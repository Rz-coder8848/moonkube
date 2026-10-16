///|
/// Kubernetes *quantities* — the fixed-point decimal numbers used for CPU,
/// memory, storage and every other resource amount.
///
/// A quantity is `<signedNumber><suffix>` where the suffix is one of
///
/// * binary SI: `Ki` (2^10), `Mi`, `Gi`, `Ti`, `Pi`, `Ei` (2^60)
/// * decimal SI: `n` (10^-9), `u` (10^-6), `m` (10^-3), none (10^0),
///   `k` (10^3), `M` (10^6), `G`, `T`, `P`, `E` (10^18)
/// * decimal exponent: `e`/`E` followed by a signed integer, e.g. `1e3`
///
/// The value is stored exactly as `coefficient * 10^exponent` with an
/// arbitrary-precision coefficient, so nothing overflows and `2Ei`, `1e100`
/// and `0.1` are all lossless. This matters because the API server compares
/// quantities *by value*, not by spelling: `1000m` and `1` are the same
/// amount, and a client that compares the raw strings gets it wrong.
///
/// `to_string` reproduces the canonical spelling of Kubernetes' own quantity
/// code: a value parsed from a binary suffix renders back in binary SI when it
/// is exactly representable (`1Gi` stays `1Gi`), everything else renders in
/// decimal SI (`1000` becomes `1k`, `1.5` becomes `1500m`).

///|
/// Which suffix family a quantity prefers when it is rendered back to text.
pub(all) enum QuantityFormat {
  // Render with decimal SI suffixes (`k`, `M`, `m`, `n`, ...).
  DecimalSI
  // Render with binary SI suffixes (`Ki`, `Mi`, ...) when exact.
  BinarySI
} derive(Eq, @debug.Debug)

///|
/// An exact Kubernetes quantity: `coefficient * 10^exponent`.
///
/// Always normalized, so the leading digit is never zero and the trailing
/// digit is never zero (for non-zero values). Use [`Quantity::compare`] for
/// value equality; the struct itself does not derive `Eq` because `1k` and
/// `1000` are the same quantity but not the same coefficient/exponent pair.
pub(all) struct Quantity {
  coefficient : BigInt
  exponent : Int
  format : QuantityFormat
} derive(@debug.Debug)

///|
/// The zero quantity.
pub fn Quantity::zero() -> Quantity {
  { coefficient: @bigint.BigInt::from_int(0), exponent: 0, format: DecimalSI, }
}

///|
/// A whole-number quantity, e.g. `2` CPUs.
pub fn Quantity::from_int(value : Int) -> Quantity {
  {
    coefficient: @bigint.BigInt::from_int(value),
    exponent: 0,
    format: DecimalSI,
  }
}

///|
/// Build a quantity from a coefficient and a power of ten, normalizing first.
pub fn Quantity::new(
  coefficient : BigInt,
  exponent : Int,
  format : QuantityFormat,
) -> Quantity {
  let (c, e) = normalize(coefficient, exponent)
  { coefficient: c, exponent: e, format, }
}

///|
/// Parse a quantity such as `100m`, `1Gi`, `1.5` or `1e3`.
///
/// The accepted grammar is slightly more permissive than the API server's: at
/// least one digit is required overall, so `.5` and `5.` are both accepted.
pub fn Quantity::parse(text : String) -> Quantity raise KubeError {
  let chars : Array[Char] = []
  for c in text {
    chars.push(c)
  }
  let n = chars.length()
  if n == 0 {
    raise KubeError::Parse("empty quantity")
  }
  let mut i = 0
  let mut negative = false
  if chars[i] == '+' || chars[i] == '-' {
    negative = chars[i] == '-'
    i = i + 1
  }
  let digits = StringBuilder()
  let mut int_count = 0
  while i < n && is_digit(chars[i]) {
    digits.write_char(chars[i])
    int_count = int_count + 1
    i = i + 1
  }
  let mut frac_count = 0
  if i < n && chars[i] == '.' {
    i = i + 1
    while i < n && is_digit(chars[i]) {
      digits.write_char(chars[i])
      frac_count = frac_count + 1
      i = i + 1
    }
  }
  if int_count + frac_count == 0 {
    raise KubeError::Parse("quantity has no digits: " + text)
  }
  let suffix_sb = StringBuilder()
  while i < n {
    suffix_sb.write_char(chars[i])
    i = i + 1
  }
  let suffix = suffix_sb.to_string()
  let mut coefficient = @bigint.BigInt::from_string(digits.to_string())
  let mut exponent = 0 - frac_count
  let mut format = DecimalSI
  match binary_multiplier(suffix) {
    Some(multiplier) => {
      coefficient = coefficient * multiplier
      format = BinarySI
    }
    None =>
      match decimal_suffix_exponent(suffix) {
        Some(e) => exponent = exponent + e
        None =>
          raise KubeError::Parse("unknown quantity suffix: '" + suffix + "'")
      }
  }
  if negative {
    coefficient = -coefficient
  }
  Quantity::new(coefficient, exponent, format)
}

///|
/// True when the quantity is exactly zero.
pub fn Quantity::is_zero(self : Quantity) -> Bool {
  self.coefficient.is_zero()
}

///|
/// Compare by value: `-1`, `0` or `1`. `1000m` and `1` compare equal.
pub fn Quantity::compare(self : Quantity, other : Quantity) -> Int {
  let (c1, e1) = normalize(self.coefficient, self.exponent)
  let (c2, e2) = normalize(other.coefficient, other.exponent)
  let s1 = c1.compare_int(0)
  let s2 = c2.compare_int(0)
  if s1 != s2 {
    return s1.compare(s2)
  }
  if s1 == 0 {
    return 0
  }
  let swapped = e1 < e2
  let (hi, he, lo, le) = if swapped {
    (c2, e2, c1, e1)
  } else {
    (c1, e1, c2, e2)
  }
  let magnitude = compare_magnitude(hi, he, lo, le)
  let result = if swapped { -magnitude } else { magnitude }
  if s1 < 0 {
    -result
  } else {
    result
  }
}

///|
/// Value equality.
pub fn Quantity::equals(self : Quantity, other : Quantity) -> Bool {
  self.compare(other) == 0
}

///|
/// Add two quantities exactly. The result keeps the binary SI preference only
/// when both operands prefer it, matching Kubernetes' own rule.
pub fn Quantity::add(self : Quantity, other : Quantity) -> Quantity {
  let (c1, e1) = normalize(self.coefficient, self.exponent)
  let (c2, e2) = normalize(other.coefficient, other.exponent)
  let format = if self.format == BinarySI && other.format == BinarySI {
    BinarySI
  } else {
    DecimalSI
  }
  if e1 >= e2 {
    Quantity::new(c1 * ten_pow(e1 - e2) + c2, e2, format)
  } else {
    Quantity::new(c1 + c2 * ten_pow(e2 - e1), e1, format)
  }
}

///|
/// The canonical spelling, as Kubernetes itself would print it.
pub fn Quantity::to_string(self : Quantity) -> String {
  let (c, e) = normalize(self.coefficient, self.exponent)
  if c.is_zero() {
    return "0"
  }
  let negative = c.compare_int(0) < 0
  let magnitude = if negative { -c } else { c }
  let body = render(magnitude, e, self.format)
  if negative {
    "-" + body
  } else {
    body
  }
}

///|
/// A JSON quantity is always a string, never a number.
pub impl ToJson for Quantity with fn to_json(self) -> Json {
  Json::string(self.to_string())
}

///|
/// Decoding accepts anything `parse` accepts and rejects JSON numbers, which
/// is what the API server does too.
pub impl FromJson for Quantity with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> Quantity raise @json.JsonDecodeError {
  match json {
    String(s) =>
      Quantity::parse(s) catch {
        _ => raise @json.JsonDecodeError((path, "not a valid quantity: " + s))
      }
    _ => raise @json.JsonDecodeError((path, "quantity must be a JSON string"))
  }
}

///|
/// Render a normalized non-negative quantity in canonical form.
fn render(
  magnitude : BigInt,
  exponent : Int,
  format : QuantityFormat,
) -> String {
  if format == BinarySI && exponent >= 0 {
    match render_binary(magnitude * ten_pow(exponent)) {
      Some(text) => return text
      None => ()
    }
  }
  let digits = magnitude.to_string()
  if exponent >= 0 {
    canonical_positive(digits, exponent)
  } else {
    canonical_negative(digits, exponent)
  }
}

///|
/// Render an integer as a binary SI suffix when 2^10k divides it exactly for
/// some `k >= 1`; `None` when no binary suffix applies.
fn render_binary(value : BigInt) -> String? {
  let mut k = 6
  while k >= 1 {
    let (divisor, suffix) = binary_step(k)
    if (value % divisor).is_zero() {
      return Some((value / divisor).to_string() + suffix)
    }
    k = k - 1
  }
  None
}

///|
/// Decimal SI rendering for a non-negative exponent.
fn canonical_positive(digits : String, exponent : Int) -> String {
  if exponent >= 18 {
    digits + zeros(exponent - 18) + "E"
  } else if exponent >= 15 {
    digits + zeros(exponent - 15) + "P"
  } else if exponent >= 12 {
    digits + zeros(exponent - 12) + "T"
  } else if exponent >= 9 {
    digits + zeros(exponent - 9) + "G"
  } else if exponent >= 6 {
    digits + zeros(exponent - 6) + "M"
  } else if exponent >= 3 {
    digits + zeros(exponent - 3) + "k"
  } else {
    digits + zeros(exponent)
  }
}

///|
/// Decimal SI rendering for a negative exponent. Values smaller than 10^-9
/// fall back to the `e` exponent form, which Kubernetes also accepts.
fn canonical_negative(digits : String, exponent : Int) -> String {
  if exponent >= -3 {
    digits + zeros(exponent + 3) + "m"
  } else if exponent >= -6 {
    digits + zeros(exponent + 6) + "u"
  } else if exponent >= -9 {
    digits + zeros(exponent + 9) + "n"
  } else {
    digits + "e" + exponent.to_string()
  }
}

///|
/// Compare two magnitudes whose exponents may differ.
///
/// The common case multiplies the larger-exponent side down to the smaller
/// exponent. When the exponents are more than 512 apart the decimal digit
/// counts already settle the ordering, so `10^diff` is never materialized —
/// comparing `1e1000000` against `1` must not build a million-digit number.
fn compare_magnitude(hi : BigInt, he : Int, lo : BigInt, le : Int) -> Int {
  let diff = he - le
  if diff > 512 {
    let hi_order = hi.to_string().length() + he
    let lo_order = lo.to_string().length() + le
    hi_order.compare(lo_order)
  } else {
    (hi * ten_pow(diff)).compare(lo)
  }
}

///|
/// Strip trailing zeros from the coefficient, folding them into the exponent.
fn normalize(coefficient : BigInt, exponent : Int) -> (BigInt, Int) {
  if coefficient.is_zero() {
    (@bigint.BigInt::from_int(0), 0)
  } else {
    let mut c = coefficient
    let mut e = exponent
    let mut reduced = true
    while reduced {
      if (c % ten()).is_zero() {
        c = c / ten()
        e = e + 1
      } else {
        reduced = false
      }
    }
    (c, e)
  }
}

///|
fn ten() -> BigInt {
  @bigint.BigInt::from_string("10")
}

///|
/// `10^k` as an exact integer.
fn ten_pow(k : Int) -> BigInt {
  @bigint.BigInt::from_string("1" + zeros(k))
}

///|
/// A string of `count` zeros.
fn zeros(count : Int) -> String {
  if count <= 0 {
    ""
  } else if count <= 16 {
    "0000000000000000"[:count].to_owned()
  } else {
    zeros(16) + zeros(count - 16)
  }
}

///|
fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
/// The exact multiplier and suffix for the `k`-th binary SI step.
fn binary_step(k : Int) -> (BigInt, String) {
  match k {
    1 => (@bigint.BigInt::from_string("1024"), "Ki")
    2 => (@bigint.BigInt::from_string("1048576"), "Mi")
    3 => (@bigint.BigInt::from_string("1073741824"), "Gi")
    4 => (@bigint.BigInt::from_string("1099511627776"), "Ti")
    5 => (@bigint.BigInt::from_string("1125899906842624"), "Pi")
    _ => (@bigint.BigInt::from_string("1152921504606846976"), "Ei")
  }
}

///|
/// The multiplier for a binary SI suffix, or `None`.
fn binary_multiplier(suffix : String) -> BigInt? {
  match suffix {
    "Ki" => Some(@bigint.BigInt::from_string("1024"))
    "Mi" => Some(@bigint.BigInt::from_string("1048576"))
    "Gi" => Some(@bigint.BigInt::from_string("1073741824"))
    "Ti" => Some(@bigint.BigInt::from_string("1099511627776"))
    "Pi" => Some(@bigint.BigInt::from_string("1125899906842624"))
    "Ei" => Some(@bigint.BigInt::from_string("1152921504606846976"))
    _ => None
  }
}

///|
/// The power of ten for a decimal SI suffix, or for an `e`/`E` exponent.
fn decimal_suffix_exponent(suffix : String) -> Int? {
  match suffix {
    "" => Some(0)
    "n" => Some(-9)
    "u" => Some(-6)
    "m" => Some(-3)
    "k" => Some(3)
    "M" => Some(6)
    "G" => Some(9)
    "T" => Some(12)
    "P" => Some(15)
    "E" => Some(18)
    _ => exponent_suffix(suffix)
  }
}

///|
/// `e3` / `E-9` style suffixes: `e` or `E` followed by a signed integer.
fn exponent_suffix(suffix : String) -> Int? {
  let chars : Array[Char] = []
  for c in suffix {
    chars.push(c)
  }
  let n = chars.length()
  if n < 2 || (chars[0] != 'e' && chars[0] != 'E') {
    return None
  }
  let sb = StringBuilder()
  let mut i = 1
  while i < n {
    sb.write_char(chars[i])
    i = i + 1
  }
  let body = sb.to_string()
  Some(@string.parse_int(body)) catch {
    _ => None
  }
}

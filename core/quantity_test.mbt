///|
/// Blackbox tests for quantities: the public API, driven the way an external
/// consumer would — through `@core` only, never through package internals.

///|
/// Parse `text` and render it back canonically, or `<error>` when invalid.
fn canonical(text : String) -> String {
  @core.Quantity::parse(text).to_string() catch {
    _ => "<error>"
  }
}

///|
fn compare_of(a : String, b : String) -> Int {
  @core.Quantity::parse(a).compare(@core.Quantity::parse(b)) catch {
    _ => 99
  }
}

///|
fn add_of(a : String, b : String) -> String {
  @core.Quantity::parse(a).add(@core.Quantity::parse(b)).to_string() catch {
    _ => "<error>"
  }
}

///|
fn rejected(text : String) -> Bool {
  try {
    let _ = @core.Quantity::parse(text)
    false
  } catch {
    _ => true
  }
}

///|
/// The canonical spelling matches what the API server itself would print,
/// including keeping binary SI spelling for exactly representable values.
test "canonical spellings" {
  assert_eq(canonical("1"), "1")
  assert_eq(canonical("0"), "0")
  assert_eq(canonical("100m"), "100m")
  assert_eq(canonical("1.5"), "1500m")
  assert_eq(canonical("1000"), "1k")
  assert_eq(canonical("1e3"), "1k")
  assert_eq(canonical("1G"), "1G")
  assert_eq(canonical("-100m"), "-100m")
  assert_eq(canonical("1n"), "1n")
  assert_eq(canonical("1e-10"), "1e-10")
  assert_eq(canonical("1000000"), "1M")
  assert_eq(canonical("1000000000"), "1G")
  assert_eq(canonical("1e18"), "1E")
  assert_eq(canonical("1e19"), "10E")
  assert_eq(canonical("1Mi"), "1Mi")
  assert_eq(canonical("1Gi"), "1Gi")
  assert_eq(canonical("1.5Gi"), "1536Mi")
  assert_eq(canonical("2Ei"), "2Ei")
  assert_eq(canonical("1500Ki"), "1500Ki")
  assert_eq(canonical("0.5Ki"), "512")
}

///|
/// Malformed quantities must be rejected rather than silently coerced.
test "invalid quantities are rejected" {
  assert_true(rejected(""))
  assert_true(rejected("abc"))
  assert_true(rejected("Mi"))
  assert_true(rejected("1KiB"))
  assert_true(rejected("1.2.3"))
  assert_true(rejected("1e"))
  assert_true(rejected("1e+"))
  assert_true(rejected("1e1x"))
  assert_true(rejected("12x"))
  assert_true(rejected("1 E"))
}

///|
/// Comparison is by value, which is the whole point: the API server treats
/// `1000m` and `1` as the same amount.
test "comparison is by value" {
  assert_eq(compare_of("1000m", "1"), 0)
  assert_eq(compare_of("100m", "0.1"), 0)
  assert_eq(compare_of("1Ki", "1k"), 1)
  assert_eq(compare_of("1M", "1Mi"), -1)
  assert_eq(compare_of("-1", "0"), -1)
  assert_eq(compare_of("0", "0"), 0)
  assert_eq(compare_of("1e100", "1"), 1)
  assert_eq(compare_of("1e100", "1e100"), 0)
  assert_eq(compare_of("-1e100", "1"), -1)
}

///|
/// Addition is exact and keeps the binary spelling only when both sides
/// prefer it, mirroring Kubernetes' own rule.
test "addition is exact" {
  assert_eq(add_of("1", "500m"), "1500m")
  assert_eq(add_of("250m", "250m"), "500m")
  assert_eq(add_of("1", "-1"), "0")
  assert_eq(add_of("1Gi", "1Gi"), "2Gi")
  assert_eq(add_of("1k", "1Ki"), "2024")
}

///|
/// On the wire a quantity is always a JSON string, never a number.
test "quantity JSON is a string" {
  let encoded = @json.to_json(@core.Quantity::parse("100m")).stringify() catch {
    _ => "<error>"
  }
  assert_eq(encoded, "\"100m\"")
  let decoded = try {
    let q : @core.Quantity = @json.from_json(@json.parse("\"1Gi\""))
    q.to_string()
  } catch {
    _ => "<error>"
  }
  assert_eq(decoded, "1Gi")
  let number_rejected = try {
    let _ : @core.Quantity = @json.from_json(@json.parse("5"))
    false
  } catch {
    _ => true
  }
  assert_true(number_rejected)
  let garbage_rejected = try {
    let _ : @core.Quantity = @json.from_json(@json.parse("\"1KiB\""))
    false
  } catch {
    _ => true
  }
  assert_true(garbage_rejected)
}

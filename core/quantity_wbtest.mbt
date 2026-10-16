///|
/// Whitebox tests: internals that the public surface hides.

///|
/// Normalization folds trailing zeros into the exponent, so two spellings of
/// the same amount end up with identical coefficient/exponent pairs.
test "normalize folds trailing zeros" {
  let a = normalize(@bigint.BigInt::from_string("1500"), 0)
  let b = normalize(@bigint.BigInt::from_string("15"), 2)
  assert_eq(a, b)
  assert_eq(a, (@bigint.BigInt::from_string("15"), 2))
}

///|
/// Zero normalizes to coefficient 0 with exponent 0, whatever it came in as.
test "normalize zeroes" {
  assert_eq(normalize(@bigint.BigInt::from_int(0), 7).1, 0)
  assert_true(normalize(@bigint.BigInt::from_int(0), 7).0.is_zero())
}

///|
/// `zeros` is recursive over blocks of 16 and must not lose or duplicate a
/// digit at the block boundary.
test "zeros block boundary" {
  assert_eq(zeros(0), "")
  assert_eq(zeros(1), "0")
  assert_eq(zeros(16), "0000000000000000")
  assert_eq(zeros(17).length(), 17)
  assert_eq(zeros(33).length(), 33)
  assert_eq(zeros(-3), "")
}

///|
/// `10^k` is exact for exponents well past 64-bit range.
test "ten_pow is arbitrary precision" {
  assert_eq(ten_pow(0).to_string(), "1")
  assert_eq(ten_pow(3).to_string(), "1000")
  assert_eq(ten_pow(30).to_string(), "1" + zeros(30))
}

///|
/// The comparison guard must kick in for huge exponent gaps: building
/// `10^1000000` would be a memory disaster, so ordering is settled by digit
/// count instead.
test "compare guard on huge exponent gap" {
  let huge = Quantity::new(@bigint.BigInt::from_int(1), 1000000, DecimalSI)
  let one = Quantity::new(@bigint.BigInt::from_int(1), 0, DecimalSI)
  assert_eq(huge.compare(one), 1)
  assert_eq(one.compare(huge), -1)
}

///|
/// A binary step table entry must be exactly 2^(10k).
test "binary step table is exact powers of two" {
  let mut k = 1
  let mut expected = @bigint.BigInt::from_int(1)
  let two = @bigint.BigInt::from_int(2)
  while k <= 6 {
    let mut i = 0
    while i < 10 {
      expected = expected * two
      i = i + 1
    }
    assert_eq(binary_step(k).0, expected)
    k = k + 1
  }
}

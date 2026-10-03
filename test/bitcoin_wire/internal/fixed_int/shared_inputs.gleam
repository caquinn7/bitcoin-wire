pub const zero_bytes = <<0, 0, 0, 0, 0, 0, 0, 0>>

pub const one_bytes = <<1, 0, 0, 0, 0, 0, 0, 0>>

/// 2^32
pub const two_to_32 = 4_294_967_296

/// 2^32
pub const two_to_32_bytes = <<0, 0, 0, 0, 1, 0, 0, 0>>

/// 2^53 - 1
pub const max_safe_js_int = 9_007_199_254_740_991

/// 2^53 - 1
pub const max_safe_js_int_bytes = <<
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0x1F,
  0,
>>

/// 2^53
pub const max_safe_js_int_plus_one_bytes = <<
  0,
  0,
  0,
  0,
  0,
  0,
  0x20,
  0,
>>

/// Signed values at and immediately outside JavaScript's safe integer bounds.
/// Each row contains wire bytes, exact decimal text, and JavaScript safety.
pub const signed_safe_integer_boundaries = [
  #(max_safe_js_int_bytes, "9007199254740991", True),
  #(<<0x01, 0, 0, 0, 0, 0, 0xE0, 0xFF>>, "-9007199254740991", True),
  #(max_safe_js_int_plus_one_bytes, "9007199254740992", False),
  #(<<0, 0, 0, 0, 0, 0, 0xE0, 0xFF>>, "-9007199254740992", False),
  #(<<0x01, 0, 0, 0, 0, 0, 0x20, 0>>, "9007199254740993", False),
  #(
    <<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xDF, 0xFF>>,
    "-9007199254740993",
    False,
  ),
]

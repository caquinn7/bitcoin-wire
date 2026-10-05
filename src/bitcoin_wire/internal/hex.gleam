import gleam/bit_array
import gleam/bool
import gleam/int
import gleam/result

pub type DecodeError {
  InvalidHex
  SizeLimitExceeded(actual: Int, limit: Int)
}

/// Convert hex only when its implied byte size fits the supplied limit.
///
/// Oversized input is validated without constructing decoded bytes, so invalid
/// hex still takes precedence over a size error. Within-limit input is validated
/// and converted together by the standard library.
pub fn decode_with_max_size(
  hex: String,
  max_size: Int,
) -> Result(BitArray, DecodeError) {
  let length = native_length(hex)
  use <- bool.guard(int.is_odd(length), Error(InvalidHex))

  let size = length / 2
  case size > max_size {
    True ->
      case has_only_hex_digits(hex) {
        True -> Error(SizeLimitExceeded(actual: size, limit: max_size))
        False -> Error(InvalidHex)
      }
    False ->
      hex
      |> bit_array.base16_decode
      |> result.replace_error(InvalidHex)
  }
}

/// Return the string's native length without copying it.
///
/// Counts UTF-8 bytes on Erlang and UTF-16 code units on JavaScript. Valid hex is
/// ASCII, so these lengths agree. Only report an oversized input's implied byte
/// size after validating its characters.
@external(erlang, "erlang", "byte_size")
@external(javascript, "./hex_ffi.mjs", "native_length")
fn native_length(hex: String) -> Int

/// Return whether the string contains only ASCII hexadecimal digits.
///
/// Accepts `0`–`9`, `A`–`F`, and `a`–`f` without constructing decoded bytes.
/// Returns `True` for an empty string. It does not check whether the length is
/// even; the caller must check that before converting the string to bytes.
@external(erlang, "hex_ffi", "has_only_hex_digits")
@external(javascript, "./hex_ffi.mjs", "has_only_hex_digits")
fn has_only_hex_digits(hex: String) -> Bool

import bitcoin_wire/hash256.{InvalidBitCount}
import gleam/string
import support/offset_bit_array

pub fn from_bytes_le_reports_incorrect_bit_counts_test() {
  assert Error(InvalidBitCount(actual: 0, expected: 256))
    == hash256.from_bytes_le(<<>>)

  assert Error(InvalidBitCount(actual: 248, expected: 256))
    == hash256.from_bytes_le(<<1:little-size({ 31 * 8 })>>)

  assert Error(InvalidBitCount(actual: 255, expected: 256))
    == hash256.from_bytes_le(<<0:255>>)

  assert Error(InvalidBitCount(actual: 257, expected: 256))
    == hash256.from_bytes_le(<<0:257>>)

  assert Error(InvalidBitCount(actual: 264, expected: 256))
    == hash256.from_bytes_le(<<1:little-size({ 33 * 8 })>>)
}

pub fn from_bytes_le_returns_ok_when_input_is_32_bytes_test() {
  let assert Ok(_) = hash256.from_bytes_le(<<1:little-size({ 32 * 8 })>>)
}

pub fn to_bytes_le_preserves_original_bytes_test() {
  let bytes = <<1:little-size({ 32 * 8 })>>
  let assert Ok(hash) = hash256.from_bytes_le(bytes)

  assert hash256.to_bytes_le(hash) == bytes
}

pub fn to_bytes_le_preserves_offset_bytes_test() {
  let bytes = <<
    0x00,
    0x01,
    0x02,
    0x03,
    0x04,
    0x05,
    0x06,
    0x07,
    0x08,
    0x09,
    0x0A,
    0x0B,
    0x0C,
    0x0D,
    0x0E,
    0x0F,
    0x10,
    0x11,
    0x12,
    0x13,
    0x14,
    0x15,
    0x16,
    0x17,
    0x18,
    0x19,
    0x1A,
    0x1B,
    0x1C,
    0x1D,
    0x1E,
    0x1F,
  >>
  let view = offset_bit_array.with_one_bit_offset(bytes)
  let assert Ok(hash) = hash256.from_bytes_le(view)

  assert hash256.to_bytes_le(hash) == bytes
}

pub fn to_display_hex_reverses_wire_order_bytes_test() {
  let assert Ok(hash) = hash256.from_bytes_le(<<0x12, 0x34, 0:size(240)>>)

  let expected = string.repeat("0", 60) <> "3412"
  assert hash256.to_display_hex(hash) == expected
}

pub fn to_display_hex_uses_lowercase_hex_test() {
  let assert Ok(hash) = hash256.from_bytes_le(<<0:248, 0xAB>>)

  let expected = "ab" <> string.repeat("0", 62)
  assert hash256.to_display_hex(hash) == expected
}

pub fn to_display_hex_formats_zero_as_64_characters_test() {
  let assert Ok(hash) = hash256.from_bytes_le(<<0:256>>)
  let display = hash256.to_display_hex(hash)

  assert display == string.repeat("0", 64)
  assert string.length(display) == 64
}

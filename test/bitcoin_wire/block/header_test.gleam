import bitcoin_wire/block.{
  HeaderDecodeFailed, InvalidHeaderBitCount, InvalidHeaderHex,
}
import bitcoin_wire/hash256
import gleam/bit_array
import gleam/crypto.{Sha256}
import support/bitcoin_wire

// ============================================================================
// deserialize_header
// ============================================================================

pub fn deserialize_header_decodes_exact_640_bits_and_preserves_all_fields_test() {
  let previous_block_hash = <<0x01, 0:size(240), 0x02>>
  let merkle_root = <<0x03, 0:size(240), 0x04>>
  let timestamp = 0x80000000
  let target = 0xFEDCBA98
  let nonce = 0xFFFFFFFF
  let header_bytes =
    bitcoin_wire.build_block_header_bytes(
      -1,
      previous_block_hash,
      merkle_root,
      timestamp,
      target,
      nonce,
    )

  assert bit_array.bit_size(header_bytes) == 640

  let assert Ok(header) = block.deserialize_header(header_bytes)

  assert block.get_header_version(header) == -1
  assert header
    |> block.get_header_previous_block_hash
    |> hash256.to_bytes_le
    == previous_block_hash
  assert header
    |> block.get_header_merkle_root
    |> hash256.to_bytes_le
    == merkle_root
  assert block.get_header_timestamp(header) == timestamp
  assert block.get_header_target(header) == target
  assert block.get_header_nonce(header) == nonce
  assert block.serialize_header(header) == header_bytes
}

pub fn deserialize_header_rejects_every_incorrect_required_bit_count_test() {
  assert block.deserialize_header(<<0:632>>)
    == Error(InvalidHeaderBitCount(actual: 632, expected: 640))

  assert block.deserialize_header(<<0:639>>)
    == Error(InvalidHeaderBitCount(actual: 639, expected: 640))

  assert block.deserialize_header(<<0:641>>)
    == Error(InvalidHeaderBitCount(actual: 641, expected: 640))

  assert block.deserialize_header(<<0:648>>)
    == Error(InvalidHeaderBitCount(actual: 648, expected: 640))
}

// ============================================================================
// deserialize_header_hex
// ============================================================================

pub fn deserialize_header_hex_distinguishes_invalid_hex_from_wrong_size_test() {
  assert block.deserialize_header_hex("00zz") == Error(InvalidHeaderHex)
  assert block.deserialize_header_hex("0") == Error(InvalidHeaderHex)

  let wrong_sized_header_hex = bit_array.base16_encode(<<0:632>>)

  assert block.deserialize_header_hex(wrong_sized_header_hex)
    == Error(
      HeaderDecodeFailed(InvalidHeaderBitCount(actual: 632, expected: 640)),
    )
}

pub fn deserialize_header_hex_decodes_a_valid_header_test() {
  let header_bytes = sample_header_bytes()

  let assert Ok(header) =
    header_bytes
    |> bit_array.base16_encode
    |> block.deserialize_header_hex

  assert block.serialize_header(header) == header_bytes
}

// ============================================================================
// Header hashing
// ============================================================================

pub fn compute_block_hash_matches_genesis_display_and_manual_dsha256_test() {
  let genesis_header_bytes = <<
    1:32-little,
    0:size(256),
    0x3B,
    0xA3,
    0xED,
    0xFD,
    0x7A,
    0x7B,
    0x12,
    0xB2,
    0x7A,
    0xC7,
    0x2C,
    0x3E,
    0x67,
    0x76,
    0x8F,
    0x61,
    0x7F,
    0xC8,
    0x1B,
    0xC3,
    0x88,
    0x8A,
    0x51,
    0x32,
    0x3A,
    0x9F,
    0xB8,
    0xAA,
    0x4B,
    0x1E,
    0x5E,
    0x4A,
    1_231_006_505:32-little,
    0x1D00FFFF:32-little,
    2_083_236_893:32-little,
  >>

  let assert Ok(header) = block.deserialize_header(genesis_header_bytes)
  let expected_hash =
    genesis_header_bytes
    |> crypto.hash(Sha256, _)
    |> crypto.hash(Sha256, _)
  let actual_hash = block.compute_block_hash(header)

  assert block.serialize_header(header) == genesis_header_bytes
  assert hash256.to_bytes_le(actual_hash) == expected_hash
  assert hash256.to_display_hex(actual_hash)
    == "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f"
}

pub fn compute_block_hash_hashes_a_header_from_a_complete_block_test() {
  let header_bytes = sample_header_bytes()
  let assert Ok(parsed_block) =
    block.deserialize(bitcoin_wire.assemble_block_bytes(header_bytes, []))
  let expected_hash =
    header_bytes
    |> crypto.hash(Sha256, _)
    |> crypto.hash(Sha256, _)

  assert block.compute_block_hash(block.get_header(parsed_block))
    |> hash256.to_bytes_le
    == expected_hash
}

fn sample_header_bytes() -> BitArray {
  bitcoin_wire.build_block_header_bytes(
    2,
    <<0x01, 0:size(240), 0x02>>,
    <<0x03, 0:size(240), 0x04>>,
    1_234_567_890,
    0x1D00FFFF,
    2_083_236_893,
  )
}

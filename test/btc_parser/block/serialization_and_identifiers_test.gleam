import btc_parser/block
import btc_parser/hash256
import gleam/crypto.{Sha256}
import gleam/list
import support/bitcoin_wire

// ============================================================================
// serialize_header
// ============================================================================

pub fn serialize_header_round_trips_parsed_header_bytes_test() {
  // The serializer must reproduce the exact 80-byte header accepted by the
  // deserializer.
  let header_bytes =
    bitcoin_wire.build_block_header_bytes(
      2,
      <<0x01, 0:size(240), 0x02>>,
      <<0x03, 0:size(240), 0x04>>,
      1_234_567_890,
      0x1D00FFFF,
      2_083_236_893,
    )

  let assert Ok(block) =
    block.deserialize(bitcoin_wire.assemble_block_bytes(header_bytes, []))

  assert block
    |> block.get_header
    |> block.serialize_header
    == header_bytes
}

pub fn serialize_header_encodes_signed_version_bit_pattern_test() {
  // Negative versions must retain their original signed 32-bit wire encoding.
  let block_bytes =
    bitcoin_wire.build_header_only_block_bytes(
      -1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      0,
      0,
      0,
    )

  let assert Ok(block) = block.deserialize(block_bytes)

  let serialized_header =
    block
    |> block.get_header
    |> block.serialize_header

  let assert <<0xFF, 0xFF, 0xFF, 0xFF, _:bytes>> = serialized_header
}

pub fn serialize_header_encodes_unsigned_u32_values_from_int_test() {
  // Unsigned values above the signed 32-bit range must encode as four little-endian bytes.
  let block_bytes =
    bitcoin_wire.build_header_only_block_bytes(
      1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      0x80000000,
      0xFEDCBA98,
      0xFFFFFFFF,
    )
  let assert Ok(block) = block.deserialize(block_bytes)

  let serialized_header =
    block
    |> block.get_header
    |> block.serialize_header

  let assert <<
    _:bytes-size(68),
    0x00,
    0x00,
    0x00,
    0x80,
    0x98,
    0xBA,
    0xDC,
    0xFE,
    0xFF,
    0xFF,
    0xFF,
    0xFF,
  >> = serialized_header
}

// ============================================================================
// serialize
// ============================================================================

pub fn serialize_encodes_zero_transaction_count_without_payload_test() {
  // An empty transaction list must add only a CompactSize zero after the header.
  let block_bytes =
    bitcoin_wire.build_header_only_block_bytes(
      1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      0,
      0,
      0,
    )

  let assert Ok(block) = block.deserialize(block_bytes)

  let assert <<_:bytes-size(80), 0>> = block.serialize(block)
}

pub fn serialize_preserves_transaction_wire_order_test() {
  // Block serialization must concatenate contained transactions without reordering them.
  let first_tx = bitcoin_wire.build_minimal_legacy_transaction_bytes(1)
  let second_tx = bitcoin_wire.build_minimal_legacy_transaction_bytes(2)
  let header =
    bitcoin_wire.build_block_header_bytes(
      1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      0,
      0,
      0,
    )
  let assert Ok(block) =
    block.deserialize(
      bitcoin_wire.assemble_block_bytes(header, [first_tx, second_tx]),
    )

  let assert <<_:bytes-size(80), serialized_payload:bytes>> =
    block.serialize(block)

  assert serialized_payload == <<2, first_tx:bits, second_tx:bits>>
}

pub fn serialize_includes_segwit_witness_data_test() {
  // SegWit transactions must use their full wire form rather than stripped bytes.
  let input = bitcoin_wire.build_input_bytes(<<0:size(256)>>, 0, <<>>, 0)
  let output = bitcoin_wire.build_output_bytes(<<0:little-size(64)>>, <<>>)
  let witness_stack = <<
    bitcoin_wire.compact_size(1):bits,
    bitcoin_wire.compact_size(3):bits,
    0xAA,
    0xBB,
    0xCC,
  >>
  let segwit_tx =
    bitcoin_wire.assemble_segwit_transaction_bytes([input], [output], [
      witness_stack,
    ])
  let header =
    bitcoin_wire.build_block_header_bytes(
      1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      0,
      0,
      0,
    )
  let assert Ok(block) =
    block.deserialize(bitcoin_wire.assemble_block_bytes(header, [segwit_tx]))

  let assert <<_:bytes-size(80), 1, serialized_tx:bytes>> =
    block.serialize(block)

  assert serialized_tx == segwit_tx
}

pub fn serialize_encodes_multibyte_compact_size_transaction_count_test() {
  // The transaction count must use minimal CompactSize at the first multibyte boundary.
  let tx_count = 253
  let txs =
    list.repeat(
      bitcoin_wire.build_minimal_legacy_transaction_bytes(1),
      tx_count,
    )
  let header =
    bitcoin_wire.build_block_header_bytes(
      1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      0,
      0,
      0,
    )
  let assert Ok(block) =
    block.deserialize(bitcoin_wire.assemble_block_bytes(header, txs))

  let assert <<_:bytes-size(80), 0xFD, 0xFD, 0x00, _:bytes>> =
    block.serialize(block)
}

// ============================================================================
// Block size and weight computation
// ============================================================================

pub fn compute_sizes_and_weight_for_empty_block_test() {
  let bytes =
    bitcoin_wire.build_header_only_block_bytes(
      1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      0,
      0,
      0,
    )
  let assert Ok(block) = block.deserialize(bytes)

  assert block.compute_base_size(block) == 81
  assert block.compute_total_size(block) == 81
  assert block.compute_weight(block) == 324
  assert block.compute_virtual_size(block) == 81
}

pub fn compute_sizes_and_weight_for_one_minimal_legacy_transaction_test() {
  let header =
    bitcoin_wire.build_block_header_bytes(
      1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      0,
      0,
      0,
    )
  let tx = bitcoin_wire.build_minimal_legacy_transaction_bytes(1)
  let assert Ok(block) =
    block.deserialize(bitcoin_wire.assemble_block_bytes(header, [tx]))

  assert block.compute_base_size(block) == 141
  assert block.compute_total_size(block) == 141
  assert block.compute_weight(block) == 564
  assert block.compute_virtual_size(block) == 141
}

pub fn compute_sizes_and_weight_for_one_segwit_transaction_with_witness_data_test() {
  let input = bitcoin_wire.build_input_bytes(<<0:size(256)>>, 0, <<>>, 0)
  let output = bitcoin_wire.build_output_bytes(<<0:little-size(64)>>, <<>>)
  let witness_stack = <<
    bitcoin_wire.compact_size(1):bits,
    bitcoin_wire.compact_size(3):bits,
    0xAA,
    0xBB,
    0xCC,
  >>
  let tx =
    bitcoin_wire.assemble_segwit_transaction_bytes([input], [output], [
      witness_stack,
    ])
  let header =
    bitcoin_wire.build_block_header_bytes(
      1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      0,
      0,
      0,
    )
  let assert Ok(block) =
    block.deserialize(bitcoin_wire.assemble_block_bytes(header, [tx]))

  assert block.compute_base_size(block) == 141
  assert block.compute_total_size(block) == 148
  assert block.compute_weight(block) == 571
  assert block.compute_virtual_size(block) == 143
}

pub fn compute_sizes_and_weight_for_253_minimal_legacy_transactions_test() {
  let tx_count = 253
  let txs =
    list.repeat(
      bitcoin_wire.build_minimal_legacy_transaction_bytes(1),
      tx_count,
    )
  let header =
    bitcoin_wire.build_block_header_bytes(
      1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      0,
      0,
      0,
    )
  let assert Ok(block) =
    block.deserialize(bitcoin_wire.assemble_block_bytes(header, txs))

  assert block.compute_base_size(block) == 15_263
  assert block.compute_total_size(block) == 15_263
  assert block.compute_weight(block) == 61_052
  assert block.compute_virtual_size(block) == 15_263
}

// ============================================================================
// compute_block_hash
// ============================================================================

pub fn compute_block_hash_matches_manual_dsha256_test() {
  // A block hash covers exactly the 80-byte header, excluding all transaction data.
  let header_bytes =
    bitcoin_wire.build_block_header_bytes(
      2,
      <<0x01, 0:size(240), 0x02>>,
      <<0x03, 0:size(240), 0x04>>,
      1_234_567_890,
      0x1D00FFFF,
      2_083_236_893,
    )
  let tx = bitcoin_wire.build_minimal_legacy_transaction_bytes(1)
  let assert Ok(block) =
    block.deserialize(bitcoin_wire.assemble_block_bytes(header_bytes, [tx]))

  let expected_hash =
    header_bytes
    |> crypto.hash(Sha256, _)
    |> crypto.hash(Sha256, _)

  assert block
    |> block.compute_block_hash
    |> hash256.to_bytes_le
    == expected_hash
}

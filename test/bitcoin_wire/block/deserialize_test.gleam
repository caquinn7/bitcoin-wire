import bitcoin_wire/block.{
  DecodeFailed, InsufficientBytes, IntegerOutOfRange, InvalidHex,
  NonByteAlignedInput, NonMinimalCompactSize, TrailingBytes,
  TransactionDecodeFailed, UnexpectedEof,
}
import bitcoin_wire/hash256
import bitcoin_wire/transaction
import gleam/bit_array
import gleam/list
import support/bitcoin_wire
import support/decode_assertions
import support/target

// ============================================================================
// Header and empty-block deserialization success
// ============================================================================

pub fn deserialize_accepts_header_only_block_with_zero_transactions_test() {
  let bytes =
    bitcoin_wire.build_header_only_block_bytes(
      1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      1_234_567_890,
      0x1D00FFFF,
      2_083_236_893,
    )

  let assert Ok(block) = block.deserialize(bytes)
  assert block.get_transaction_count(block) == 0
  assert block.get_transactions(block) == []
}

pub fn deserialize_preserves_signed_header_version_test() {
  let bytes =
    bitcoin_wire.build_header_only_block_bytes(
      -1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      0,
      0,
      0,
    )

  let assert Ok(block) = block.deserialize(bytes)

  assert block
    |> block.get_header
    |> block.get_header_version
    == -1
}

pub fn deserialize_preserves_header_hashes_in_wire_order_test() {
  let previous_block_hash = <<0x01, 0:size(240), 0x02>>
  let merkle_root = <<0x03, 0:size(240), 0x04>>
  let bytes =
    bitcoin_wire.build_header_only_block_bytes(
      1,
      previous_block_hash,
      merkle_root,
      0,
      0,
      0,
    )

  let assert Ok(block) = block.deserialize(bytes)
  let header = block.get_header(block)

  assert header
    |> block.get_header_previous_block_hash
    |> hash256.to_bytes_le
    == previous_block_hash

  assert header
    |> block.get_header_merkle_root
    |> hash256.to_bytes_le
    == merkle_root
}

pub fn deserialize_preserves_unsigned_header_timestamp_target_and_nonce_test() {
  let timestamp = 2_147_483_648
  let target = 4_294_967_295
  let nonce = 4_026_531_840
  let bytes =
    bitcoin_wire.build_header_only_block_bytes(
      1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      timestamp,
      target,
      nonce,
    )

  let assert Ok(block) = block.deserialize(bytes)
  let header = block.get_header(block)

  assert block.get_header_timestamp(header) == timestamp
  assert block.get_header_target(header) == target
  assert block.get_header_nonce(header) == nonce
}

// ============================================================================
// Transaction deserialization success
// ============================================================================

pub fn deserialize_accepts_block_with_one_legacy_transaction_test() {
  let header =
    bitcoin_wire.build_block_header_bytes(
      1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      0,
      0,
      0,
    )
  let bytes =
    bitcoin_wire.assemble_block_bytes(header, [
      bitcoin_wire.build_minimal_legacy_transaction_bytes(1),
    ])

  let assert Ok(block) = block.deserialize(bytes)
  let assert [tx] = block.get_transactions(block)

  assert block.get_transaction_count(block) == 1
  assert !transaction.is_segwit(tx)
}

pub fn deserialize_accepts_block_with_one_segwit_transaction_test() {
  let header =
    bitcoin_wire.build_block_header_bytes(
      1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      0,
      0,
      0,
    )
  let bytes =
    bitcoin_wire.assemble_block_bytes(header, [
      bitcoin_wire.build_minimal_segwit_transaction_bytes(),
    ])

  let assert Ok(block) = block.deserialize(bytes)
  let assert [tx] = block.get_transactions(block)

  assert block.get_transaction_count(block) == 1
  assert transaction.is_segwit(tx)
}

pub fn deserialize_preserves_multiple_transactions_in_wire_order_test() {
  let header =
    bitcoin_wire.build_block_header_bytes(
      1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      0,
      0,
      0,
    )
  let bytes =
    bitcoin_wire.assemble_block_bytes(header, [
      bitcoin_wire.build_minimal_legacy_transaction_bytes(1),
      bitcoin_wire.build_minimal_legacy_transaction_bytes(2),
    ])

  let assert Ok(block) = block.deserialize(bytes)
  let assert [first_tx, second_tx] = block.get_transactions(block)

  assert block.get_transaction_count(block) == 2
  assert transaction.get_version(first_tx) == 1
  assert transaction.get_version(second_tx) == 2
}

pub fn deserialize_preserves_multibyte_compact_size_transaction_count_test() {
  let header =
    bitcoin_wire.build_block_header_bytes(
      1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      0,
      0,
      0,
    )
  let tx_count = 253
  let txs =
    list.repeat(
      bitcoin_wire.build_minimal_legacy_transaction_bytes(1),
      tx_count,
    )
  let bytes = bitcoin_wire.assemble_block_bytes(header, txs)

  let assert Ok(block) = block.deserialize(bytes)

  assert block.get_transaction_count(block) == tx_count
  assert list.length(block.get_transactions(block)) == tx_count
}

// ============================================================================
// Input shape errors
// ============================================================================

pub fn deserialize_rejects_non_byte_aligned_input_test() {
  let aligned =
    bitcoin_wire.build_header_only_block_bytes(
      1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      0,
      0,
      0,
    )
  let unaligned = <<aligned:bits, 1:size(1)>>

  let assert Error(error) = block.deserialize(unaligned)

  assert decode_assertions.check_block_decode_error(error, 0, "block")
    == NonByteAlignedInput(bit_array.bit_size(unaligned))
}

// ============================================================================
// Header errors
// ============================================================================

pub fn deserialize_errors_when_header_version_is_truncated_test() {
  let assert Error(error) = block.deserialize(<<0x01, 0x02, 0x03>>)

  assert decode_assertions.check_block_decode_error(
      error,
      0,
      "block.header.version",
    )
    == UnexpectedEof(bytes_needed: 4, remaining: 3)
}

pub fn deserialize_errors_when_previous_block_hash_is_truncated_test() {
  let assert Error(error) = block.deserialize(<<1:32-little, 0:size(248)>>)

  assert decode_assertions.check_block_decode_error(
      error,
      4,
      "block.header.previous_block_hash",
    )
    == UnexpectedEof(bytes_needed: 32, remaining: 31)
}

pub fn deserialize_errors_when_merkle_root_is_truncated_test() {
  let assert Error(error) =
    block.deserialize(<<1:32-little, 0:size(256), 0:size(248)>>)

  assert decode_assertions.check_block_decode_error(
      error,
      36,
      "block.header.merkle_root",
    )
    == UnexpectedEof(bytes_needed: 32, remaining: 31)
}

pub fn deserialize_errors_when_header_timestamp_is_truncated_test() {
  let assert Error(error) =
    block.deserialize(<<1:32-little, 0:size(256), 0:size(256), 0:size(24)>>)

  assert decode_assertions.check_block_decode_error(
      error,
      68,
      "block.header.timestamp",
    )
    == UnexpectedEof(bytes_needed: 4, remaining: 3)
}

pub fn deserialize_errors_when_header_target_is_truncated_test() {
  let assert Error(error) =
    block.deserialize(<<
      1:32-little,
      0:size(256),
      0:size(256),
      0:32-little,
      0:size(24),
    >>)

  assert decode_assertions.check_block_decode_error(
      error,
      72,
      "block.header.target",
    )
    == UnexpectedEof(bytes_needed: 4, remaining: 3)
}

pub fn deserialize_errors_when_header_nonce_is_truncated_test() {
  let assert Error(error) =
    block.deserialize(<<
      1:32-little,
      0:size(256),
      0:size(256),
      0:32-little,
      0:32-little,
      0:size(24),
    >>)

  assert decode_assertions.check_block_decode_error(
      error,
      76,
      "block.header.nonce",
    )
    == UnexpectedEof(bytes_needed: 4, remaining: 3)
}

// ============================================================================
// Transaction-count errors
// ============================================================================

pub fn deserialize_errors_when_transaction_count_is_missing_test() {
  let header =
    bitcoin_wire.build_block_header_bytes(
      1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      0,
      0,
      0,
    )

  let assert Error(error) = block.deserialize(header)

  assert decode_assertions.check_block_decode_error(
      error,
      80,
      "block.transactions.count",
    )
    == UnexpectedEof(bytes_needed: 1, remaining: 0)
}

pub fn deserialize_errors_when_compact_size_transaction_count_is_truncated_test() {
  let header =
    bitcoin_wire.build_block_header_bytes(
      1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      0,
      0,
      0,
    )

  let assert Error(error) = block.deserialize(<<header:bits, 0xFD>>)

  assert decode_assertions.check_block_decode_error(
      error,
      80,
      "block.transactions.count",
    )
    == UnexpectedEof(bytes_needed: 2, remaining: 0)
}

pub fn deserialize_rejects_non_minimal_compact_size_transaction_count_test() {
  let header =
    bitcoin_wire.build_block_header_bytes(
      1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      0,
      0,
      0,
    )

  let assert Error(error) = block.deserialize(<<header:bits, 0xFD, 0x01, 0x00>>)

  assert decode_assertions.check_block_decode_error(
      error,
      80,
      "block.transactions.count",
    )
    == NonMinimalCompactSize(encoded_size: 3, value: 1)
}

pub fn deserialize_rejects_transaction_count_outside_the_runtime_int_range_test() {
  let header =
    bitcoin_wire.build_block_header_bytes(
      1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      0,
      0,
      0,
    )
  // 2^53, one greater than JavaScript's largest exactly representable Int.
  let count_above_max_safe_js_int = <<0, 0, 0, 0, 0, 0, 0x20, 0>>
  let bytes = <<header:bits, 0xFF, count_above_max_safe_js_int:bits>>

  case target.is_javascript() {
    True -> {
      let assert Error(decode_err) = block.deserialize(bytes)

      assert decode_assertions.check_block_decode_error(
          decode_err,
          80,
          "block.transactions.count",
        )
        == IntegerOutOfRange("9007199254740992")
    }

    False -> Nil
  }
}

pub fn deserialize_rejects_transaction_count_that_cannot_fit_test() {
  let header =
    bitcoin_wire.build_block_header_bytes(
      1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      0,
      0,
      0,
    )
  let tx_count = 1
  let assert Error(error) = block.deserialize(<<header:bits, tx_count>>)

  assert decode_assertions.check_block_decode_error(
      error,
      80,
      "block.transactions.count",
    )
    == InsufficientBytes(claimed: 1, remaining: 0)
}

// ============================================================================
// Contained transaction errors
// ============================================================================

pub fn deserialize_offsets_contained_transaction_errors_from_the_block_start_test() {
  let header =
    bitcoin_wire.build_block_header_bytes(
      1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      0,
      0,
      0,
    )
  let tx_count = 1
  let incomplete_tx = <<1:32-little, 1, 0:size(40)>>

  let assert Error(error) =
    block.deserialize(<<header:bits, tx_count, incomplete_tx:bits>>)

  // `85` is block-relative (80-byte header + one-byte count + four-byte
  // transaction version); `4` remains relative to the transaction start.
  let assert TransactionDecodeFailed(tx_decode_err) =
    decode_assertions.check_block_decode_error(
      error,
      85,
      "block.transactions[0]",
    )

  assert decode_assertions.check_transaction_decode_error(
      tx_decode_err,
      4,
      "transaction.inputs.count",
    )
    == transaction.InsufficientBytes(claimed: 6, remaining: 5)
}

pub fn deserialize_reports_error_in_second_transaction_with_transaction_index_in_path_test() {
  let header =
    bitcoin_wire.build_block_header_bytes(
      1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      0,
      0,
      0,
    )
  let incomplete_second_tx = <<1:32-little>>
  let bytes =
    bitcoin_wire.assemble_block_bytes(header, [
      bitcoin_wire.build_minimal_legacy_transaction_bytes(1),
      incomplete_second_tx,
    ])

  let assert Error(error) = block.deserialize(bytes)

  let assert TransactionDecodeFailed(tx_decode_err) =
    decode_assertions.check_block_decode_error(
      error,
      145,
      "block.transactions[1]",
    )

  assert decode_assertions.check_transaction_decode_error(
      tx_decode_err,
      4,
      "transaction.inputs.count",
    )
    == transaction.UnexpectedEof(bytes_needed: 1, remaining: 0)
}

// ============================================================================
// Block boundary
// ============================================================================

pub fn deserialize_rejects_trailing_bytes_after_a_complete_block_test() {
  let complete_block =
    bitcoin_wire.build_header_only_block_bytes(
      1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      0,
      0,
      0,
    )

  let assert Error(error) = block.deserialize(<<complete_block:bits, 0x42>>)

  assert decode_assertions.check_block_decode_error(error, 81, "block")
    == TrailingBytes(1)
}

// ============================================================================
// deserialize_hex
// ============================================================================

pub fn deserialize_hex_accepts_block_with_one_legacy_transaction_test() {
  let header =
    bitcoin_wire.build_block_header_bytes(
      1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      1_234_567_890,
      0x1D00FFFF,
      2_083_236_893,
    )
  let bytes =
    bitcoin_wire.assemble_block_bytes(header, [
      bitcoin_wire.build_minimal_legacy_transaction_bytes(1),
    ])

  let assert Ok(block) =
    bytes
    |> bit_array.base16_encode
    |> block.deserialize_hex

  assert block
    |> block.get_header
    |> block.get_header_timestamp
    == 1_234_567_890

  let assert [tx] = block.get_transactions(block)
  assert transaction.get_version(tx) == 1
  assert !transaction.is_segwit(tx)
}

pub fn deserialize_hex_errors_on_odd_length_string_test() {
  assert block.deserialize_hex("0") == Error(InvalidHex)
}

pub fn deserialize_hex_errors_on_invalid_hex_characters_test() {
  assert block.deserialize_hex("0000zz") == Error(InvalidHex)
}

pub fn deserialize_hex_errors_on_string_with_whitespace_test() {
  assert block.deserialize_hex("00 00") == Error(InvalidHex)
}

pub fn deserialize_hex_wraps_block_decode_error_test() {
  let assert Error(DecodeFailed(error)) = block.deserialize_hex("")

  assert decode_assertions.check_block_decode_error(
      error,
      0,
      "block.header.version",
    )
    == UnexpectedEof(bytes_needed: 4, remaining: 0)
}

import bitcoin_wire/block.{
  DecodeFailed, InsufficientBytes, InvalidHex, MaxBlockSize, MaxTransactionCount,
  NonByteAlignedInput, PolicyLimitExceeded, TransactionDecodeFailed,
  UnexpectedEof,
}
import bitcoin_wire/transaction
import gleam/bit_array
import gleam/list
import gleam/string
import support/bitcoin_wire
import support/decode_assertions

// ============================================================================
// Decode policy configuration
// ============================================================================

pub fn default_decode_policy_returns_expected_values_test() {
  let policy = block.default_decode_policy()
  let tx_policy = block.decode_policy_transaction_policy(policy)

  assert block.decode_policy_max_block_size(policy) == 4_000_000
  assert block.decode_policy_max_tx_count(policy) == 20_000
  assert transaction.decode_policy_max_tx_size(tx_policy) == 4_000_000
  assert transaction.decode_policy_max_input_count(tx_policy) == 100_000
  assert transaction.decode_policy_max_output_count(tx_policy) == 125_000
  assert transaction.decode_policy_max_witness_item_count(tx_policy)
    == 4_000_000
}

pub fn decode_policy_builder_overrides_default_limits_test() {
  let policy =
    block.default_decode_policy()
    |> block.decode_policy_with_max_block_size(8_000_000)
    |> block.decode_policy_with_max_tx_count(40_000)

  assert block.decode_policy_max_block_size(policy) == 8_000_000
  assert block.decode_policy_max_tx_count(policy) == 40_000
}

pub fn decode_policy_builder_replaces_transaction_policy_without_changing_block_limits_test() {
  let tx_policy =
    transaction.default_decode_policy()
    |> transaction.decode_policy_with_max_tx_size(8)
    |> transaction.decode_policy_with_max_input_count(6)
    |> transaction.decode_policy_with_max_output_count(7)
    |> transaction.decode_policy_with_max_witness_item_count(9)

  let policy =
    block.default_decode_policy()
    |> block.decode_policy_with_max_block_size(123)
    |> block.decode_policy_with_max_tx_count(4)
    |> block.decode_policy_with_transaction_policy(tx_policy)

  let actual_tx_policy = block.decode_policy_transaction_policy(policy)

  assert block.decode_policy_max_block_size(policy) == 123
  assert block.decode_policy_max_tx_count(policy) == 4
  assert transaction.decode_policy_max_tx_size(actual_tx_policy) == 8
  assert transaction.decode_policy_max_input_count(actual_tx_policy) == 6
  assert transaction.decode_policy_max_output_count(actual_tx_policy) == 7
  assert transaction.decode_policy_max_witness_item_count(actual_tx_policy) == 9
}

// ============================================================================
// Decode policy enforcement
// ============================================================================

pub fn deserialize_with_policy_rejects_bytes_exceeding_max_block_size_test() {
  let bytes =
    bitcoin_wire.build_header_only_block_bytes(
      1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      0,
      0,
      0,
    )
  let block_size = bit_array.byte_size(bytes)

  let assert Error(error) =
    block.deserialize_with_policy(
      bytes,
      policy_with_max_block_size(block_size - 1),
    )

  assert decode_assertions.check_block_decode_error(error, 0, "block")
    == PolicyLimitExceeded(MaxBlockSize, block_size, block_size - 1)
}

pub fn deserialize_with_policy_prioritizes_non_byte_aligned_input_over_max_block_size_test() {
  let bytes =
    bitcoin_wire.build_header_only_block_bytes(
      1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      0,
      0,
      0,
    )
  let unaligned = <<bytes:bits, 0:1>>
  let max_block_size = bit_array.byte_size(unaligned) - 1

  let assert Error(error) =
    block.deserialize_with_policy(
      unaligned,
      policy_with_max_block_size(max_block_size),
    )

  assert decode_assertions.check_block_decode_error(error, 0, "block")
    == NonByteAlignedInput(bit_array.bit_size(unaligned))
}

pub fn deserialize_with_policy_accepts_bytes_at_max_block_size_test() {
  let bytes =
    bitcoin_wire.build_header_only_block_bytes(
      1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      0,
      0,
      0,
    )

  let policy = policy_with_max_block_size(bit_array.byte_size(bytes))
  let assert Ok(block) = block.deserialize_with_policy(bytes, policy)

  assert block.get_transactions(block) == []
}

pub fn deserialize_with_policy_rejects_tx_count_exceeding_max_tx_count_test() {
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

  let assert Error(error) =
    block.deserialize_with_policy(bytes, policy_with_max_tx_count(1))

  assert decode_assertions.check_block_decode_error(
      error,
      80,
      "block.transactions.count",
    )
    == PolicyLimitExceeded(MaxTransactionCount, 2, 1)
}

pub fn deserialize_with_policy_prioritizes_structural_tx_count_error_test() {
  let header =
    bitcoin_wire.build_block_header_bytes(
      1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      0,
      0,
      0,
    )

  // The count exceeds the policy, but no transaction bytes remain, so the
  // structural impossibility must be reported before the policy violation.
  let assert Error(error) =
    block.deserialize_with_policy(
      bitcoin_wire.assemble_block_from_transaction_payload_bytes(
        header,
        2,
        <<>>,
      ),
      policy_with_max_tx_count(1),
    )

  assert decode_assertions.check_block_decode_error(
      error,
      80,
      "block.transactions.count",
    )
    == InsufficientBytes(claimed: 1, remaining: 0)
}

pub fn deserialize_with_policy_accepts_tx_count_at_max_tx_count_test() {
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

  let assert Ok(block) =
    block.deserialize_with_policy(bytes, policy_with_max_tx_count(2))

  assert list.length(block.get_transactions(block)) == 2
}

pub fn deserialize_accepts_default_max_tx_count_without_call_stack_overflow_test() {
  let policy = block.default_decode_policy()
  let tx_count = block.decode_policy_max_tx_count(policy)
  let header =
    bitcoin_wire.build_block_header_bytes(
      1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      0,
      0,
      0,
    )
  let tx = build_smallest_structurally_decodable_transaction()
  let bytes =
    bitcoin_wire.assemble_block_bytes(header, list.repeat(tx, tx_count))

  let tx_size = bit_array.byte_size(tx)
  let expected_block_size =
    bit_array.byte_size(header)
    + bit_array.byte_size(bitcoin_wire.compact_size(tx_count))
    + tx_count
    * tx_size

  assert tx_size == 10
  assert bit_array.byte_size(bytes) == expected_block_size
  assert expected_block_size <= block.decode_policy_max_block_size(policy)

  let assert Ok(block) = block.deserialize(bytes)

  assert block.get_transaction_count(block) == tx_count
  assert list.length(block.get_transactions(block)) == tx_count
}

// ============================================================================
// Contained transaction policy errors
// ============================================================================

pub fn deserialize_with_policy_wraps_contained_transaction_policy_error_with_block_offset_test() {
  // The first transaction has no outputs, so only the second exceeds the limit.
  let first_tx = build_smallest_structurally_decodable_transaction()
  let second_tx = bitcoin_wire.build_minimal_segwit_transaction_bytes()
  let bytes =
    bitcoin_wire.assemble_block_bytes(<<0:640>>, [first_tx, second_tx])
  let tx_policy =
    transaction.default_decode_policy()
    |> transaction.decode_policy_with_max_output_count(0)
  let policy =
    block.default_decode_policy()
    |> block.decode_policy_with_transaction_policy(tx_policy)
  let assert Error(error) = block.deserialize_with_policy(bytes, policy)

  // 80 header bytes + one count byte + ten first-transaction bytes + offset 48.
  let assert TransactionDecodeFailed(tx_error) =
    decode_assertions.check_block_decode_error(
      error,
      139,
      "block.transactions[1]",
    )
  assert decode_assertions.check_transaction_decode_error(
      tx_error,
      48,
      "transaction.outputs.count",
    )
    == transaction.PolicyLimitExceeded(transaction.MaxOutputCount, 1, 0)
}

pub fn deserialize_with_policy_ignores_contained_transaction_max_tx_size_test() {
  let header =
    bitcoin_wire.build_block_header_bytes(
      1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      0,
      0,
      0,
    )
  let tx_bytes = bitcoin_wire.build_minimal_legacy_transaction_bytes(1)
  let tx_policy =
    transaction.default_decode_policy()
    |> transaction.decode_policy_with_max_tx_size(1)
  let policy =
    block.default_decode_policy()
    |> block.decode_policy_with_transaction_policy(tx_policy)

  let assert Ok(decoded_block) =
    block.deserialize_with_policy(
      bitcoin_wire.assemble_block_bytes(header, [tx_bytes]),
      policy,
    )

  assert block.get_transaction_count(decoded_block) == 1
}

// ============================================================================
// deserialize_hex_with_policy
// ============================================================================

pub fn deserialize_hex_with_policy_accepts_block_at_max_block_size_test() {
  let bytes =
    bitcoin_wire.build_header_only_block_bytes(
      0xABCD,
      <<0:size(256)>>,
      <<0:size(256)>>,
      0,
      0,
      0,
    )
  let policy = policy_with_max_block_size(bit_array.byte_size(bytes))
  let upper_hex = bit_array.base16_encode(bytes)

  [upper_hex, string.lowercase(upper_hex)]
  |> list.each(fn(hex) {
    let assert Ok(decoded_block) =
      block.deserialize_hex_with_policy(hex, policy)
    assert block.get_transactions(decoded_block) == []
    assert block.serialize(decoded_block) == bytes
  })
}

pub fn deserialize_hex_with_policy_wraps_policy_limit_error_test() {
  let bytes =
    bitcoin_wire.build_header_only_block_bytes(
      1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      0,
      0,
      0,
    )
  let block_size = bit_array.byte_size(bytes)

  let policy = policy_with_max_block_size(block_size - 1)
  let assert Error(DecodeFailed(error)) =
    bytes
    |> bit_array.base16_encode
    |> block.deserialize_hex_with_policy(policy)

  assert decode_assertions.check_block_decode_error(error, 0, "block")
    == PolicyLimitExceeded(MaxBlockSize, block_size, block_size - 1)
}

pub fn deserialize_hex_with_policy_prioritizes_invalid_hex_over_size_limit_test() {
  let policy = policy_with_max_block_size(1)
  // Include non-ASCII strings whose UTF-8 and UTF-16 lengths differ, including
  // cases that cross the size threshold on only one target. Both return InvalidHex.
  [
    "000",
    "zz00",
    "0z00",
    "00zz",
    "000z",
    "0000zz",
    "00 0",
    "00é0",
    "00😀0",
    "é0",
    "😀",
  ]
  |> list.each(fn(hex) {
    assert block.deserialize_hex_with_policy(hex, policy) == Error(InvalidHex)
  })
}

pub fn deserialize_hex_with_policy_rejects_large_valid_hex_test() {
  let hex = string.repeat("aB", 100_000)
  let assert Error(DecodeFailed(error)) =
    block.deserialize_hex_with_policy(hex, policy_with_max_block_size(1))

  assert decode_assertions.check_block_decode_error(error, 0, "block")
    == PolicyLimitExceeded(MaxBlockSize, 100_000, 1)
}

pub fn deserialize_hex_with_policy_applies_zero_byte_limit_test() {
  let policy = policy_with_max_block_size(0)
  let assert Error(DecodeFailed(size_error)) =
    block.deserialize_hex_with_policy("00", policy)
  assert decode_assertions.check_block_decode_error(size_error, 0, "block")
    == PolicyLimitExceeded(MaxBlockSize, 1, 0)

  assert block.deserialize_hex_with_policy("z0", policy) == Error(InvalidHex)

  // Empty valid hex fits the zero-byte envelope and reaches structural decoding.
  let assert Error(DecodeFailed(empty_error)) =
    block.deserialize_hex_with_policy("", policy)
  assert decode_assertions.check_block_decode_error(
      empty_error,
      0,
      "block.header.version",
    )
    == UnexpectedEof(bytes_needed: 4, remaining: 0)
}

pub fn deserialize_hex_with_policy_applies_negative_byte_limit_test() {
  let assert Error(DecodeFailed(error)) =
    block.deserialize_hex_with_policy("", policy_with_max_block_size(-1))

  assert decode_assertions.check_block_decode_error(error, 0, "block")
    == PolicyLimitExceeded(MaxBlockSize, 0, -1)
}

// ============================================================================
// Helpers
// ============================================================================

fn build_smallest_structurally_decodable_transaction() -> BitArray {
  <<1:32-little, 0, 0, 0:32-little>>
}

fn policy_with_max_block_size(max_block_size: Int) {
  block.default_decode_policy()
  |> block.decode_policy_with_max_block_size(max_block_size)
}

fn policy_with_max_tx_count(max_tx_count: Int) {
  block.default_decode_policy()
  |> block.decode_policy_with_max_tx_count(max_tx_count)
}

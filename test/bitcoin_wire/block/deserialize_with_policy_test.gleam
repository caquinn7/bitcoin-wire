import bitcoin_wire/block.{
  DecodeFailed, InsufficientBytes, MaxBlockSize, MaxTransactionCount,
  NonByteAlignedInput, PolicyLimitExceeded, TransactionDecodeFailed,
}
import bitcoin_wire/transaction
import gleam/bit_array
import gleam/list
import gleam/option.{None, Some}
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
  assert transaction.decode_policy_max_tx_size(tx_policy) == 400_000
  assert transaction.decode_policy_max_input_count(tx_policy) == 100_000
  assert transaction.decode_policy_max_output_count(tx_policy) == 100_000
  assert transaction.decode_policy_max_script_size(tx_policy) == 10_000
  assert transaction.decode_policy_max_witness_stack_item_count(tx_policy)
    == None
  assert transaction.decode_policy_max_witness_stack_payload_size(tx_policy)
    == None
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
    |> transaction.decode_policy_with_max_script_size(5)
    |> transaction.decode_policy_with_max_witness_stack_item_count(Some(9))
    |> transaction.decode_policy_with_max_witness_stack_payload_size(Some(10))

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
  assert transaction.decode_policy_max_script_size(actual_tx_policy) == 5
  assert transaction.decode_policy_max_witness_stack_item_count(
      actual_tx_policy,
    )
    == Some(9)
  assert transaction.decode_policy_max_witness_stack_payload_size(
      actual_tx_policy,
    )
    == Some(10)
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

pub fn deserialize_accepts_default_max_tx_count_without_stack_overflow_test() {
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

pub fn deserialize_wraps_contained_transaction_policy_error_with_block_offset_test() {
  let header =
    bitcoin_wire.build_block_header_bytes(
      1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      0,
      0,
      0,
    )
  let oversized_script_sig = <<0:size({ 10_001 * 8 })>>
  let oversized_tx = <<
    1:32-little,
    1,
    0:size(256),
    0:32-little,
    bitcoin_wire.compact_size(10_001):bits,
    oversized_script_sig:bits,
    0:32-little,
    0,
    0:32-little,
  >>

  let assert Error(error) =
    block.deserialize(bitcoin_wire.assemble_block_bytes(header, [oversized_tx]))

  let assert TransactionDecodeFailed(tx_decode_err) =
    decode_assertions.check_block_decode_error(
      error,
      122,
      "block.transactions[0]",
    )

  assert decode_assertions.check_transaction_decode_error(
      tx_decode_err,
      41,
      "transaction.inputs[0].script_sig.length",
    )
    == transaction.PolicyLimitExceeded(
      transaction.MaxScriptSize,
      10_001,
      10_000,
    )
}

pub fn deserialize_with_policy_applies_a_relaxed_contained_transaction_script_limit_test() {
  let header =
    bitcoin_wire.build_block_header_bytes(
      1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      0,
      0,
      0,
    )
  let oversized_tx = build_transaction_with_script_sig_size(10_001)
  let tx_policy =
    transaction.default_decode_policy()
    |> transaction.decode_policy_with_max_script_size(10_001)
  let policy =
    block.default_decode_policy()
    |> block.decode_policy_with_transaction_policy(tx_policy)

  let assert Ok(decoded_block) =
    block.deserialize_with_policy(
      bitcoin_wire.assemble_block_bytes(header, [oversized_tx]),
      policy,
    )

  assert block.get_transaction_count(decoded_block) == 1
}

pub fn deserialize_with_policy_wraps_stricter_contained_transaction_policy_error_test() {
  let header =
    bitcoin_wire.build_block_header_bytes(
      1,
      <<0:size(256)>>,
      <<0:size(256)>>,
      0,
      0,
      0,
    )
  let tx_bytes = build_transaction_with_script_sig_size(11)
  let tx_policy =
    transaction.default_decode_policy()
    |> transaction.decode_policy_with_max_script_size(10)
  let policy =
    block.default_decode_policy()
    |> block.decode_policy_with_transaction_policy(tx_policy)

  let assert Error(error) =
    block.deserialize_with_policy(
      bitcoin_wire.assemble_block_bytes(header, [tx_bytes]),
      policy,
    )

  let assert TransactionDecodeFailed(tx_decode_err) =
    decode_assertions.check_block_decode_error(
      error,
      122,
      "block.transactions[0]",
    )

  assert decode_assertions.check_transaction_decode_error(
      tx_decode_err,
      41,
      "transaction.inputs[0].script_sig.length",
    )
    == transaction.PolicyLimitExceeded(transaction.MaxScriptSize, 11, 10)
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

pub fn deserialize_with_policy_accepts_second_segwit_transaction_at_witness_item_limit_test() {
  let bytes = build_block_with_second_witness_stack([<<>>, <<>>])
  let assert Ok(decoded_block) =
    block.deserialize_with_policy(bytes, policy_with_two_item_witness_limits())

  assert block.get_transaction_count(decoded_block) == 2
  assert block.serialize(decoded_block) == bytes
}

pub fn deserialize_with_policy_wraps_second_segwit_transaction_witness_item_limit_error_test() {
  let bytes = build_block_with_second_witness_stack([<<>>, <<>>, <<>>])
  let assert Error(error) =
    block.deserialize_with_policy(bytes, policy_with_two_item_witness_limits())
  let assert TransactionDecodeFailed(tx_error) =
    decode_assertions.check_block_decode_error(
      error,
      203,
      "block.transactions[1]",
    )

  assert decode_assertions.check_transaction_decode_error(
      tx_error,
      58,
      "transaction.witnesses[0].items.count",
    )
    == transaction.PolicyLimitExceeded(
      transaction.MaxWitnessStackItemCount,
      3,
      2,
    )
}

pub fn deserialize_with_policy_accepts_second_segwit_transaction_at_witness_payload_limit_test() {
  let bytes = build_block_with_second_witness_stack([<<0xAA>>, <<0xBB>>])
  let assert Ok(decoded_block) =
    block.deserialize_with_policy(bytes, policy_with_two_item_witness_limits())

  assert block.get_transaction_count(decoded_block) == 2
  assert block.serialize(decoded_block) == bytes
}

pub fn deserialize_with_policy_wraps_second_segwit_transaction_witness_payload_limit_error_test() {
  let bytes = build_block_with_second_witness_stack([<<0xAA>>, <<0xBB, 0xCC>>])
  let assert Error(error) =
    block.deserialize_with_policy(bytes, policy_with_two_item_witness_limits())
  let assert TransactionDecodeFailed(tx_error) =
    decode_assertions.check_block_decode_error(
      error,
      206,
      "block.transactions[1]",
    )

  assert decode_assertions.check_transaction_decode_error(
      tx_error,
      61,
      "transaction.witnesses[0].items[1]",
    )
    == transaction.PolicyLimitExceeded(
      transaction.MaxWitnessStackPayloadSize,
      3,
      2,
    )
}

// ============================================================================
// deserialize_hex_with_policy
// ============================================================================

pub fn deserialize_hex_with_policy_accepts_block_at_max_block_size_test() {
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
  let assert Ok(block) =
    bytes
    |> bit_array.base16_encode
    |> block.deserialize_hex_with_policy(policy)

  assert block.get_transactions(block) == []
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

// ============================================================================
// Helpers
// ============================================================================

fn build_block_with_second_witness_stack(items: List(BitArray)) -> BitArray {
  let first_tx = bitcoin_wire.build_minimal_segwit_transaction_bytes()
  assert bit_array.byte_size(first_tx) == 64
  let second_tx =
    bitcoin_wire.assemble_segwit_transaction_bytes(
      [bitcoin_wire.build_input_bytes(<<1:256>>, 0, <<>>, 0)],
      [bitcoin_wire.build_output_bytes(<<1000:64-little>>, <<>>)],
      [bitcoin_wire.build_witness_stack_bytes(items)],
    )

  // An 80-byte header and one count byte put the second transaction at 145.
  bitcoin_wire.assemble_block_bytes(<<0:640>>, [first_tx, second_tx])
}

fn policy_with_two_item_witness_limits() -> block.DecodePolicy {
  let tx_policy =
    transaction.default_decode_policy()
    |> transaction.decode_policy_with_max_witness_stack_item_count(Some(2))
    |> transaction.decode_policy_with_max_witness_stack_payload_size(Some(2))

  block.default_decode_policy()
  |> block.decode_policy_with_transaction_policy(tx_policy)
}

fn build_transaction_with_script_sig_size(script_size: Int) -> BitArray {
  let script_sig = <<0:size({ script_size * 8 })>>

  <<
    1:32-little,
    1,
    0:size(256),
    0:32-little,
    bitcoin_wire.compact_size(script_size):bits,
    script_sig:bits,
    0:32-little,
    0,
    0:32-little,
  >>
}

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

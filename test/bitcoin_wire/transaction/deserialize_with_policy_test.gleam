import bitcoin_wire/transaction.{
  DecodeFailed, InsufficientBytes, MaxInputCount, MaxOutputCount,
  MaxTransactionSize, NonByteAlignedInput, PolicyLimitExceeded,
}
import gleam/bit_array
import gleam/list
import support/bitcoin_wire
import support/decode_assertions

// ============================================================================
// deserialize_hex_with_policy
// ============================================================================

pub fn deserialize_hex_with_policy_accepts_tx_at_max_tx_size_test() {
  let bytes = bitcoin_wire.build_minimal_legacy_transaction_bytes(1)
  let policy = policy_with_max_tx_size(bit_array.byte_size(bytes))

  let assert Ok(tx) =
    bytes
    |> bit_array.base16_encode
    |> transaction.deserialize_hex_with_policy(policy)

  assert transaction.serialize(tx) == bytes
}

pub fn deserialize_hex_with_policy_wraps_policy_limit_error_test() {
  let bytes = bitcoin_wire.build_minimal_legacy_transaction_bytes(1)
  let tx_size = bit_array.byte_size(bytes)
  let policy = policy_with_max_tx_size(tx_size - 1)

  let assert Error(DecodeFailed(error)) =
    bytes
    |> bit_array.base16_encode
    |> transaction.deserialize_hex_with_policy(policy)

  assert decode_assertions.check_transaction_decode_error(
      error,
      0,
      "transaction",
    )
    == PolicyLimitExceeded(MaxTransactionSize, tx_size, tx_size - 1)
}

// ============================================================================
// Decode policy configuration
// ============================================================================

pub fn default_decode_policy_returns_expected_values_test() {
  let policy = transaction.default_decode_policy()

  assert transaction.decode_policy_max_tx_size(policy) == 400_000
  assert transaction.decode_policy_max_input_count(policy) == 100_000
  assert transaction.decode_policy_max_output_count(policy) == 100_000
}

pub fn decode_policy_builder_overrides_default_limits_test() {
  let policy =
    transaction.default_decode_policy()
    |> transaction.decode_policy_with_max_tx_size(123)
    |> transaction.decode_policy_with_max_input_count(4)
    |> transaction.decode_policy_with_max_output_count(5)

  assert transaction.decode_policy_max_tx_size(policy) == 123
  assert transaction.decode_policy_max_input_count(policy) == 4
  assert transaction.decode_policy_max_output_count(policy) == 5
}

// ============================================================================
// deserialize_with_policy: transaction size
// ============================================================================

pub fn deserialize_with_policy_accepts_tx_at_max_tx_size_test() {
  let bytes = bitcoin_wire.build_minimal_legacy_transaction_bytes(1)
  let policy = policy_with_max_tx_size(bit_array.byte_size(bytes))
  let assert Ok(tx) = transaction.deserialize_with_policy(bytes, policy)

  assert transaction.serialize(tx) == bytes
}

pub fn deserialize_with_policy_rejects_tx_exceeding_max_tx_size_test() {
  let bytes = bitcoin_wire.build_minimal_legacy_transaction_bytes(1)
  let tx_size = bit_array.byte_size(bytes)
  let max_tx_size = tx_size - 1
  let assert Error(error) =
    transaction.deserialize_with_policy(
      bytes,
      policy_with_max_tx_size(max_tx_size),
    )

  assert decode_assertions.check_transaction_decode_error(
      error,
      0,
      "transaction",
    )
    == PolicyLimitExceeded(MaxTransactionSize, tx_size, max_tx_size)
}

pub fn deserialize_with_policy_prioritizes_max_tx_size_over_structural_errors_test() {
  // The version is truncated, but the byte envelope must reject before parsing.
  let bytes = <<1, 0, 0>>
  let tx_size = bit_array.byte_size(bytes)
  let max_tx_size = tx_size - 1
  let assert Error(error) =
    transaction.deserialize_with_policy(
      bytes,
      policy_with_max_tx_size(max_tx_size),
    )

  assert decode_assertions.check_transaction_decode_error(
      error,
      0,
      "transaction",
    )
    == PolicyLimitExceeded(MaxTransactionSize, tx_size, max_tx_size)
}

pub fn deserialize_with_policy_prioritizes_non_byte_aligned_input_over_max_tx_size_test() {
  let tx_bytes = bitcoin_wire.build_minimal_legacy_transaction_bytes(1)
  let unaligned = <<tx_bytes:bits, 0:1>>
  let max_tx_size = bit_array.byte_size(unaligned) - 1

  let assert Error(error) =
    transaction.deserialize_with_policy(
      unaligned,
      policy_with_max_tx_size(max_tx_size),
    )

  assert decode_assertions.check_transaction_decode_error(
      error,
      0,
      "transaction",
    )
    == NonByteAlignedInput(bit_array.bit_size(unaligned))
}

// ============================================================================
// deserialize_with_policy: input and output counts
// ============================================================================

pub fn deserialize_with_policy_accepts_input_count_at_max_input_count_test() {
  // Supply enough bytes that policy, not structural feasibility, is the limit.

  let max_input_count = 3
  let input_count = max_input_count
  let input_padding = <<
    0:little-size({ input_count * bitcoin_wire.min_input_size_bytes * 8 }),
  >>
  let lock_time = <<0:little-size(32)>>

  let assert Ok(tx) =
    transaction.deserialize_with_policy(
      <<
        bitcoin_wire.transaction_version_1_bytes:bits,
        bitcoin_wire.compact_size(input_count):bits,
        input_padding:bits,
        bitcoin_wire.build_minimal_output_section_bytes():bits,
        lock_time:bits,
      >>,
      policy_with_max_input_count(max_input_count),
    )

  assert transaction.get_input_count(tx) == input_count
}

pub fn deserialize_with_policy_rejects_input_count_exceeding_max_input_count_before_parsing_inputs_test() {
  let max_input_count = 2
  let input_count = max_input_count + 1
  // A non-minimal script length would fail if the first input were parsed.
  let malformed_first_input = <<0:256, 0:32-little, 0xFD, 0, 0, 0:32-little>>
  let input_padding = <<
    0:size({ { input_count - 1 } * bitcoin_wire.min_input_size_bytes * 8 }),
  >>

  // Enough bytes remain for the declared count, so structural feasibility passes.
  let assert Error(error) =
    transaction.deserialize_with_policy(
      <<
        bitcoin_wire.transaction_version_1_bytes:bits,
        bitcoin_wire.compact_size(input_count):bits,
        malformed_first_input:bits,
        input_padding:bits,
      >>,
      policy_with_max_input_count(max_input_count),
    )

  assert decode_assertions.check_transaction_decode_error(
      error,
      4,
      "transaction.inputs.count",
    )
    == PolicyLimitExceeded(MaxInputCount, input_count, max_input_count)
}

pub fn deserialize_with_policy_prioritizes_structural_input_count_error_test() {
  // The claimed count exceeds both structural feasibility and the policy.

  let available_input_count = 2
  let input_count = available_input_count + 1
  let max_input_count = available_input_count
  let input_padding = <<
    0:little-size({
      available_input_count * bitcoin_wire.min_input_size_bytes * 8
    }),
  >>

  let assert Error(decode_err) =
    transaction.deserialize_with_policy(
      <<
        bitcoin_wire.transaction_version_1_bytes:bits,
        bitcoin_wire.compact_size(input_count):bits,
        input_padding:bits,
      >>,
      policy_with_max_input_count(max_input_count),
    )

  assert decode_assertions.check_transaction_decode_error(
      decode_err,
      4,
      "transaction.inputs.count",
    )
    == InsufficientBytes(
      claimed: available_input_count * bitcoin_wire.min_input_size_bytes + 1,
      remaining: available_input_count * bitcoin_wire.min_input_size_bytes,
    )
}

pub fn deserialize_with_policy_accepts_output_count_at_max_output_count_test() {
  // Supply enough bytes that policy, not structural feasibility, is the limit.

  let max_output_count = 3
  let output_count = max_output_count
  let output1 = bitcoin_wire.build_output_bytes(<<0:little-size(64)>>, <<>>)
  let output2 = bitcoin_wire.build_output_bytes(<<0:little-size(64)>>, <<>>)
  let output3 = bitcoin_wire.build_output_bytes(<<0:little-size(64)>>, <<>>)
  let lock_time = <<0:little-size(32)>>

  let assert Ok(tx) =
    transaction.deserialize_with_policy(
      <<
        bitcoin_wire.transaction_version_1_bytes:bits,
        bitcoin_wire.build_minimal_input_section_bytes():bits,
        bitcoin_wire.compact_size(output_count):bits,
        output1:bits,
        output2:bits,
        output3:bits,
        lock_time:bits,
      >>,
      policy_with_max_output_count(max_output_count),
    )

  assert transaction.get_output_count(tx) == output_count
}

pub fn deserialize_with_policy_rejects_output_count_exceeding_max_output_count_before_parsing_outputs_test() {
  let max_output_count = 2
  let output_count = max_output_count + 1
  // A non-minimal script length would fail if the first output were parsed.
  let malformed_first_output = <<0:64-little, 0xFD, 0, 0>>
  let output_padding = <<
    0:size({ { output_count - 1 } * bitcoin_wire.min_output_size_bytes * 8 }),
  >>

  // Enough bytes remain for the declared count, so structural feasibility passes.
  let assert Error(error) =
    transaction.deserialize_with_policy(
      <<
        bitcoin_wire.transaction_version_1_bytes:bits,
        bitcoin_wire.build_minimal_input_section_bytes():bits,
        bitcoin_wire.compact_size(output_count):bits,
        malformed_first_output:bits,
        output_padding:bits,
      >>,
      policy_with_max_output_count(max_output_count),
    )

  assert decode_assertions.check_transaction_decode_error(
      error,
      46,
      "transaction.outputs.count",
    )
    == PolicyLimitExceeded(MaxOutputCount, output_count, max_output_count)
}

pub fn deserialize_with_policy_prioritizes_structural_output_count_error_test() {
  // The claimed count exceeds both structural feasibility and the policy.

  let available_output_count = 2
  let output_count = available_output_count + 1
  let max_output_count = available_output_count
  let output1 = bitcoin_wire.build_output_bytes(<<0:little-size(64)>>, <<>>)
  let output2 = bitcoin_wire.build_output_bytes(<<0:little-size(64)>>, <<>>)

  let assert Error(decode_err) =
    transaction.deserialize_with_policy(
      <<
        bitcoin_wire.transaction_version_1_bytes:bits,
        bitcoin_wire.build_minimal_input_section_bytes():bits,
        bitcoin_wire.compact_size(output_count):bits,
        output1:bits,
        output2:bits,
      >>,
      policy_with_max_output_count(max_output_count),
    )

  assert decode_assertions.check_transaction_decode_error(
      decode_err,
      46,
      "transaction.outputs.count",
    )
    == InsufficientBytes(
      claimed: available_output_count * bitcoin_wire.min_output_size_bytes + 1,
      remaining: available_output_count * bitcoin_wire.min_output_size_bytes,
    )
}

// ============================================================================
// Large witness collections
// ============================================================================

pub fn deserialize_accepts_zero_length_witness_items_at_default_tx_size_without_stack_overflow_test() {
  // 60 stripped bytes + 2 marker/flag bytes + 5 count bytes + one byte per item.
  let item_count = 399_933
  let stack = <<
    bitcoin_wire.compact_size(item_count):bits,
    0:size({ item_count * 8 }),
  >>
  let bytes =
    bitcoin_wire.assemble_segwit_transaction_bytes(
      [bitcoin_wire.build_input_bytes(<<0:size(256)>>, 0, <<>>, 0)],
      [bitcoin_wire.build_output_bytes(<<0:64>>, <<>>)],
      [stack],
    )

  assert bit_array.byte_size(bytes) == 400_000
  let assert Ok(tx) = transaction.deserialize(bytes)
  let assert Ok([stack]) = transaction.get_witnesses(tx)
  assert list.length(transaction.get_witness_items(stack)) == item_count
  assert transaction.compute_base_size(tx) == 60
  assert transaction.compute_total_size(tx) == 400_000
  assert transaction.serialize(tx) == bytes
}

// ============================================================================
// Helpers
// ============================================================================

fn policy_with_max_tx_size(max_tx_size: Int) {
  transaction.default_decode_policy()
  |> transaction.decode_policy_with_max_tx_size(max_tx_size)
}

fn policy_with_max_input_count(max_input_count: Int) {
  transaction.default_decode_policy()
  |> transaction.decode_policy_with_max_input_count(max_input_count)
}

fn policy_with_max_output_count(max_output_count: Int) {
  transaction.default_decode_policy()
  |> transaction.decode_policy_with_max_output_count(max_output_count)
}

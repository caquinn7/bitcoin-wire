import bitcoin_wire/transaction.{
  DecodeFailed, InsufficientBytes, MaxInputCount, MaxOutputCount,
  MaxTransactionSize, MaxWitnessItemCount, NonByteAlignedInput,
  PolicyLimitExceeded, SuperfluousWitnessRecord,
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

  assert transaction.decode_policy_max_tx_size(policy) == 4_000_000
  assert transaction.decode_policy_max_input_count(policy) == 100_000
  assert transaction.decode_policy_max_output_count(policy) == 125_000
  assert transaction.decode_policy_max_witness_item_count(policy) == 4_000_000
}

pub fn decode_policy_builder_overrides_default_limits_test() {
  let policy =
    transaction.default_decode_policy()
    |> transaction.decode_policy_with_max_tx_size(123)
    |> transaction.decode_policy_with_max_input_count(4)
    |> transaction.decode_policy_with_max_output_count(5)
    |> transaction.decode_policy_with_max_witness_item_count(6)

  assert transaction.decode_policy_max_tx_size(policy) == 123
  assert transaction.decode_policy_max_input_count(policy) == 4
  assert transaction.decode_policy_max_output_count(policy) == 5
  assert transaction.decode_policy_max_witness_item_count(policy) == 6
}

// ============================================================================
// deserialize_with_policy: transaction size
// ============================================================================

pub fn deserialize_accepts_tx_at_default_max_tx_size_test() {
  // 60 stripped bytes + 2 marker/flag bytes + 1 item-count byte + 5 length bytes.
  let bytes = build_transaction_with_witness_payload(3_999_932)
  assert bit_array.byte_size(bytes) == 4_000_000

  let assert Ok(tx) = transaction.deserialize(bytes)
  let assert Ok([stack]) = transaction.get_witnesses(tx)
  assert list.length(transaction.get_witness_items(stack)) == 1
  assert transaction.compute_total_size(tx) == 4_000_000
  assert transaction.serialize(tx) == bytes
}

pub fn deserialize_rejects_tx_one_byte_over_default_max_tx_size_test() {
  let bytes = build_transaction_with_witness_payload(3_999_933)
  assert bit_array.byte_size(bytes) == 4_000_001

  let assert Error(error) = transaction.deserialize(bytes)
  assert decode_assertions.check_transaction_decode_error(
      error,
      0,
      "transaction",
    )
    == PolicyLimitExceeded(MaxTransactionSize, 4_000_001, 4_000_000)
}

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

pub fn deserialize_accepts_default_max_output_count_without_call_stack_overflow_test() {
  let output_count = 125_000
  let output_padding = <<
    0:size({ output_count * bitcoin_wire.min_output_size_bytes * 8 }),
  >>
  let bytes = <<
    bitcoin_wire.transaction_version_1_bytes:bits,
    bitcoin_wire.build_minimal_input_section_bytes():bits,
    bitcoin_wire.compact_size(output_count):bits,
    output_padding:bits,
    0:32-little,
  >>
  let assert Ok(tx) = transaction.deserialize(bytes)

  assert transaction.get_output_count(tx) == output_count
  assert list.length(transaction.get_outputs(tx)) == output_count
}

pub fn deserialize_rejects_output_count_one_over_default_limit_test() {
  let output_count = 125_001
  // Enough bytes remain for every minimal output, so structural feasibility
  // passes and policy rejects at the count field before parsing any outputs.
  let output_padding = <<
    0:size({ output_count * bitcoin_wire.min_output_size_bytes * 8 }),
  >>
  let bytes = <<
    bitcoin_wire.transaction_version_1_bytes:bits,
    bitcoin_wire.build_minimal_input_section_bytes():bits,
    bitcoin_wire.compact_size(output_count):bits,
    output_padding:bits,
    0:32-little,
  >>
  let assert Error(error) = transaction.deserialize(bytes)

  assert decode_assertions.check_transaction_decode_error(
      error,
      46,
      "transaction.outputs.count",
    )
    == PolicyLimitExceeded(MaxOutputCount, output_count, 125_000)
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
// deserialize_with_policy: total witness item count
// ============================================================================

// The default item and byte limits are both 4,000,000. Each item needs at least
// one length-prefix byte, so transaction overhead makes the item limit
// unreachable within the default byte envelope. Testing acceptance at that
// boundary would require raising the byte limit and decoding millions of items,
// with substantial memory and runtime costs. Small custom limits cover policy
// boundaries and error behavior; bounded large workloads cover call stack safety.

pub fn deserialize_accepts_100_000_witness_items_without_call_stack_overflow_test() {
  let item_count = 100_000
  let bytes =
    build_transaction_with_witness_stacks([empty_items_stack(item_count)])

  let assert Ok(tx) = transaction.deserialize(bytes)
  let assert Ok([stack]) = transaction.get_witnesses(tx)
  assert list.length(transaction.get_witness_items(stack)) == item_count
  assert transaction.serialize(tx) == bytes
}

pub fn deserialize_with_policy_accepts_witness_item_count_at_limit_test() {
  let bytes = build_transaction_with_witness_stacks([empty_items_stack(3)])
  let assert Ok(tx) =
    transaction.deserialize_with_policy(
      bytes,
      policy_with_max_witness_item_count(3),
    )
  let assert Ok([stack]) = transaction.get_witnesses(tx)

  assert list.length(transaction.get_witness_items(stack)) == 3
  assert transaction.serialize(tx) == bytes
}

pub fn deserialize_with_policy_rejects_witness_item_count_one_over_limit_test() {
  let bytes = build_transaction_with_witness_stacks([empty_items_stack(4)])
  let assert Error(error) =
    transaction.deserialize_with_policy(
      bytes,
      policy_with_max_witness_item_count(3),
    )

  assert decode_assertions.check_transaction_decode_error(
      error,
      58,
      "transaction.witnesses[0].items.count",
    )
    == PolicyLimitExceeded(MaxWitnessItemCount, 4, 3)
}

pub fn deserialize_with_policy_accepts_total_witness_item_count_at_limit_test() {
  // Empty stacks contribute nothing; zero-length items each contribute one.
  let bytes =
    build_transaction_with_witness_stacks([
      empty_items_stack(1),
      empty_items_stack(0),
      empty_items_stack(2),
    ])
  let assert Ok(tx) =
    transaction.deserialize_with_policy(
      bytes,
      policy_with_max_witness_item_count(3),
    )
  let assert Ok(witnesses) = transaction.get_witnesses(tx)

  assert list.map(witnesses, fn(stack) {
      list.length(transaction.get_witness_items(stack))
    })
    == [1, 0, 2]
  assert transaction.serialize(tx) == bytes
}

pub fn deserialize_with_policy_rejects_total_witness_item_count_one_over_limit_test() {
  let first_stack = empty_items_stack(1)
  let bytes =
    build_transaction_with_witness_stacks([
      first_stack,
      empty_items_stack(3),
    ])
  let assert Error(error) =
    transaction.deserialize_with_policy(
      bytes,
      policy_with_max_witness_item_count(3),
    )

  assert decode_assertions.check_transaction_decode_error(
      error,
      99 + bit_array.byte_size(first_stack),
      "transaction.witnesses[1].items.count",
    )
    == PolicyLimitExceeded(MaxWitnessItemCount, 4, 3)
}

pub fn deserialize_with_policy_rejects_total_witness_item_count_before_parsing_stack_items_test() {
  // The first stack has two valid zero-length items. The second declares two
  // more, exceeding the transaction-wide limit of three at its count field.
  // Its first item has a non-minimal length encoding, so parsing it would return
  // NonMinimalCompactSize. Expecting PolicyLimitExceeded proves the cumulative
  // count is checked before any items in the second stack are parsed.
  let bytes =
    build_transaction_with_witness_stacks([
      empty_items_stack(2),
      <<2, 0xFD, 0, 0, 0>>,
    ])
  let assert Error(error) =
    transaction.deserialize_with_policy(
      bytes,
      policy_with_max_witness_item_count(3),
    )

  assert decode_assertions.check_transaction_decode_error(
      error,
      102,
      "transaction.witnesses[1].items.count",
    )
    == PolicyLimitExceeded(MaxWitnessItemCount, 4, 3)
}

pub fn deserialize_with_policy_prioritizes_structural_witness_item_count_error_test() {
  // The second stack claims seven items, but only six bytes remain after its
  // count. The cumulative count would also exceed the custom policy.
  let bytes =
    build_transaction_with_witness_stacks([
      empty_items_stack(1),
      <<7, 0, 0>>,
    ])
  let assert Error(error) =
    transaction.deserialize_with_policy(
      bytes,
      policy_with_max_witness_item_count(1),
    )

  assert decode_assertions.check_transaction_decode_error(
      error,
      101,
      "transaction.witnesses[1].items.count",
    )
    == InsufficientBytes(7, 6)
}

pub fn deserialize_with_policy_accepts_legacy_transaction_with_zero_witness_item_limit_test() {
  let bytes = bitcoin_wire.build_minimal_legacy_transaction_bytes(1)
  let assert Ok(tx) =
    transaction.deserialize_with_policy(
      bytes,
      policy_with_max_witness_item_count(0),
    )

  assert transaction.serialize(tx) == bytes
}

pub fn deserialize_with_policy_rejects_zero_length_witness_item_with_zero_limit_test() {
  let bytes = bitcoin_wire.build_minimal_segwit_transaction_bytes()
  let assert Error(error) =
    transaction.deserialize_with_policy(
      bytes,
      policy_with_max_witness_item_count(0),
    )

  assert decode_assertions.check_transaction_decode_error(
      error,
      58,
      "transaction.witnesses[0].items.count",
    )
    == PolicyLimitExceeded(MaxWitnessItemCount, 1, 0)
}

pub fn deserialize_with_policy_rejects_superfluous_witness_record_with_zero_limit_test() {
  let bytes = build_transaction_with_witness_stacks([empty_items_stack(0)])
  let assert Error(error) =
    transaction.deserialize_with_policy(
      bytes,
      policy_with_max_witness_item_count(0),
    )

  assert decode_assertions.check_transaction_decode_error(
      error,
      58,
      "transaction",
    )
    == SuperfluousWitnessRecord
}

pub fn deserialize_with_policy_accepts_default_max_input_count_witness_stacks_without_call_stack_overflow_test() {
  let input_count = 100_000
  let stacks = list.append(list.repeat(<<0>>, input_count - 1), [<<1, 0>>])
  let bytes = build_transaction_with_witness_stacks(stacks)
  let policy = policy_with_max_tx_size(bit_array.byte_size(bytes))
  let assert Ok(tx) = transaction.deserialize_with_policy(bytes, policy)
  let assert Ok(witnesses) = transaction.get_witnesses(tx)

  assert transaction.get_input_count(tx) == input_count
  assert list.length(witnesses) == input_count
  let assert Ok(last_stack) = list.last(witnesses)
  assert list.length(transaction.get_witness_items(last_stack)) == 1
}

pub fn deserialize_accepts_399_933_witness_items_without_call_stack_overflow_test() {
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

fn build_transaction_with_witness_payload(item_length: Int) -> BitArray {
  build_transaction_with_witness_stacks([
    <<
      1,
      bitcoin_wire.compact_size(item_length):bits,
      0:size({ item_length * 8 }),
    >>,
  ])
}

fn empty_items_stack(item_count: Int) -> BitArray {
  <<bitcoin_wire.compact_size(item_count):bits, 0:size({ item_count * 8 })>>
}

fn build_transaction_with_witness_stacks(stacks: List(BitArray)) -> BitArray {
  bitcoin_wire.assemble_segwit_transaction_bytes(
    list.repeat(
      bitcoin_wire.build_input_bytes(<<0:256>>, 0, <<>>, 0),
      list.length(stacks),
    ),
    [bitcoin_wire.build_output_bytes(<<0:64>>, <<>>)],
    stacks,
  )
}

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

fn policy_with_max_witness_item_count(max_witness_item_count: Int) {
  transaction.default_decode_policy()
  |> transaction.decode_policy_with_max_witness_item_count(
    max_witness_item_count,
  )
}

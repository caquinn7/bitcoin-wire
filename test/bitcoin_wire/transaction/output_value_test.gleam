import bitcoin_wire/hash256
import bitcoin_wire/transaction.{
  type OutputValue, DuplicateInput, OutputValueOutOfRange,
  TotalOutputValueOutOfRange,
}
import gleam/int
import gleam/list
import support/bitcoin_wire
import support/crypto.{dsha256}
import support/offset_bit_array
import support/target

type OutputValueCase {
  OutputValueCase(
    bytes_le: BitArray,
    decimal: String,
    is_safe_on_js: Bool,
    is_in_money_range: Bool,
  )
}

const values = [
  OutputValueCase(
    bytes_le: <<0:64>>,
    decimal: "0",
    is_safe_on_js: True,
    is_in_money_range: True,
  ),
  OutputValueCase(
    bytes_le: <<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF>>,
    decimal: "-1",
    is_safe_on_js: True,
    is_in_money_range: False,
  ),
  OutputValueCase(
    bytes_le: <<2_100_000_000_000_000:64-little>>,
    decimal: "2100000000000000",
    is_safe_on_js: True,
    is_in_money_range: True,
  ),
  OutputValueCase(
    bytes_le: <<2_100_000_000_000_001:64-little>>,
    decimal: "2100000000000001",
    is_safe_on_js: True,
    is_in_money_range: False,
  ),
  OutputValueCase(
    bytes_le: <<0xFE, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x1F, 0>>,
    decimal: "9007199254740990",
    is_safe_on_js: True,
    is_in_money_range: False,
  ),
  OutputValueCase(
    bytes_le: <<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x1F, 0>>,
    decimal: "9007199254740991",
    is_safe_on_js: True,
    is_in_money_range: False,
  ),
  OutputValueCase(
    bytes_le: <<1, 0, 0, 0, 0, 0, 0xE0, 0xFF>>,
    decimal: "-9007199254740991",
    is_safe_on_js: True,
    is_in_money_range: False,
  ),
  OutputValueCase(
    bytes_le: <<2, 0, 0, 0, 0, 0, 0xE0, 0xFF>>,
    decimal: "-9007199254740990",
    is_safe_on_js: True,
    is_in_money_range: False,
  ),
  OutputValueCase(
    bytes_le: <<0, 0, 0, 0, 0, 0, 0x20, 0>>,
    decimal: "9007199254740992",
    is_safe_on_js: False,
    is_in_money_range: False,
  ),
  OutputValueCase(
    bytes_le: <<0, 0, 0, 0, 0, 0, 0xE0, 0xFF>>,
    decimal: "-9007199254740992",
    is_safe_on_js: False,
    is_in_money_range: False,
  ),
  OutputValueCase(
    bytes_le: <<1, 0, 0, 0, 0, 0, 0x20, 0>>,
    decimal: "9007199254740993",
    is_safe_on_js: False,
    is_in_money_range: False,
  ),
  OutputValueCase(
    bytes_le: <<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xDF, 0xFF>>,
    decimal: "-9007199254740993",
    is_safe_on_js: False,
    is_in_money_range: False,
  ),
  OutputValueCase(
    bytes_le: <<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F>>,
    decimal: "9223372036854775807",
    is_safe_on_js: False,
    is_in_money_range: False,
  ),
  OutputValueCase(
    bytes_le: <<0, 0, 0, 0, 0, 0, 0, 0x80>>,
    decimal: "-9223372036854775808",
    is_safe_on_js: False,
    is_in_money_range: False,
  ),
]

pub fn output_values_preserve_full_signed_range_and_checked_conversions_test() {
  values
  |> list.each(fn(row) {
    let inputs = [bitcoin_wire.build_input_bytes(<<0:256>>, 0, <<>>, 0)]
    let tx_bytes =
      bitcoin_wire.assemble_legacy_transaction_bytes(inputs, [
        bitcoin_wire.build_output_bytes(row.bytes_le, <<>>),
      ])

    [tx_bytes, offset_bit_array.with_one_bit_offset(tx_bytes)]
    |> list.each(fn(view) {
      let assert Ok(tx) = transaction.deserialize(view)
      let assert [output] = transaction.get_outputs(tx)
      let value: OutputValue = transaction.get_output_value(output)

      assert transaction.output_value_to_bytes_le(value) == row.bytes_le
      assert transaction.output_value_to_string(value) == row.decimal
      assert transaction.serialize(tx) == tx_bytes

      let expected = case target.is_javascript() && !row.is_safe_on_js {
        True -> Error(Nil)
        False -> int.parse(row.decimal)
      }
      assert transaction.output_value_to_int(value) == expected
    })
  })
}

pub fn output_value_consensus_errors_preserve_exact_amounts_test() {
  values
  |> list.each(fn(row) {
    let inputs = [bitcoin_wire.build_input_bytes(<<0:256>>, 0, <<>>, 0)]

    let assert Ok(tx) =
      bitcoin_wire.assemble_legacy_transaction_bytes(inputs, [
        bitcoin_wire.build_output_bytes(row.bytes_le, <<>>),
      ])
      |> transaction.deserialize

    case row.is_in_money_range {
      True -> {
        let assert Ok(validated_tx) =
          transaction.validate_context_free_consensus(tx)
        let assert [output] = transaction.get_outputs(validated_tx)
        assert transaction.output_value_to_int(transaction.get_output_value(
            output,
          ))
          == int.parse(row.decimal)
      }

      False -> {
        let assert Error([OutputValueOutOfRange(0, value)]) =
          transaction.validate_context_free_consensus(tx)
        assert transaction.output_value_to_bytes_le(value) == row.bytes_le
        assert transaction.output_value_to_string(value) == row.decimal
      }
    }
  })
}

pub fn legacy_and_segwit_serialization_and_hashes_preserve_extreme_amounts_test() {
  values
  |> list.each(fn(row) {
    let inputs = [bitcoin_wire.build_input_bytes(<<0:256>>, 0, <<>>, 0)]
    let outputs = [bitcoin_wire.build_output_bytes(row.bytes_le, <<>>)]
    let stripped =
      bitcoin_wire.assemble_legacy_transaction_bytes(inputs, outputs)
    let segwit =
      bitcoin_wire.assemble_segwit_transaction_bytes(inputs, outputs, [
        bitcoin_wire.build_witness_stack_bytes([<<0x42>>]),
      ])

    list.each([stripped, segwit], fn(bytes) {
      list.each([bytes, offset_bit_array.with_one_bit_offset(bytes)], fn(view) {
        let assert Ok(tx) = transaction.deserialize(view)
        assert transaction.serialize_stripped(tx) == stripped
        assert transaction.serialize(tx) == bytes
        assert hash256.to_bytes_le(transaction.compute_txid(tx))
          == dsha256(stripped)
        assert hash256.to_bytes_le(transaction.compute_wtxid(tx))
          == dsha256(bytes)
      })
    })
  })
}

pub fn cumulative_output_totals_remain_exact_at_money_boundaries_test() {
  let max_money = 2_100_000_000_000_000

  [0, 1, max_money]
  |> list.each(fn(last_value) {
    let inputs = [bitcoin_wire.build_input_bytes(<<0:256>>, 0, <<>>, 0)]
    let outputs = [
      bitcoin_wire.build_output_bytes(<<max_money:64-little>>, <<>>),
      bitcoin_wire.build_output_bytes(<<last_value:64-little>>, <<>>),
    ]

    let assert Ok(tx) =
      bitcoin_wire.assemble_legacy_transaction_bytes(inputs, outputs)
      |> transaction.deserialize

    case last_value {
      0 -> {
        let assert Ok(_) = transaction.validate_context_free_consensus(tx)
        Nil
      }

      _ -> {
        assert transaction.validate_context_free_consensus(tx)
          == Error([
            TotalOutputValueOutOfRange(1, max_money + last_value),
          ])
      }
    }
  })
}

pub fn extreme_output_failure_keeps_first_amount_and_other_violation_order_test() {
  let min_i64 = <<0, 0, 0, 0, 0, 0, 0, 0x80>>
  let max_i64 = <<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F>>
  let input = bitcoin_wire.build_input_bytes(<<1:256>>, 0, <<>>, 0)

  let assert Ok(tx) =
    bitcoin_wire.assemble_legacy_transaction_bytes([input, input], [
      bitcoin_wire.build_output_bytes(min_i64, <<>>),
      bitcoin_wire.build_output_bytes(max_i64, <<>>),
    ])
    |> transaction.deserialize

  let assert Error([OutputValueOutOfRange(0, value), DuplicateInput(_, 0, 1)]) =
    transaction.validate_context_free_consensus(tx)

  assert transaction.output_value_to_bytes_le(value) == min_i64
}

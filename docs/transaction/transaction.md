# `bitcoin_wire/transaction`

The transaction domain deserializes, inspects, validates, and serializes Bitcoin
transactions while preserving Bitcoin's wire representation.

## Features

- **Safe deserialization**: Configurable resource limits constrain work and
  allocation when deserializing untrusted transaction bytes.
- **Rich decode diagnostics**: Decode errors include byte offsets and stable
  structural paths.
- **Format detection**: Legacy and SegWit transaction encodings remain distinct.
- **Transaction inspection**: Access versions, lock times, inputs, outputs,
  outpoints, script bytes, output values, and SegWit witness stacks.
- **Script classification**: Structurally identify P2PKH, P2SH, P2WPKH, P2WSH,
  P2TR, P2A, and other output script templates.
- **Context-free consensus validation**: Check transaction-local rules such as
  input/output presence, Bitcoin Core's transaction base-size check (at most
  1,000,000 stripped bytes, excluding witness data), output value ranges,
  coinbase structure, and duplicate inputs. Witness data excluded by that
  base-size check still contributes to the separate 4,000,000-WU block-weight
  limit.
- **Validation-aware API**: Phantom types distinguish parsed transactions from
  transactions that passed context-free consensus validation.
- **Serialization, measurements, and identifiers**: Produce stripped or full
  wire bytes, compute BIP 141 base size, total size, weight, and upward-rounded
  virtual size in vbytes, and compute txids and wtxids.

## Quick Start

```gleam
import bitcoin_wire/hash256
import bitcoin_wire/transaction
import gleam/result

pub fn display_txid_from_bytes(
  bytes: BitArray,
) -> Result(String, transaction.DecodeError) {
  bytes
  |> transaction.deserialize
  |> result.map(transaction.compute_txid)
  |> result.map(hash256.to_display_hex)
}

pub fn txid_bytes_from_hex(
  hex: String,
) -> Result(BitArray, transaction.DeserializeHexError) {
  hex
  |> transaction.deserialize_hex
  |> result.map(transaction.compute_txid)
  |> result.map(hash256.to_bytes_le)
}
```

Outpoint txids and computed txids and wtxids are exposed as `Hash256` values in
the same little-endian order used on the Bitcoin wire. Use
`hash256.to_display_hex` for conventional explorer notation or
`hash256.to_bytes_le` for the exact 32 wire-order bytes.

## Decode Policy

`deserialize` and `deserialize_hex` apply these defaults:

| Limit | Default |
| --- | ---: |
| Serialized transaction size | 400,000 bytes |
| Input count | 100,000 |
| Output count | 100,000 |
| Total witness item count across all input stacks | 100,000 |

Use `default_decode_policy` and the `decode_policy_with_*` builders to customize
them:

```gleam
let policy =
  transaction.default_decode_policy()
  |> transaction.decode_policy_with_max_tx_size(1_000_000)
  |> transaction.decode_policy_with_max_input_count(5_000)
  |> transaction.decode_policy_with_max_witness_item_count(50_000)

let result = transaction.deserialize_with_policy(transaction_bytes, policy)
```

The size limit applies to the complete input buffer before decoding. Input and
output count limits are checked before their collections are decoded, after
checking whether the counts can fit in the remaining bytes. Script lengths,
witness item counts, and witness item lengths must also fit the remaining input.
The witness item limit applies to the cumulative count across all input stacks,
including zero-length items; empty stacks contribute zero. Each stack's count is
checked against the remaining bytes, then against the cumulative limit before
any of that stack's items are decoded. A violation reports `MaxWitnessItemCount`
with the cumulative count and points to the current stack's item-count field.

When transactions are decoded inside a block, the block's serialized-size limit
provides the byte envelope and `max_tx_size` is ignored. Each contained
transaction still uses its configured input, output, and total witness item count
limits.

These limits constrain decoding resources, not consensus validity. A parsed
transaction has not passed script execution or context-free consensus checks,
and a strict custom policy can reject consensus-valid transactions.

## Scope

The module performs whole-value deserialization, structural inspection,
serialization, output script classification, and documented context-free
consensus checks. It does not perform full transaction validation requiring UTXO
lookup, script execution, signature verification, block context, mempool policy,
or network/RPC access.

## Documentation

- [Output script classification](https://github.com/caquinn7/bitcoin-wire/blob/main/docs/transaction/output_script_classification.md)
- [Project overview](https://github.com/caquinn7/bitcoin-wire)

# `bitcoin_wire/block`

The block domain deserializes, inspects, validates, and serializes Bitcoin
blocks while preserving Bitcoin's wire representation.

## Features

- **Safe deserialization**: Configurable block-size and transaction-count limits
  constrain work and allocation when deserializing untrusted block bytes.
- **Rich decode diagnostics**: Decode errors include byte offsets and stable
  structural paths, with contained transaction failures preserved for further
  inspection.
- **Block inspection**: Access the header, header fields, transaction count, and
  transactions in wire order.
- **Measurements and Merkle trees**: Compute BIP 141 base size, total size,
  weight, and upward-rounded virtual size in vbytes, as well as the transaction
  Merkle root with explicit `Mutated` or `NonMutated` status.
- **Context-free consensus validation**: Check proof of work, block size and
  weight limits, transaction-count bounds, the transaction Merkle root,
  coinbase placement, the legacy sigop limit, and every contained transaction's
  context-free consensus rules.
- **Validation-aware API**: Phantom types distinguish parsed blocks from blocks
  that passed the available context-free consensus checks.
- **Serialization and identifiers**: Deserialize and serialize standalone
  80-byte headers or complete blocks, and compute block hashes from headers.

## Quick Start

```gleam
import bitcoin_wire/block
import bitcoin_wire/hash256
import bitcoin_wire/transaction
import gleam/result

pub fn display_block_hash_from_bytes(
  bytes: BitArray,
) -> Result(String, block.DecodeError) {
  bytes
  |> block.deserialize
  |> result.map(block.get_header)
  |> result.map(block.compute_block_hash)
  |> result.map(hash256.to_display_hex)
}

pub fn block_hash_bytes_from_hex(
  hex: String,
) -> Result(BitArray, block.DeserializeHexError) {
  hex
  |> block.deserialize_hex
  |> result.map(block.get_header)
  |> result.map(block.compute_block_hash)
  |> result.map(hash256.to_bytes_le)
}
```

## Standalone Headers

`deserialize_header` accepts exactly one 80-byte (640-bit) block header. It
returns `InvalidHeaderBitCount` when the input is short, long, or not
byte-aligned. `deserialize_header_hex` first converts hexadecimal to bytes, so
malformed or odd-length hexadecimal is distinct from valid hexadecimal whose
decoded length is not 80 bytes.

Standalone header parsing is structural only: every exact 80-byte sequence has
the fixed header shape. It does not validate proof of work, select a network,
or establish that the header belongs to a valid chain.

```gleam
pub fn reserialize_header(
  bytes: BitArray,
) -> Result(BitArray, block.HeaderDecodeError) {
  bytes
  |> block.deserialize_header
  |> result.map(block.serialize_header)
}

pub fn display_header_hash(
  hex: String,
) -> Result(String, block.DeserializeHeaderHexError) {
  hex
  |> block.deserialize_header_hex
  |> result.map(block.compute_block_hash)
  |> result.map(hash256.to_display_hex)
}
```

`compute_block_hash` takes a `Header`, whether it was parsed directly or
obtained from a complete block with `get_header`. Its returned `Hash256` stays
in wire-order little-endian bytes. Use `hash256.to_display_hex` only when a
conventional explorer-style string is needed.

Headers can be compared structurally without reversing bytes:

```gleam
pub fn child_links_to_parent(parent: block.Header, child: block.Header) -> Bool {
  block.compute_block_hash(parent)
  == block.get_header_previous_block_hash(child)
}
```

This equality only establishes the encoded parent reference. It is not chain
validation.

## Decode Policy

The defaults accept serialized blocks up to 4,000,000 bytes and up to 20,000
transactions. Each transaction inherits the default transaction policy:
100,000 inputs, 125,000 outputs, and 4,000,000 total witness items.

These permissive ceilings accommodate canonical encodings of consensus-valid
blocks under current Bitcoin limits. Serialized size cannot exceed the
4,000,000-weight-unit block limit, and a valid transaction weighs at least 240
weight units, so the transaction-count ceiling exceeds what can fit. See
[BIP 141](https://github.com/bitcoin/bips/blob/master/bip-0141.mediawiki) and
[Bitcoin Core's consensus constants](https://github.com/bitcoin/bitcoin/blob/master/src/consensus/consensus.h).
The inherited input, output, and witness item count limits are explained in the
[transaction guide](https://github.com/caquinn7/bitcoin-wire/blob/main/docs/transaction/transaction.md#decode-policy).

Serialized size does not directly bound heap usage. Callers with tighter
resource budgets can configure lower byte and collection-count limits.

Block decoding applies the limit configured by
`block.decode_policy_with_max_block_size` to the complete block byte envelope
and uses the configured transaction policy for every contained transaction. For
example, a caller can restrict each transaction's input, output, and total witness
item counts while keeping the block limits at their defaults:

```gleam
let transaction_policy =
  transaction.default_decode_policy()
  |> transaction.decode_policy_with_max_input_count(5_000)
  |> transaction.decode_policy_with_max_output_count(10_000)
  |> transaction.decode_policy_with_max_witness_item_count(50_000)

let policy =
  block.default_decode_policy()
  |> block.decode_policy_with_transaction_policy(transaction_policy)

let result = block.deserialize_with_policy(block_bytes, policy)
```

The limit configured by `transaction.decode_policy_with_max_tx_size` is ignored
for contained transactions. The block's maximum serialized size remains the
only byte-envelope limit for the block and its transactions.
The input, output, and total witness item count limits apply separately to each
transaction.

Previous-block hashes, Merkle roots, and computed block hashes are exposed as
`Hash256` values in the same little-endian order used on the Bitcoin wire. Use
`hash256.to_display_hex` for conventional explorer notation or
`hash256.to_bytes_le` for the exact 32 wire-order bytes.

## Context-Free Consensus Validation

Deserialization produces a `Block(Parsed)`. Pass that block and the intended
network's proof-of-work limit to `validate_context_free_consensus` to obtain a
`Block(ContextFreeValidated)`:

For mainnet, supply its maximum target as 32 little-endian bytes:

```gleam
let mainnet_pow_limit_le = <<0:size(208), 0xFF, 0xFF, 0:size(32)>>
let assert Ok(pow_limit) = block.new_pow_limit(mainnet_pow_limit_le)
let assert Ok(validated_block) =
  block.validate_context_free_consensus(parsed_block, pow_limit)
```

`new_pow_limit` checks that the supplied value is nonzero and exactly 32 bytes.
It cannot determine whether the value is the correct limit for the network.

Proof-of-work and block-size failures stop validation immediately. Once those
checks pass, independent block-level and transaction-level violations are
collected in deterministic validation and wire order.

Proof-of-work failures include a reason that distinguishes malformed compact
targets, targets above the supplied limit, and insufficient header work.

## Scope

The module performs whole-value deserialization, structural inspection,
serialization, hashing, measurement, Merkle-root computation, and documented
context-free consensus checks. It does not construct headers, determine the
target required by preceding headers, evaluate timestamp or transaction-finality
rules, enforce activation-based rules such as the BIP34 coinbase height or
SegWit witness commitment, or perform UTXO lookup, script execution, signature
verification, fee, or subsidy checks. Difficulty transitions, accumulated work,
chain selection, networking, SPV Merkle-proof verification, and Signet
block-solution validation are also outside its scope.

## Documentation

- [Merkle root](merkle_root.md)
- [Transaction domain](https://github.com/caquinn7/bitcoin-wire/blob/main/docs/transaction/transaction.md)
- [Project overview](https://github.com/caquinn7/bitcoin-wire)

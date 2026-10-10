# bitcoin_wire

Bitcoin transaction and block wire formats for Gleam.

<!-- [![Package Version](https://img.shields.io/hexpm/v/bitcoin_wire)](https://hex.pm/packages/bitcoin_wire)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/bitcoin_wire/) -->

`bitcoin_wire` is a Gleam library for deserializing, inspecting, hashing,
serializing, and performing context-free consensus checks on Bitcoin
transactions and blocks. It preserves exact wire values across Erlang and
JavaScript and reports malformed encodings as structured errors.

## Project Status

The following Bitcoin wire-format data structures are currently implemented:

- [`bitcoin_wire/transaction`](https://github.com/caquinn7/bitcoin-wire/blob/main/docs/transaction/transaction.md) deserializes and
  serializes legacy and SegWit transactions, exposes their fields and output
  script classifications, computes their base sizes, total sizes, weights, and
  virtual sizes, txids, and wtxids, and runs context-free consensus checks.
- [`bitcoin_wire/block`](https://github.com/caquinn7/bitcoin-wire/blob/main/docs/block/block.md) deserializes and serializes standalone
  80-byte headers and computes their block hashes. It also deserializes and
  serializes complete blocks; exposes their headers and transactions; computes
  base sizes, total sizes, weights, virtual sizes, and Merkle roots; and runs
  context-free consensus checks.
- `bitcoin_wire/hash256` provides fixed-width wire-order hashes with conversions
  to raw little-endian bytes and conventional Bitcoin display notation.

Additional domains may be added as the library expands.

<!-- ## Installation
```sh
gleam add bitcoin_wire@1
``` -->

## Goals and Philosophy

### Correctness over convenience

> Malformed or ambiguous encodings are surfaced explicitly rather than being
> silently normalized or accepted as partial values.

### Reference-grade intent

> The library is structured so it can be read alongside Bitcoin documentation
> as a reliable guide to wire formats and protocol data structures.

### Faithful protocol modeling

> Protocol distinctions and encoded forms are preserved rather than collapsed
> into convenience abstractions.

### Cross-runtime portability

> Public behavior remains consistent across the supported runtimes:
> Erlang and Node.js.

Native browser builds are not currently supported. The JavaScript hashing
implementation imports `node:crypto`, which is available in Node.js but not
through native browser APIs.

## Scope

This project deserializes and models caller-provided Bitcoin data. It is not a
wallet, full node, RPC client, or networking library. Domain-specific
documentation describes the exact deserialization, validation, and policy
boundaries for each implemented module.

No security guarantees are provided.

## Use Cases

- **Explorers and blockchain indexers**: Turn externally obtained Bitcoin wire
  bytes into structured blocks and transactions for display, search, and
  downstream analysis.
- **Monitoring and research**: Inspect caller-provided feeds and datasets for
  transaction shapes, script types, witness usage, block composition, Merkle
  roots, and context-free consensus violations.
- **Protocol and data tooling**: Add a portable deserialization, inspection, and
  context-free validation layer ahead of application-specific processing.
- **Testing and education**: Study Bitcoin wire encoding and exercise software
  with valid, malformed, and consensus-invalid block and transaction data.

## Development

Run the unit tests on Erlang and Node.js:

```sh
gleam test -t erlang
gleam test -t javascript --runtime node
```

### Fuzz Testing

The standalone [fuzz harness](https://github.com/caquinn7/bitcoin-wire/blob/main/fuzz/README.md) exercises transaction and block
parser safety against malformed and mutated wire-format inputs. Run a selected
suite with `./fuzz/run -- <suite> <iterations> [seed]`; target and runtime
options go before `--`.

### Benchmarking

The standalone [performance harness](https://github.com/caquinn7/bitcoin-wire/blob/main/benchmarks/README.md) measures public
deserialization and inspection workflows across representative inputs, scaling
dimensions, and fail-fast paths. Run the complete suite with
`./benchmarks/run`, or pass benchmark arguments after `--`, for example
`./benchmarks/run -- --section transaction.deserialize.fixtures`.

### Examples

The standalone [examples project](https://github.com/caquinn7/bitcoin-wire/blob/main/examples/README.md) uses mempool.space raw
mainnet data to demonstrate transaction JSON output, block metrics,
context-free block validation, and structured transaction decode errors. Run an
example from the repository root with, for example,
`./examples/run -- block-metrics 0`.

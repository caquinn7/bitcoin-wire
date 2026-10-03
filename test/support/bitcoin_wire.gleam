//// Test-only helpers for constructing Bitcoin wire encodings.
////
//// Helper names describe the abstraction they return:
////
//// - `build_*_bytes` constructs an encoded component from field values.
//// - `build_minimal_*_section_bytes` returns a count-prefixed minimal fixture.
//// - `assemble_*_bytes` combines existing encodings into a container.
////
//// Names use full domain terminology and an explicit `_bytes` suffix when
//// returning wire bytes so their result is clear at the call site.

import gleam/bit_array
import gleam/list

// ============================================================================
// Common byte helpers and CompactSize
// ============================================================================

/// Encode a non-negative integer as a minimal CompactSize byte array.
pub fn compact_size(value: Int) -> BitArray {
  case value {
    _ if value < 0 -> panic as "compact_size: negative values not supported"
    _ if value <= 252 -> <<value:size(8)>>
    _ if value <= 65_535 -> <<0xFD, value:little-size(16)>>
    _ if value <= 4_294_967_295 -> <<0xFE, value:little-size(32)>>
    _ -> <<0xFF, value:little-size(64)>>
  }
}

/// Produce a `BitArray` consisting of `n` repetitions of byte `b`.
pub fn repeat_byte(b: Int, n: Int) -> BitArray {
  case n {
    _ if n < 0 -> panic as "count cannot be negative"
    _ -> bit_array.concat(list.repeat(<<b:little-size(8)>>, times: n))
  }
}

// ============================================================================
// Transaction components and assembly
// ============================================================================

/// The minimum encoded input size: a 32-byte txid, 4-byte output index,
/// one-byte empty script length, and 4-byte sequence.
pub const min_input_size_bytes = 41

/// The minimum encoded output size: an 8-byte value and one-byte empty script
/// length.
pub const min_output_size_bytes = 9

/// The four-byte wire encoding of transaction version 1.
pub const transaction_version_1_bytes = <<1:little-size(32)>>

/// Build one encoded transaction input from its field values.
pub fn build_input_bytes(
  outpoint_txid: BitArray,
  outpoint_vout: Int,
  script_sig: BitArray,
  sequence: Int,
) -> BitArray {
  let outpoint_vout_bytes = <<outpoint_vout:little-size(32)>>
  let script_length = compact_size(bit_array.byte_size(script_sig))
  let sequence_bytes = <<sequence:little-size(32)>>

  <<
    outpoint_txid:bits,
    outpoint_vout_bytes:bits,
    script_length:bits,
    script_sig:bits,
    sequence_bytes:bits,
  >>
}

/// Build one encoded transaction output from its field values.
pub fn build_output_bytes(
  value: BitArray,
  script_pubkey: BitArray,
) -> BitArray {
  let script_length = compact_size(bit_array.byte_size(script_pubkey))

  <<
    value:bits,
    script_length:bits,
    script_pubkey:bits,
  >>
}

/// Return an input section containing a count and one minimal encoded input.
pub fn build_minimal_input_section_bytes() -> BitArray {
  let input_count = compact_size(1)
  let input = build_input_bytes(<<0:size(256)>>, 0, <<>>, 0)
  <<input_count:bits, input:bits>>
}

/// Return an output section containing a count and one minimal encoded output.
pub fn build_minimal_output_section_bytes() -> BitArray {
  let output_count = compact_size(1)
  let output = build_output_bytes(<<0:little-size(64)>>, <<>>)
  <<output_count:bits, output:bits>>
}

/// Build a minimal legacy transaction with the supplied version.
pub fn build_minimal_legacy_transaction_bytes(version: Int) -> BitArray {
  <<
    version:little-size(32),
    build_minimal_input_section_bytes():bits,
    build_minimal_output_section_bytes():bits,
    0:little-size(32),
  >>
}

/// Build a minimal SegWit transaction with one zero-length witness item.
pub fn build_minimal_segwit_transaction_bytes() -> BitArray {
  let witness_stack = <<
    compact_size(1):bits,
    compact_size(0):bits,
  >>

  assemble_segwit_transaction_bytes(
    [build_input_bytes(<<0:size(256)>>, 0, <<>>, 0)],
    [build_output_bytes(<<0:little-size(64)>>, <<>>)],
    [witness_stack],
  )
}

/// Build one witness stack from its item payloads, including all length prefixes.
pub fn build_witness_stack_bytes(items: List(BitArray)) -> BitArray {
  let item_count = compact_size(list.length(items))
  let fragments =
    list.flat_map(items, fn(item) {
      [compact_size(bit_array.byte_size(item)), item]
    })

  bit_array.concat([item_count, ..fragments])
}

/// Assemble SegWit transaction bytes from encoded components without validating them.
pub fn assemble_segwit_transaction_bytes(
  inputs: List(BitArray),
  outputs: List(BitArray),
  witness_stacks: List(BitArray),
) -> BitArray {
  let input_count = compact_size(list.length(inputs))
  let output_count = compact_size(list.length(outputs))

  <<
    transaction_version_1_bytes:bits,
    0x00,
    0x01,
    input_count:bits,
    bit_array.concat(inputs):bits,
    output_count:bits,
    bit_array.concat(outputs):bits,
    bit_array.concat(witness_stacks):bits,
    0:little-size(32),
  >>
}

// ============================================================================
// Block headers and assembly
// ============================================================================

/// Build an encoded 80-byte block header from its field values.
pub fn build_block_header_bytes(
  version: Int,
  previous_block_hash: BitArray,
  merkle_root: BitArray,
  timestamp: Int,
  target: Int,
  nonce: Int,
) -> BitArray {
  <<
    version:32-little,
    previous_block_hash:bits,
    merkle_root:bits,
    timestamp:32-little,
    target:32-little,
    nonce:32-little,
  >>
}

/// Build a block containing an encoded header and zero transactions.
pub fn build_header_only_block_bytes(
  version: Int,
  previous_block_hash: BitArray,
  merkle_root: BitArray,
  timestamp: Int,
  target: Int,
  nonce: Int,
) -> BitArray {
  assemble_block_bytes(
    build_block_header_bytes(
      version,
      previous_block_hash,
      merkle_root,
      timestamp,
      target,
      nonce,
    ),
    [],
  )
}

/// Assemble a block by deriving its CompactSize transaction count.
pub fn assemble_block_bytes(
  header: BitArray,
  transactions: List(BitArray),
) -> BitArray {
  assemble_block_from_transaction_payload_bytes(
    header,
    list.length(transactions),
    bit_array.concat(transactions),
  )
}

/// Assemble a block from an explicit transaction count and raw payload.
pub fn assemble_block_from_transaction_payload_bytes(
  header: BitArray,
  transaction_count: Int,
  payload: BitArray,
) -> BitArray {
  <<
    header:bits,
    compact_size(transaction_count):bits,
    payload:bits,
  >>
}

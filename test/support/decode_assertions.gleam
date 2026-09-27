//// Test-only assertions for block and transaction decode errors.

import bitcoin_wire/block
import bitcoin_wire/transaction

/// Assert the common location details of a block decode error and return its kind.
pub fn check_block_decode_error(
  error: block.DecodeError,
  expected_offset: Int,
  expected_path: String,
) -> block.DecodeErrorKind {
  assert block.get_decode_error_offset(error) == expected_offset
  assert block.get_decode_error_path(error) == expected_path
  block.get_decode_error_kind(error)
}

/// Assert the common location details of a transaction decode error and return
/// its kind for the caller to compare.
pub fn check_transaction_decode_error(
  error: transaction.DecodeError,
  expected_offset: Int,
  expected_path: String,
) -> transaction.DecodeErrorKind {
  assert transaction.get_decode_error_offset(error) == expected_offset
  assert transaction.get_decode_error_path(error) == expected_path
  transaction.get_decode_error_kind(error)
}

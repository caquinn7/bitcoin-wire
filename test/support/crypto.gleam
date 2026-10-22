//// Test-only hashing helpers independent of the library's hash implementation.

import gleam/crypto.{Sha256}

/// Hash bytes twice with SHA-256, returning the raw digest bytes.
pub fn dsha256(bytes: BitArray) -> BitArray {
  bytes
  |> crypto.hash(Sha256, _)
  |> crypto.hash(Sha256, _)
}

-module(bitcoin_wire_benchmarks_ffi).
-export([exit_failure/0]).

exit_failure() -> erlang:halt(1).

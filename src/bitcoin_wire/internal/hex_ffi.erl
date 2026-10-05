-module(hex_ffi).
-export([has_only_hex_digits/1]).

-define(IS_HEX_DIGIT(Byte),
        (((Byte) >= $0 andalso (Byte) =< $9)
         orelse ((Byte) >= $A andalso (Byte) =< $F)
         orelse ((Byte) >= $a andalso (Byte) =< $f))).

% Check sixteen bytes per iteration to reduce recursion overhead on large input.
has_only_hex_digits(<<
    A, B, C, D, E, F, G, H,
    I, J, K, L, M, N, O, P,
    Rest/binary
>>)
    when ?IS_HEX_DIGIT(A)
         andalso ?IS_HEX_DIGIT(B)
         andalso ?IS_HEX_DIGIT(C)
         andalso ?IS_HEX_DIGIT(D)
         andalso ?IS_HEX_DIGIT(E)
         andalso ?IS_HEX_DIGIT(F)
         andalso ?IS_HEX_DIGIT(G)
         andalso ?IS_HEX_DIGIT(H)
         andalso ?IS_HEX_DIGIT(I)
         andalso ?IS_HEX_DIGIT(J)
         andalso ?IS_HEX_DIGIT(K)
         andalso ?IS_HEX_DIGIT(L)
         andalso ?IS_HEX_DIGIT(M)
         andalso ?IS_HEX_DIGIT(N)
         andalso ?IS_HEX_DIGIT(O)
         andalso ?IS_HEX_DIGIT(P) ->
    has_only_hex_digits(Rest);
has_only_hex_digits(Hex) ->
    has_only_hex_digits_tail(Hex).

% A separate tail scanner lets the compiler reuse the binary match context in
% the sixteen-byte loop instead of constructing a sub-binary on every iteration.
has_only_hex_digits_tail(<<Byte, Rest/binary>>)
    when ?IS_HEX_DIGIT(Byte) ->
    has_only_hex_digits_tail(Rest);
has_only_hex_digits_tail(<<>>) ->
    true;
has_only_hex_digits_tail(_) ->
    false.

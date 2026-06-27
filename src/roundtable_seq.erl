%% @doc Monotonic per-session sequence counters backed by :atomics.
%% Lock-free, strictly increasing, safe under concurrent access from
%% many processes. One ref per table; every accepted delta gets next/1.
-module(roundtable_seq).
-export([new/0, next/1, current/1]).

-spec new() -> atomics:atomics_ref().
new() ->
    atomics:new(1, [{signed, false}]).

-spec next(atomics:atomics_ref()) -> pos_integer().
next(Ref) ->
    atomics:add_get(Ref, 1, 1).

-spec current(atomics:atomics_ref()) -> non_neg_integer().
current(Ref) ->
    atomics:get(Ref, 1).

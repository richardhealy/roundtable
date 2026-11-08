# Progress

Milestones M0 to M8 from the spec are implemented (single-node session core,
Channels and Presence, the Erlang `:atomics` sequence module, the `:queue`
initiative ring, Horde and DeltaCrdt distribution, telemetry and LiveDashboard,
the load test, and the production release). CI runs format, credo --strict,
compile with warnings as errors, the test suite and dialyzer on every push.

## Recent changes

- 2026-11-08: rewinding from the very first turn (round 1, leader up) used to
  step back to the last combatant while staying on round 1, so the next advance
  reported round 2 although no full round had passed. `Initiative.rewind/1` now
  leaves the ring as it is on that turn (new `Initiative.first_turn?/1`), and
  `TableState` answers the intent with `:noop`, so the session neither uses a
  sequence number nor broadcasts. A model-based property test (the turn and
  round always match the number of turns taken, with a rewind never going
  before the first) plus unit, `TableState` and session tests cover it.
- 2026-11-07: a table restored after its session died could count rounds
  differently from the live table when the top initiative roll was tied.
  `Initiative.restore/2` picked the leader with `Enum.max_by` over the rotated
  order, so with amy 18, bob 18, cat 9 and one advance it chose bob, while
  `build/1` had chosen amy (ties go to the lower combatant id). The restored
  table then stayed on round 1 when amy was up again. Both functions now use
  the same ordering key. A unit test, a property test (restore at any point,
  then play the same moves on both rings) and a `TableState` snapshot test
  cover it.
- 2026-10-06: `set_initiative` with a roll that is not an integer (a string,
  `null`, a float) raised inside the table's GenServer. The table process
  crashed, the calling channel crashed with it, and a handful of these in quick
  succession exceeded Horde's restart limit (3 in 5 seconds), which took down
  `Roundtable.Session.Supervisor` and every table on the node.
  `Initiative.build/1` now rejects such rolls with `{:error, :invalid_roll}`.
  Regression tests cover the ring, the pure state, the session and the channel.

## Known bugs

- None open.

## Not done yet

- Project dossier (docs/dossier). Note that `/docs/` is in `.gitignore` (local
  design notes), so the dossier path needs an exception there before it can be
  committed.
- Spec stretch goals: snapshots to Postgres or ETS for cold start, CRDT merge
  for offline edits, a LiveView spectator page.

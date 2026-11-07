# Progress

Milestones M0 to M8 from the spec are implemented (single-node session core,
Channels and Presence, the Erlang `:atomics` sequence module, the `:queue`
initiative ring, Horde and DeltaCrdt distribution, telemetry and LiveDashboard,
the load test, and the production release). CI runs format, credo --strict,
compile with warnings as errors, the test suite and dialyzer on every push.

## Recent changes

- 2026-10-06: `set_initiative` with a roll that is not an integer (a string,
  `null`, a float) raised inside the table's GenServer. The table process
  crashed, the calling channel crashed with it, and a handful of these in quick
  succession exceeded Horde's restart limit (3 in 5 seconds), which took down
  `Roundtable.Session.Supervisor` and every table on the node.
  `Initiative.build/1` now rejects such rolls with `{:error, :invalid_roll}`.
  Regression tests cover the ring, the pure state, the session and the channel.

## Known bugs

- Tied top roll after a restore: `Initiative.restore/2` picks the leader with
  `Enum.max_by` over the rotated order, while `build/1` breaks ties by
  combatant id. With rolls amy 18, bob 18, cat 9, a session restored after one
  advance treats bob as the leader, so the round counter lags by one turn
  (live ring: round 2 when amy is up again; restored ring: still round 1).
- Rewinding from the very first turn (round 1, leader up) stays on round 1 but
  moves to the last combatant; advancing again then reports round 2 although no
  full round has passed.

## Not done yet

- Project dossier (docs/dossier). Note that `/docs/` is in `.gitignore` (local
  design notes), so the dossier path needs an exception there before it can be
  committed.
- Spec stretch goals: snapshots to Postgres or ETS for cold start, CRDT merge
  for offline edits, a LiveView spectator page.

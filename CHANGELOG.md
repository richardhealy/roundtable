# Changelog

## 2026-11-08

### Fixed

- Rewinding on the very first turn of combat (round 1, with the leader up) no
  longer moves the turn to the last combatant. Before this, the next advance
  reported round 2 although no full round had passed. The rewind is now a
  no-op: the channel replies `{"seq": "noop"}` and nothing is broadcast.

## 2026-11-07

### Fixed

- A table restored from the cluster replica now picks the same initiative
  leader as the live table when the top roll is tied, so both bump the round
  on the same turn. Before this, `Initiative.restore/2` took the first
  highest roll in rotation order instead of breaking the tie by combatant id
  as `build/1` does, and the restored table's round counter fell one behind.

## 2026-10-06

### Fixed

- A `set_initiative` intent with a roll that is not an integer no longer
  crashes the table's session process. `Initiative.build/1` returns
  `{:error, :invalid_roll}` and the channel replies with that reason. Before
  this, repeated bad rolls could exhaust the Horde supervisor's restart limit
  and stop every table on the node.

### Added

- PROGRESS.md with current status and known bugs, and this changelog.
- README lists the reasons a rejected intent can come back with.

## v0.1.0 (2026-06-27)

- Milestones M0 to M8: session core, Channels and Presence, `:atomics`
  sequence numbers, `:queue` initiative ring, Horde and DeltaCrdt
  distribution with node-kill survival, telemetry and LiveDashboard, load
  test, `mix release` and Docker images.

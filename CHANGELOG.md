# Changelog

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

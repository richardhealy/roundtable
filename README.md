# roundtable

An authoritative, real-time multiplayer **session server** on the BEAM. One
supervised process per table holds authoritative state; clients send intents,
the server validates and broadcasts strictly-ordered deltas, and reconnecting
clients resume from the current snapshot.

## Why the BEAM

- **A process per session.** Each table is its own `GenServer`
  ([`Roundtable.Session.Server`](lib/roundtable/session/server.ex)). Isolation
  is the default — one crashing table cannot disturb another (proven by a test).
- **A genuine drop to Erlang.** Per-table sequence numbers come from a native
  `:atomics` module ([`src/roundtable_seq.erl`](src/roundtable_seq.erl)); turn
  order is an Erlang `:queue` ring ([`Roundtable.Initiative`](lib/roundtable/initiative.ex)).
- **Soft-real-time transport.** Phoenix Channels + Presence + PubSub.
- **Survives a node dying.** Tables are addressable cluster-wide (Horde) and each
  table's state is replicated across the cluster (DeltaCrdt), so a session lives
  through an ungraceful `kill -9` of the node it ran on — see below.

Implemented milestones: **M0–M8** — single-node real-time core, distribution and
node-kill survival, observability, a load test, and a production release.

## Architecture at a glance

```
client ──ws──> TableChannel ──> Roundtable.Session (facade)
                                   │  find_or_start (Registry + DynamicSupervisor)
                                   ▼
                            Session.Server (GenServer, authoritative)
                                   │  TableState.apply_intent/2  (pure validate+apply)
                                   │  Seq.next/1                 (:atomics, ordered)
                                   ▼
                            Phoenix.PubSub "table:<id>"  ──{:delta, %{seq, …}}──> all channels
```

- **Presence** tracks who is *connected*; **`TableState.players`** tracks who is
  *at the table*. Disconnecting drops Presence only — leaving the table is an
  explicit `leave` intent. That separation is what makes reconnect/resume clean.
- **Only accepted, state-changing intents** consume a seq and broadcast. Rejects
  and no-ops do neither.

## Run it (Docker — no host Elixir needed)

```bash
make setup     # fetch + compile deps
make server    # http://localhost:4000  (LiveDashboard at /dev/dashboard)
make test      # full test suite
make check     # format + credo --strict + dialyzer + test (the CI bundle)
```

## Try the real-time core

Mint a signed token, then connect a Channel client to `table:<id>`:

```bash
docker compose run --rm app mix roundtable.token amy
```

Connect a websocket to `ws://localhost:4000/socket` with `?token=<token>`, join
topic `table:my-table`, then send intents on the `"intent"` event:

| intent | payload |
| --- | --- |
| set initiative | `{"type":"set_initiative","rolls":[{"combatant_id":"amy","roll":18},{"combatant_id":"bob","roll":9}]}` |
| advance turn | `{"type":"advance_turn"}` |
| rewind turn | `{"type":"rewind_turn"}` |
| leave table | `{"type":"leave"}` |

On join the client receives a `"state"` snapshot (`%{state, seq}`); every
accepted intent broadcasts a `"delta"` carrying a strictly-monotonic `seq`.
Order/dedupe deltas by `seq` on the client.

A rejected intent replies with `{"reason": ...}` and broadcasts nothing. The
reasons are `no_initiative`, `not_a_player`, `empty`, `duplicate_combatant`,
`invalid_roll` (a roll that is not an integer), `bad_initiative` (a roll entry
that is not an object with `combatant_id` and `roll`) and `unknown_intent`.
None of these crash the table's process.

## Distribution & node-kill survival (M5)

Tables are addressable cluster-wide via `Horde.Registry`/`Horde.DynamicSupervisor`,
and each table's authoritative snapshot is replicated across the cluster on every
accepted intent via a `DeltaCrdt` store ([`Roundtable.StateReplica`](lib/roundtable/state_replica.ex)).
When a node dies, Horde restarts its sessions on a surviving node and each restores
`{players, initiative, last_seq}` from the replica — the sequence continues without
collision. (`Phoenix.PubSub` already fans out deltas cluster-wide, so no extra wiring
is needed for clients on other nodes.)

Run a 3-node cluster (auto-formed via libcluster Epmd on the compose network):

```bash
docker compose -f docker-compose.cluster.yml up    # nodes on :4001, :4002, :4003
```

Kill-survival demo:
1. Drive a table on any node (join, set initiative, advance a turn).
2. `docker compose -f docker-compose.cluster.yml kill -s SIGKILL node3` — kill the
   node holding the session, ungracefully.
3. Read the table from another node: the roster, initiative, and current turn are
   intact and the sequence continues.

The restore + seq-continuity mechanism is also covered by an automated single-node
test (`test/roundtable/session_test.exs` — kill the session process, Horde restarts
it, state is restored from the replica).

## Observability (M6)

The hot paths emit Telemetry — intent latency + result, session started/restored,
delta throughput — registered as metrics on the dev LiveDashboard:

```bash
make server   # then open http://localhost:4000/dev/dashboard
```

- **Metrics tab:** intent latency and counts by result (accepted/rejected/noop),
  deltas by type, session starts broken out by `restored` (so node-kill restores
  show up), and a live active-sessions gauge.
- **Sessions tab:** a live table of every active table — id, players, current turn,
  round, last seq — read straight from the replicated CRDT
  ([`RoundtableWeb.SessionsDashboardPage`](lib/roundtable_web/sessions_dashboard_page.ex)).

## Load test (M7)

A built-in in-node load harness ([`Roundtable.LoadTest`](lib/roundtable/load_test.ex))
spins up many sessions, drives intents, and reports memory per session and broadcast
latency (the `apply_intent`→delta path, including the cluster-replicated snapshot write):

```bash
docker compose run --rm app mix roundtable.loadtest 5000
```

Result on a single Docker container (illustrative, not a benchmark claim):

| sessions | memory / session | p50 | p99 |
| --- | --- | --- | --- |
| 5,000 | 8.8 KB | 16µs | 50µs |

So ~115k live sessions per GB, with sub-100µs p99 broadcast latency — each session a
full GenServer whose state is replicated across the cluster. (p99.9 is tail-noisy on
a single container — dominated by occasional GC pauses; ~10k sessions OOMs this
machine's Docker VM, so 5k is the documented run.)

Chaos is covered by the M5 node-kill demo above: bring up the 3-node cluster, kill the
node holding a session, and watch it resume on a survivor with state intact.

## Production release (M8)

Build the production image (multi-stage `mix release`) and run it:

```bash
docker build -f Dockerfile -t roundtable:release .
docker run -p 4000:4000 -e SECRET_KEY_BASE=$(mix phx.gen.secret) \
  -e PHX_HOST=localhost -e PHX_SERVER=true roundtable:release
```

Run the **release** as a 3-node cluster — distributed Erlang via
`RELEASE_DISTRIBUTION=sname` (`rel/env.sh.eex`), clustered by libcluster Epmd — so the
node-kill survival demo runs on the production image, not just dev `mix`:

```bash
docker compose -f docker-compose.release.yml up   # 3 release nodes on :4001-:4003
# kill the node holding a session; it resumes on a survivor with state intact
```

API docs: `mix docs` generates browsable HTML under `doc/`.

## Layout

```
src/roundtable_seq.erl              native Erlang :atomics sequence counters
lib/roundtable/
  initiative.ex                     :queue turn-order ring (pure)
  table_state.ex                    authoritative struct + apply_intent/2 (pure)
  state_replica.ex                  DeltaCrdt-backed cluster snapshot store (M5)
  session.ex                        facade: find_or_start / apply_intent / get_state
  session/{registry,supervisor,server,seq}.ex   registry/supervisor backed by Horde (M5)
lib/roundtable_web/
  channels/{user_socket,table_channel}.ex
  presence.ex
docker-compose.cluster.yml          3-node demo cluster (M5)
```

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

This cycle implements milestones **M0–M4** (single node). Distribution
(Horde/libcluster/`:pg`), load & chaos testing, observability panels, and
release packaging are M5–M8 (see the project plan).

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

## Layout

```
src/roundtable_seq.erl              native Erlang :atomics sequence counters
lib/roundtable/
  initiative.ex                     :queue turn-order ring (pure)
  table_state.ex                    authoritative struct + apply_intent/2 (pure)
  session.ex                        facade: find_or_start / apply_intent / get_state
  session/{registry,supervisor,server,seq}.ex
lib/roundtable_web/
  channels/{user_socket,table_channel}.ex
  presence.ex
```

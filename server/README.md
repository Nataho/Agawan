# Agawan — Dedicated Python Game Server

Backend for **Agawan** (Visayan Tayukok / Agawan Base arena).
Branch `server` (branched from `feature` — `main` is protected).

## Protocol (must match Godot)

Transport: WebSocket `ws://127.0.0.1:8080` (default).

Every frame is JSON:

```json
{ "signal_name": "<name>", "raw_data": { ... } }
```

Compatible with:
- `Classes/Network/NetworkClient/NetworkClient.gd` → `send_signal_to_server(signal_name, raw_data)`
- `Classes/Network/NetworkServer/NetworkServer.gd` → same shape
- `Scenes/Test/NetworkTest.gd` → UI sends `ping`, `chat_message`, receives `pong`, `chat_message`

## Implemented signals (authoritative)

| Direction | signal_name | raw_data | Notes |
|---|---|---|---|
| C→S | `ping` | `{timestamp, message}` | Server replies `pong` |
| S→C | `pong` | `{reply, client_id}` | |
| C→S / S→C | `chat_message` | `{sender, message, time}` | Server broadcasts to room |
| C→S | `join` | `{name, team, role}` | Assigns `client_id`, default team/role |
| S→C | `welcome` | `{client_id, server_time, message}` | Sent on join |
| S→C | `player_joined` | `{client_id, name, team, role}` | Broadcast, excluded sender |
| S→C | `player_left` | `{client_id}` | Broadcast |
| C→S | `exit_base` | `{}` | Locks `exit_timestamp = server_time()` |
| S→C | `freshness` | `{client_id, exit_time, aura}` | `predator` < 15s else `neutral` |
| C→S | `tag_attempt` | `{target_id}` | Server resolves Fresh Touch |
| S→C | `tag_resolved` | `{attacker_id, target_id, result, reason}` | `tagged` / `clash` / `denied` |
| S→C | `state` | `{server_time, players}` | 20 Hz tick broadcast |

## Fresh Touch rules (Chapter 1)

- `exit_base` locks `exit_timestamp` (server clock, monotonic).
- Later exit = Predator over earlier exit on same pair.
- `|t_a - t_b| <= 0.25s` → `clash` (knockback, no elimination).
- Priority expires after `15.0s` → `neutral`, must re-touch base.
- Tagged player → `jailed=true` (holding cell teleport is client-side).

## Run

```bash
# from Agawan/
server/.venv/bin/python -m server.src.main --host 127.0.0.1 --port 8080

# or via venv shell:
source server/.venv/bin/activate
python -m server.src.main --host 0.0.0.0 --port 8080
```

Test with Godot: `Scenes/Test/NetworkTest.tscn` →
set `ClientIPEdit=127.0.0.1`, `ClientPortEdit=8080`, `Connect Client`,
then `Send Ping` / `Send Chat`.

Or headless smoke:
```bash
server/.venv/bin/python -m server.tests.smoke_test
server/.venv/bin/python -m pytest server/tests -v
```

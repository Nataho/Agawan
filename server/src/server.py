"""Asyncio WebSocket server mirroring Godot NetworkClient/Server protocol.

Run:
    python -m server.src.main --host 127.0.0.1 --port 8080

Godot test scene:
    Scenes/Test/NetworkTest.tscn -> Connect Client -> Send Ping / Send Chat
"""
from __future__ import annotations

import argparse
import asyncio
import json
import logging
import time

import websockets

from . import config
from .game import GameState, server_now

log = logging.getLogger("agawan.server")


def make_payload(signal_name: str, raw_data: dict | None = None) -> str:
    return json.dumps({"signal_name": signal_name, "raw_data": raw_data or {}})


class AgawanServer:
    def __init__(self) -> None:
        self.state = GameState()
        self.conns: dict = {}
        self.lobby: set[int] = set()  # connected sockets NOT yet in a match
        self._next_id = 1
        self.started_at = server_now()
        self._last_fingerprint = None
        self._last_broadcast = 0.0
        self._last_lobby_fp = None
        self._last_lobby_send = 0.0

    async def _send(self, ws, signal_name: str, raw_data=None) -> None:
        try:
            await ws.send(make_payload(signal_name, raw_data))
        except Exception as exc:
            log.debug("send to closed socket ignored: %s", exc)

    async def _broadcast(self, signal_name: str, raw_data=None, exclude=None) -> None:
        dead = []
        for cid, ws in self.conns.items():
            if exclude is not None and cid == exclude:
                continue
            try:
                await ws.send(make_payload(signal_name, raw_data))
            except Exception:
                dead.append(cid)
        for cid in dead:
            self.conns.pop(cid, None)

    async def broadcast_server_message(self, message: str, sender: str = "Server") -> None:
        """Operator send: same as Godot NetworkTest _on_server_broadcast_chat."""
        message = message.strip()
        if not message:
            return
        log.info('[Server Broadcast]: %s', message)
        await self._broadcast("chat_message", {
            "sender": sender,
            "message": message,
            "time": time.strftime("%H:%M:%S"),
        })

    def _lobby_snapshot(self) -> dict:
        in_match = set(self.state.players.keys())
        waiting = sorted([c for c in self.lobby if c in self.conns])
        return {
            "server_time": server_now(),
            "lobby_count": len(waiting),
            "lobby_ids": waiting,
            "match_count": len(in_match),
            "rooms": [],  # P1: create_room/join_room fills this
        }

    def _lobby_fingerprint(self) -> tuple:
        in_match = set(self.state.players.keys())
        waiting = tuple(sorted([c for c in self.lobby if c in self.conns]))
        return (waiting, tuple(sorted(in_match)))

    async def _tick_loop(self) -> None:
        # Lobby-first: sockets in lobby get lobby_update only on change.
        # Match state only goes to in-match players, on change + heartbeat.
        # Idle lobby with no changes = silent (no state spam).
        active_interval = 1.0 / config.STATE_ACTIVE_HZ
        idle_interval = 1.0 / config.STATE_IDLE_HZ
        while True:
            await asyncio.sleep(active_interval)
            if not self.conns:
                continue
            try:
                now = server_now()
                in_match = set(self.state.players.keys())
                # 1. match state -> only in-match sockets
                if in_match:
                    fp = self.state.fingerprint(now)
                    if fp != self._last_fingerprint:
                        self._last_fingerprint = fp
                        self._last_broadcast = now
                        snap = self.state.snapshot(now)
                        for cid in list(in_match):
                            ws = self.conns.get(cid)
                            if ws is not None:
                                try:
                                    await ws.send(make_payload("state", snap))
                                except Exception:
                                    pass
                    elif (now - self._last_broadcast) >= idle_interval:
                        self._last_broadcast = now
                        snap = self.state.snapshot(now)
                        for cid in list(in_match):
                            ws = self.conns.get(cid)
                            if ws is not None:
                                try:
                                    await ws.send(make_payload("state", snap))
                                except Exception:
                                    pass
                # 2. lobby update -> only lobby sockets, on change only (no heartbeat)
                lobby_ids = [c for c in self.lobby if c in self.conns and c not in in_match]
                if lobby_ids:
                    lfp = self._lobby_fingerprint()
                    if lfp != self._last_lobby_fp:
                        self._last_lobby_fp = lfp
                        self._last_lobby_send = now
                        snap = self._lobby_snapshot()
                        for cid in lobby_ids:
                            ws = self.conns.get(cid)
                            if ws is not None:
                                try:
                                    await ws.send(make_payload("lobby_update", snap))
                                except Exception:
                                    pass
            except Exception as exc:
                log.debug("tick broadcast failed: %s", exc)

    async def handle(self, ws) -> None:
        client_id = self._next_id
        self._next_id += 1
        self.conns[client_id] = ws
        self.lobby.add(client_id)  # lobby-first: socket tracked, NOT a match player
        peer = getattr(ws, "remote_address", "?")
        log.info("client %d connected from %s (lobby)", client_id, peer)
        # Lobby hello only. No add_player here: user must explicitly
        # join/host a room (join_room) to enter a match and get state ticks.
        await self._send(ws, "welcome", {
            "client_id": client_id,
            "server_time": server_now(),
            "message": "Welcome to Agawan lobby",
        })
        self._last_lobby_fp = None  # force lobby_update send
        try:
            async for message in ws:
                await self.on_message(client_id, ws, message)
        except Exception as exc:
            log.info("client %d handler ended: %s", client_id, exc)
        finally:
            self.conns.pop(client_id, None)
            self.lobby.discard(client_id)
            left = self.state.remove_player(client_id)
            if left is not None:
                await self._broadcast("player_left", {"client_id": client_id})
                self._last_fingerprint = None
                self._last_lobby_fp = None
            else:
                self._last_lobby_fp = None
            log.info("client %d disconnected", client_id)

    async def on_message(self, client_id: int, ws, message) -> None:
        try:
            data = json.loads(message)
        except (json.JSONDecodeError, TypeError):
            await self._send(ws, "error", {"reason": "malformed JSON"})
            return
        if not isinstance(data, dict) or "signal_name" not in data:
            await self._send(ws, "error", {"reason": "missing signal_name"})
            return
        name = str(data.get("signal_name", ""))
        raw = data.get("raw_data", {})
        if not isinstance(raw, dict):
            raw = {}
        handler = {
            "ping": self._on_ping,
            "chat_message": self._on_chat,
            "join": self._on_join,
            "exit_base": self._on_exit_base,
            "tag_attempt": self._on_tag_attempt,
        }.get(name)
        if handler is None:
            await self._send(ws, "error", {"reason": f"unknown signal '{name}'"})
            return
        await handler(client_id, ws, raw)

    async def _on_ping(self, client_id: int, ws, raw: dict) -> None:
        await self._send(ws, "pong", {
            "reply": "Pong from Python Server!",
            "client_id": client_id,
            "echo": raw.get("message", ""),
        })

    async def _on_chat(self, client_id: int, ws, raw: dict) -> None:
        player = self.state.players.get(client_id)
        sender = str(raw.get("sender") or (player.name if player else f"Client {client_id}"))
        await self._broadcast("chat_message", {
            "sender": sender,
            "message": str(raw.get("message", "")),
            "time": str(raw.get("time") or time.strftime("%H:%M:%S")),
        })

    async def _on_join(self, client_id: int, ws, raw: dict) -> None:
        # Lobby-first: socket must be in lobby; join moves it into the match.
        # Plain Direct Connect stays in lobby (no player, no state ticks).
        if client_id not in self.lobby and client_id not in self.state.players:
            await self._send(ws, "error", {"reason": "not connected"})
            return
        name = str(raw.get("name") or f"Player{client_id}")
        team = str(raw.get("team") or "red")
        role = str(raw.get("role") or "scavenger")
        existing = self.state.players.get(client_id)
        if existing is not None:
            existing.name = name
            existing.team = team if team in config.VALID_TEAMS else existing.team
            existing.role = role if role in config.VALID_ROLES else existing.role
            player = existing
        else:
            player = self.state.add_player(client_id, name=name, team=team, role=role)
        self.lobby.discard(client_id)  # entered match
        self._last_fingerprint = None  # force immediate match state
        self._last_lobby_fp = None  # force lobby_update for remaining lobby
        await self._send(ws, "welcome", {
            "client_id": client_id,
            "server_time": server_now(),
            "message": f"Welcome {player.name} [{player.team}/{player.role}]",
        })
        await self._broadcast("player_joined", {
            "client_id": client_id,
            "name": player.name,
            "team": player.team,
            "role": player.role,
        }, exclude=client_id)

    async def _on_exit_base(self, client_id: int, ws, raw: dict) -> None:
        locked = self.state.lock_exit(client_id)
        if locked is None:
            await self._send(ws, "error", {"reason": "join first"})
            return
        await self._broadcast("freshness", {
            "client_id": client_id,
            "exit_time": locked,
            "aura": "predator",
        })

    async def _on_tag_attempt(self, client_id: int, ws, raw: dict) -> None:
        try:
            target_id = int(raw.get("target_id", -1))
        except (TypeError, ValueError):
            await self._send(ws, "error", {"reason": "target_id must be int"})
            return
        result = self.state.resolve_tag(client_id, target_id)
        await self._broadcast("tag_resolved", result)


async def admin_console_loop(server: "AgawanServer") -> None:
    """Operator console (stdin). Type: say <msg> | list | kick <id> | help."""
    print("[ADMIN] type 'say <message>' to broadcast, 'list' for players, 'help' for commands", flush=True)
    while True:
        try:
            line = await asyncio.to_thread(input, "[SERVER] ")
        except (EOFError, KeyboardInterrupt):
            break
        line = line.strip()
        if not line:
            continue
        low = line.lower()
        if low == "help":
            print("commands: say <msg> | list | kick <id> | count", flush=True)
        elif low == "list" or low == "count":
            snap = server.state.snapshot()
            lobby = server._lobby_snapshot()
            print(f"[ADMIN] match: {len(snap['players'])} player(s): {snap['players']}", flush=True)
            print(f"[ADMIN] lobby: {lobby['lobby_count']} waiting: {lobby['lobby_ids']}", flush=True)
        elif low.startswith("say "):
            await server.broadcast_server_message(line[4:])
        elif low.startswith("kick "):
            try:
                tid = int(line.split()[1])
            except (IndexError, ValueError):
                print("usage: kick <client_id>", flush=True)
                continue
            ws = server.conns.get(tid)
            if ws is None:
                print(f"no client {tid}", flush=True)
            else:
                try:
                    await ws.close(1000, "kicked by operator")
                except Exception as exc:
                    print(f"kick failed: {exc}", flush=True)
        else:
            # bare line = broadcast as Server (like Godot ServerChatInput)
            await server.broadcast_server_message(line)


async def serve_forever(host: str, port: int) -> None:
    server = AgawanServer()
    asyncio.get_running_loop().create_task(server._tick_loop())
    asyncio.get_running_loop().create_task(admin_console_loop(server))
    log.info("Agawan Python server on ws://%s:%d (tick %.0f Hz)", host, port, config.TICK_HZ)
    async with websockets.serve(server.handle, host, port, max_size=1000000):
        await asyncio.Future()


def main() -> None:
    parser = argparse.ArgumentParser(description="Agawan dedicated Python server")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()
    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO,
                        format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    try:
        asyncio.run(serve_forever(args.host, args.port))
    except KeyboardInterrupt:
        log.info("shutting down")


if __name__ == "__main__":
    main()

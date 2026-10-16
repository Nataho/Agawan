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
        self._next_id = 1
        self.started_at = server_now()

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

    async def _tick_loop(self) -> None:
        interval = 1.0 / config.TICK_HZ
        while True:
            await asyncio.sleep(interval)
            if not self.conns:
                continue
            try:
                await self._broadcast("state", self.state.snapshot())
            except Exception as exc:
                log.debug("tick broadcast failed: %s", exc)

    async def handle(self, ws) -> None:
        client_id = self._next_id
        self._next_id += 1
        self.conns[client_id] = ws
        peer = getattr(ws, "remote_address", "?")
        log.info("client %d connected from %s", client_id, peer)
        try:
            async for message in ws:
                await self.on_message(client_id, ws, message)
        except Exception as exc:
            log.info("client %d handler ended: %s", client_id, exc)
        finally:
            self.conns.pop(client_id, None)
            left = self.state.remove_player(client_id)
            if left is not None:
                await self._broadcast("player_left", {"client_id": client_id})
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
        name = str(raw.get("name") or f"Player{client_id}")
        team = str(raw.get("team") or ("red" if client_id % 2 else "blue"))
        role = str(raw.get("role") or "scavenger")
        player = self.state.add_player(client_id, name=name, team=team, role=role)
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


async def serve_forever(host: str, port: int) -> None:
    server = AgawanServer()
    asyncio.get_running_loop().create_task(server._tick_loop())
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

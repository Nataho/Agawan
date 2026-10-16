"""Authoritative Agawan game state: players, freshness, tag resolution.

Protocol frames (both directions):
    {"signal_name": str, "raw_data": dict}

This module has NO I/O so it can be unit-tested without sockets.
"""
from __future__ import annotations

import time
from dataclasses import dataclass, field

from . import config


def server_now() -> float:
    """Monotonic server clock used for all exit timestamps."""
    return time.monotonic()


@dataclass
class Player:
    client_id: int
    name: str = "Player"
    team: str = "red"
    role: str = "scavenger"
    exit_time: float | None = None  # locked on exit_base, server clock
    jailed: bool = False
    connected: bool = True


@dataclass
class GameState:
    players: dict[int, Player] = field(default_factory=dict)

    # -- membership -----------------------------------------------------
    def add_player(self, client_id: int, name: str = "Player",
                   team: str = "red", role: str = "scavenger") -> Player:
        team = team if team in config.VALID_TEAMS else "red"
        role = role if role in config.VALID_ROLES else "scavenger"
        p = Player(client_id=client_id, name=name, team=team, role=role)
        self.players[client_id] = p
        return p

    def remove_player(self, client_id: int) -> Player | None:
        return self.players.pop(client_id, None)

    # -- freshness ------------------------------------------------------
    def lock_exit(self, client_id: int, now: float | None = None) -> float | None:
        """Step-off-base: lock Exit Timestamp. Clears jail (re-entered field)."""
        p = self.players.get(client_id)
        if p is None:
            return None
        now = server_now() if now is None else now
        p.exit_time = now
        p.jailed = False
        return now

    def aura(self, client_id: int, now: float | None = None) -> str:
        """predator (<15s since exit) else neutral. jailed players have no aura."""
        p = self.players.get(client_id)
        if p is None or p.jailed or p.exit_time is None:
            return "neutral"
        now = server_now() if now is None else now
        if (now - p.exit_time) > config.ANTI_STALL_DURATION_SEC:
            return "neutral"
        return "predator"

    def resolve_tag(self, attacker_id: int, target_id: int,
                    now: float | None = None) -> dict:
        """Server-authoritative Fresh Touch resolution.

        Returns dict for `tag_resolved` raw_data:
            {attacker_id, target_id, result, reason}
        result in {"tagged", "clash", "denied"}.
        """
        now = server_now() if now is None else now
        attacker = self.players.get(attacker_id)
        target = self.players.get(target_id)
        if attacker is None or target is None:
            return {"attacker_id": attacker_id, "target_id": target_id,
                    "result": "denied", "reason": "unknown player"}
        if attacker_id == target_id:
            return {"attacker_id": attacker_id, "target_id": target_id,
                    "result": "denied", "reason": "cannot tag self"}
        if attacker.team == target.team:
            return {"attacker_id": attacker_id, "target_id": target_id,
                    "result": "denied", "reason": "same team"}
        if attacker.jailed:
            return {"attacker_id": attacker_id, "target_id": target_id,
                    "result": "denied", "reason": "attacker jailed"}
        if target.jailed:
            return {"attacker_id": attacker_id, "target_id": target_id,
                    "result": "denied", "reason": "target already jailed"}
        if attacker.exit_time is None or target.exit_time is None:
            return {"attacker_id": attacker_id, "target_id": target_id,
                    "result": "denied", "reason": "both must exit base first"}
        if (now - attacker.exit_time) > config.ANTI_STALL_DURATION_SEC:
            return {"attacker_id": attacker_id, "target_id": target_id,
                    "result": "denied", "reason": "attacker aura expired"}
        if (now - target.exit_time) > config.ANTI_STALL_DURATION_SEC:
            # Target is neutral — any active attacker can take them.
            target.jailed = True
            return {"attacker_id": attacker_id, "target_id": target_id,
                    "result": "tagged", "reason": "target neutral (stale)"}

        diff = attacker.exit_time - target.exit_time
        if abs(diff) <= config.CLASH_PARITY_WINDOW_SEC:
            return {"attacker_id": attacker_id, "target_id": target_id,
                    "result": "clash", "reason": "parity knockback"}
        if diff > 0:
            # Attacker exited later = fresher = Predator.
            target.jailed = True
            return {"attacker_id": attacker_id, "target_id": target_id,
                    "result": "tagged", "reason": "predator advantage"}
        return {"attacker_id": attacker_id, "target_id": target_id,
                "result": "denied", "reason": "target is fresher (prey)"}

    # -- snapshots ------------------------------------------------------
    def snapshot(self, now: float | None = None) -> dict:
        now = server_now() if now is None else now
        players = []
        for p in self.players.values():
            players.append({
                "client_id": p.client_id,
                "name": p.name,
                "team": p.team,
                "role": p.role,
                "jailed": p.jailed,
                "exit_time": p.exit_time,
                "aura": self.aura(p.client_id, now),
            })
        return {"server_time": now, "players": players}

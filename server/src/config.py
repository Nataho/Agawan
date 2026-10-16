"""Shared Agawan match constants (Chapter 1 - Game Jam Nataho.txt).

Mirrors the design doc so Godot + Python stay in sync:
- Freshness window, anti-stall, clash parity, rescue shield.
"""
from __future__ import annotations

# Tag Combat: "Fresh Touch" Priority Engine
CLASH_PARITY_WINDOW_SEC: float = 0.25
ANTI_STALL_DURATION_SEC: float = 15.0

# Rescue
PHASE_SHIELD_DURATION_SEC: float = 2.5

# Movement reference (server does not simulate physics yet, but validates)
STAMINA_MAX: float = 100.0
STAMINA_SPRINT_DRAIN_SEC: float = 3.5
EXHAUSTION_LOCKOUT_SEC: float = 1.2
DASH_STAMINA_COST: float = 35.0
DASH_CHARGES: int = 2
DASH_COOLDOWN_SEC: float = 4.0
DASH_IFRAMES_SEC: float = 0.18
ENCUMBRANCE_SPEED_MULT: float = 0.85
ENCUMBRANCE_DRAIN_MULT: float = 1.25

# Match loop
ROUND_SECONDS_MIN: int = 120
ROUND_SECONDS_MAX: int = 180
TICK_HZ: float = 20.0

VALID_ROLES = ("scavenger", "enforcer", "anchor")
VALID_TEAMS = ("red", "blue")

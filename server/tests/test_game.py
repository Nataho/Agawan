"""Unit tests for Fresh Touch priority (Chapter 1 design doc)."""
from server.src import config
from server.src.game import GameState


def make_state() -> GameState:
    s = GameState()
    s.add_player(1, name="A", team="red", role="scavenger")
    s.add_player(2, name="B", team="blue", role="enforcer")
    return s


def test_predator_advantage_later_exit_wins():
    s = make_state()
    s.lock_exit(1, now=10.0)  # A exits at 0:10
    s.lock_exit(2, now=12.0)  # B exits at 0:12 -> fresher
    r = s.resolve_tag(2, 1, now=13.0)
    assert r["result"] == "tagged"
    assert s.players[1].jailed is True


def test_stale_attacker_cannot_tag():
    s = make_state()
    s.lock_exit(1, now=10.0)
    s.lock_exit(2, now=12.0)
    r = s.resolve_tag(1, 2, now=13.0)  # A is older -> prey
    assert r["result"] == "denied"
    assert "fresher" in r["reason"]


def test_parity_clash_within_window():
    s = make_state()
    s.lock_exit(1, now=10.0)
    s.lock_exit(2, now=10.2)  # within 0.25s
    r = s.resolve_tag(2, 1, now=11.0)
    assert r["result"] == "clash"
    assert s.players[1].jailed is False


def test_anti_stall_expiry():
    s = make_state()
    s.lock_exit(1, now=0.0)
    s.lock_exit(2, now=1.0)
    assert s.aura(1, now=5.0) == "predator"
    assert s.aura(1, now=config.ANTI_STALL_DURATION_SEC + 1.0) == "neutral"
    # Attacker 2 also went stale (exited at 1.0, now at 17.0) -> denied.
    r = s.resolve_tag(2, 1, now=config.ANTI_STALL_DURATION_SEC + 2.0)
    assert r["result"] == "denied"
    assert "expired" in r["reason"]


def test_stale_target_can_be_taken_by_fresh_attacker():
    s = make_state()
    s.lock_exit(1, now=0.0)  # target goes stale
    s.lock_exit(2, now=16.0)  # attacker fresh (within 15s at t=17)
    r = s.resolve_tag(2, 1, now=17.0)
    assert r["result"] == "tagged"
    assert "stale" in r["reason"]


def test_same_team_denied():
    s = GameState()
    s.add_player(1, team="red")
    s.add_player(3, team="red")
    s.lock_exit(1, now=10.0)
    s.lock_exit(3, now=12.0)
    r = s.resolve_tag(3, 1, now=13.0)
    assert r["result"] == "denied"

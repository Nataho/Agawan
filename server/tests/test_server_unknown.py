"""Contract tests: server must fail loud on not-yet-implemented signals.

Frontend may ship signals (e.g. attack sync) before the server has handlers.
Both terminal and client must say 'unknown signal', never stay silent.
"""
import asyncio
import json

from server.src.server import AgawanServer


class FakeWS:
    def __init__(self):
        self.sent = []

    async def send(self, msg):
        self.sent.append(json.loads(msg))


def _drain(sockets_sent):
    frames = [f for f in sockets_sent if f["signal_name"] != "state"]
    return frames


def test_unknown_signal_loud_on_both_sides():
    async def run():
        s = AgawanServer()
        ws = FakeWS()
        s.conns[1] = ws
        s.lobby.add(1)
        # Frontend example: attack sync before server implements it
        msg = json.dumps({
            "signal_name": "attack",
            "raw_data": {"attacker_id": 1, "target_id": 2, "hitbox": [0, 0, 32]},
        })
        await s.on_message(1, ws, msg)
        frames = _drain(ws.sent)
        assert len(frames) == 1, frames
        f = frames[0]
        assert f["signal_name"] == "unknown_signal", f
        assert f["raw_data"]["signal"] == "attack"
        assert f["raw_data"]["data"] == {"attacker_id": 1, "target_id": 2,
                                         "hitbox": [0, 0, 32]}
        assert "join" in f["raw_data"]["known"]  # hint lists implemented ones
        assert "attack" not in f["raw_data"]["known"]

    asyncio.run(run())


def test_known_signal_still_handled():
    async def run():
        s = AgawanServer()
        ws = FakeWS()
        s.conns[1] = ws
        s.lobby.add(1)
        msg = json.dumps({"signal_name": "ping", "raw_data": {"message": "hi"}})
        await s.on_message(1, ws, msg)
        frames = _drain(ws.sent)
        assert frames[0]["signal_name"] == "pong", frames

    asyncio.run(run())


def test_malformed_json_still_error():
    async def run():
        s = AgawanServer()
        ws = FakeWS()
        await s.on_message(1, ws, "not-json{")
        assert ws.sent[0]["signal_name"] == "error"
        assert "malformed" in ws.sent[0]["raw_data"]["reason"]

    asyncio.run(run())

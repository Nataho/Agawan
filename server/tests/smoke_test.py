"""Live smoke test: boots the real server, talks Godot-shaped JSON.

Run: server/.venv/bin/python -m server.tests.smoke_test
"""
import asyncio
import json
import sys

sys.path.insert(0, ".")

import websockets

from server.src.server import serve_forever


async def recv_signal(ws, want: str | None = None):
    """Read frames until the wanted signal arrives (skips 20Hz state ticks)."""
    for _ in range(50):
        data = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
        assert "signal_name" in data and "raw_data" in data, f"bad frame: {data}"
        if want is None or data["signal_name"] == want:
            return data
    raise AssertionError(f"never got '{want}'")


async def main():
    task = asyncio.create_task(serve_forever("127.0.0.1", 18080))
    await asyncio.sleep(0.5)
    try:
        async with websockets.connect("ws://127.0.0.1:18080") as ws:
            # 1. ping/pong (same as NetworkTest.gd Send Ping)
            await ws.send(json.dumps({"signal_name": "ping",
                                      "raw_data": {"message": "Hello"}}))
            pong = await recv_signal(ws, "pong")
            assert pong["signal_name"] == "pong", pong
            print("OK ping->pong:", pong["raw_data"])

            # 2. join/welcome
            await ws.send(json.dumps({"signal_name": "join",
                                      "raw_data": {"name": "Nataho",
                                                   "team": "red",
                                                   "role": "scavenger"}}))
            welcome = await recv_signal(ws, "welcome")
            assert welcome["signal_name"] == "welcome", welcome
            cid = welcome["raw_data"]["client_id"]
            print("OK join->welcome:", welcome["raw_data"])

            # 3. exit_base/freshness + tag flow needs 2 clients
            async with websockets.connect("ws://127.0.0.1:18080") as ws2:
                await ws2.send(json.dumps({"signal_name": "join",
                                           "raw_data": {"name": "Enemy",
                                                        "team": "blue"}}))
                w2 = await recv_signal(ws2, "welcome")
                cid2 = w2["raw_data"]["client_id"]
                # drain player_joined broadcast on ws
                joined = await recv_signal(ws, "player_joined")
                assert joined["signal_name"] == "player_joined", joined

                await ws.send(json.dumps({"signal_name": "exit_base",
                                          "raw_data": {}}))
                fresh1 = await recv_signal(ws, "freshness")
                assert fresh1["signal_name"] == "freshness", fresh1
                _ = await recv_signal(ws2, "freshness")  # broadcast copy

                await asyncio.sleep(0.3)  # ensure later exit, avoid clash
                await ws2.send(json.dumps({"signal_name": "exit_base",
                                           "raw_data": {}}))
                _ = await recv_signal(ws2, "freshness")
                _ = await recv_signal(ws, "freshness")

                await ws2.send(json.dumps({"signal_name": "tag_attempt",
                                           "raw_data": {"target_id": cid}}))
                resolved = await recv_signal(ws2, "tag_resolved")
                assert resolved["signal_name"] == "tag_resolved", resolved
                assert resolved["raw_data"]["result"] == "tagged", resolved
                print("OK tag flow:", resolved["raw_data"])
        print("SMOKE PASS")
    finally:
        task.cancel()


if __name__ == "__main__":
    asyncio.run(main())

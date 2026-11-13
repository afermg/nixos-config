#!/usr/bin/env python3
"""Smoke-test a built atuin-mcp launcher without accessing real user history.

Usage: python tests/atuin-mcp.py /nix/store/...-atuin-mcp/bin/atuin-mcp
"""

import json
import os
from pathlib import Path
import selectors
import subprocess
import sys
import tempfile


def main():
    launcher = Path(sys.argv[1]).absolute()
    with tempfile.TemporaryDirectory(prefix="atuin-mcp-test-") as directory:
        home = Path(directory)
        config = home / "config" / "atuin"
        config.mkdir(parents=True)
        (config / "config.toml").write_text(
            "auto_sync = false\n[threads]\ncapture = false\ncapture_tools = false\n"
        )
        env = {key: value for key, value in os.environ.items() if not key.startswith("ATUIN_")}
        env.update(
            HOME=str(home),
            XDG_CONFIG_HOME=str(home / "config"),
            XDG_DATA_HOME=str(home / "data"),
            XDG_STATE_HOME=str(home / "state"),
            XDG_CACHE_HOME=str(home / "cache"),
            XDG_RUNTIME_DIR=str(home / "run"),
            ATUIN_CONFIG_DIR=str(config),
        )
        (home / "run").mkdir(mode=0o700)
        with subprocess.Popen(
            [str(launcher)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, env=env,
            text=True, bufsize=1,
        ) as process:
            try:
                with selectors.DefaultSelector() as selector:
                    selector.register(process.stdout, selectors.EVENT_READ)

                    def send(message):
                        process.stdin.write(json.dumps({"jsonrpc": "2.0", **message}) + "\n")
                        process.stdin.flush()

                    def receive(request_id):
                        # Each request here produces one response, without concurrent work.
                        if not selector.select(timeout=15):
                            raise AssertionError("MCP response timed out")
                        line = process.stdout.readline()
                        assert line, "MCP server exited before responding"
                        response = json.loads(line)
                        assert response.get("id") == request_id, response
                        assert "error" not in response, response
                        return response["result"]

                    send({"id": 1, "method": "initialize", "params": {
                        "protocolVersion": "2024-11-05", "capabilities": {},
                        "clientInfo": {"name": "nixos-config-test", "version": "1"},
                    }})
                    info = receive(1)
                    assert info["serverInfo"]["name"] == "atuin", info
                    send({"method": "notifications/initialized"})
                    send({"id": 2, "method": "tools/list", "params": {}})
                    tools = {tool["name"] for tool in receive(2)["tools"]}
                    expected = {"atuin_threads_list", "atuin_threads_search", "atuin_threads_read"}
                    assert expected <= tools, tools
                    print(json.dumps({"server": info["serverInfo"], "threadTools": sorted(expected)}))
            finally:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


if __name__ == "__main__":
    main()

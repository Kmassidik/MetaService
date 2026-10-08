#!/usr/bin/env python3
"""A stand-in for Apple's `container` program, strict about flags (an unknown flag is an error, like a real tool).
State lives in the JSON file $FAKE_CONTAINER_STATE; every call is logged to $FAKE_CONTAINER_LOG.
Failure switches (env): FAKE_CONTAINER_FAIL=<subcommand>, FAKE_CONTAINER_EMPTY_EXPORT=1, FAKE_CONTAINER_SYSTEM_STUCK=1."""
import fcntl
import json
import os
import sys

STATE = os.environ["FAKE_CONTAINER_STATE"]
args = sys.argv[1:]
with open(os.environ["FAKE_CONTAINER_LOG"], "a") as log:
    log.write(json.dumps(args) + "\n")


# One call at a time, like the real tool's single API server: the Agent runs several calls at once.
LOCK = open(STATE + ".lock", "w")
fcntl.flock(LOCK, fcntl.LOCK_EX)


def load():
    if not os.path.exists(STATE):
        return {"system": "stopped", "images": [], "containers": {}, "next_ip": 10}
    return json.load(open(STATE))


def save(state):
    temporary = STATE + ".tmp"
    json.dump(state, open(temporary, "w"))
    os.replace(temporary, STATE)


def die(message, code=1):
    print(message, file=sys.stderr)
    sys.exit(code)


def take_flags(rest, with_value, bare):
    """Split flags from positional words. Only the listed flags are allowed."""
    values, positional, i = {}, [], 0
    while i < len(rest):
        word = rest[i]
        if word in with_value:
            values.setdefault(word, []).append(rest[i + 1])
            i += 2
        elif word in bare:
            values[word] = [True]
            i += 1
        elif word.startswith("-"):
            die(f"unknown option {word}", 2)
        else:
            positional = rest[i:]
            break
    return values, positional


if os.environ.get("FAKE_CONTAINER_FAIL") == " ".join(args[:2]) or os.environ.get("FAKE_CONTAINER_FAIL") == args[0]:
    die("injected failure")

import time
if args[0] == "run":
    time.sleep(float(os.environ.get("FAKE_CONTAINER_RUN_DELAY", "0")))
state = load()
command = args[0]
if command == "system":
    if args[1] == "status":
        print(f"status      {state['system']}")
    elif args[1] == "start":
        if not os.environ.get("FAKE_CONTAINER_SYSTEM_STUCK"):
            state["system"] = "running"
    else:
        die("unknown system command", 2)
elif command == "image":
    if args[1] == "inspect":
        sys.exit(0 if args[2] in state["images"] else 1)
    if args[1] == "pull":
        state["images"].append(args[2])
    else:
        die("unknown image command", 2)
elif command == "run":
    values, positional = take_flags(args[1:], {"--name", "--cpus", "--memory", "--label"}, {"--detach"})
    if state["system"] != "running":
        die("the container system is not running")
    name = values["--name"][0]
    if name in state["containers"]:
        die("name in use")
    if positional[0] not in state["images"]:
        die("image not found")
    state["next_ip"] += 1
    state["containers"][name] = {"state": "running", "ip": f"192.168.65.{state['next_ip']}", "cpus": values["--cpus"][0], "memory": values["--memory"][0],
                                 "labels": values.get("--label", []), "image": positional[0], "cmd": positional[1:]}
elif command in ("start", "stop"):
    flags = {"--signal", "--time"} if command == "stop" else set()
    values, positional = take_flags(args[1:], flags, set())
    if positional[0] not in state["containers"]:
        die("no such container")
    state["containers"][positional[0]]["state"] = "running" if command == "start" else "stopped"
elif command == "delete":
    values, positional = take_flags(args[1:], set(), {"--force"})
    if positional[0] not in state["containers"]:
        die("no such container")
    del state["containers"][positional[0]]
elif command in ("list", "inspect"):
    if command == "list":
        take_flags(args[1:], {"--format"}, {"--all"})
        names = list(state["containers"])
    else:
        names = args[1:]
        if any(n not in state["containers"] for n in names):
            die("no such container")
    out = [{"id": n, "status": {"state": state["containers"][n]["state"], "networks": ([{"ipv4Address": state["containers"][n]["ip"] + "/24"}] if state["containers"][n]["state"] == "running" else [])}} for n in names]
    print(json.dumps(out))
elif command == "export":
    values, positional = take_flags(args[1:], {"--output"}, set())
    if positional[0] not in state["containers"]:
        die("no such container")
    with open(values["--output"][0], "wb") as out:
        if not os.environ.get("FAKE_CONTAINER_EMPTY_EXPORT"):
            out.write(b"fake filesystem tar for " + positional[0].encode())
else:
    die(f"unknown command {command}", 2)
save(state)

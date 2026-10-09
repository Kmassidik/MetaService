#!/usr/bin/env python3
"""A stand-in for the `incus` program, strict about flags (an unknown flag is an error, like a real tool).
State lives in the JSON file $FAKE_INCUS_STATE; every call is logged to $FAKE_INCUS_LOG.
Failure switches (env): FAKE_INCUS_FAIL=<subcommand>, FAKE_INCUS_EMPTY_EXPORT=1, FAKE_INCUS_RUN_DELAY=<seconds>."""
import fcntl
import json
import os
import sys
import time

STATE = os.environ["FAKE_INCUS_STATE"]
args = sys.argv[1:]
with open(os.environ["FAKE_INCUS_LOG"], "a") as log:
    log.write(json.dumps(args) + "\n")
LOCK = open(STATE + ".lock", "w")
fcntl.flock(LOCK, fcntl.LOCK_EX)


def load():
    return json.load(open(STATE)) if os.path.exists(STATE) else {"instances": {}, "next_ip": 10}


def save(state):
    temporary = STATE + ".tmp"
    json.dump(state, open(temporary, "w"))
    os.replace(temporary, STATE)


def die(message, code=1):
    print(message, file=sys.stderr)
    sys.exit(code)


def flags(rest, with_value, bare=()):
    values, positional, i = {}, [], 0
    while i < len(rest):
        word = rest[i]
        if word == "--":
            positional += rest[i + 1:]
            break
        if word in with_value:
            values.setdefault(word, []).append(rest[i + 1])
            i += 2
        elif word in bare:
            values[word] = [True]
            i += 1
        elif word.startswith("-") and len(word) > 1 and not word[1:].isdigit():
            die(f"unknown option {word}", 2)
        else:
            positional.append(word)
            i += 1
    return values, positional


if os.environ.get("FAKE_INCUS_FAIL") in (args[0], " ".join(args[:2])):
    die("injected failure")

state = load()
command = args[0]
if command == "list":
    flags(args[1:], {"--format"})
    out = []
    for name, item in state["instances"].items():
        running = item["status"] == "Running"
        network = {"eth0": {"addresses": [{"family": "inet", "address": item["ip"], "scope": "global"}]}} if running else {}
        out.append({"name": name, "status": item["status"], "type": item["type"], "config": item["config"], "state": {"network": network} if running else None})
    print(json.dumps(out))
elif command == "launch":
    time.sleep(float(os.environ.get("FAKE_INCUS_RUN_DELAY", "0")))
    values, positional = flags(args[1:], {"-c", "-d"}, {"--vm"})
    image, name = positional
    if name in state["instances"]:
        die("instance already exists")
    config = dict(item.split("=", 1) for item in values.get("-c", []))
    for device in values.get("-d", []):
        if not (device.startswith("root,size=") or device == "gpu0,type=gpu"):
            die(f"unexpected device {device}", 2)
    state["next_ip"] += 1
    state["instances"][name] = {"status": "Running", "type": "virtual-machine" if "--vm" in values else "container", "config": config, "ip": f"10.77.0.{state['next_ip']}", "image": image}
elif command in ("start", "stop"):
    values, positional = flags(args[1:], {"--timeout"} if command == "stop" else set())
    if positional[0] not in state["instances"]:
        die("instance not found")
    state["instances"][positional[0]]["status"] = "Running" if command == "start" else "Stopped"
elif command == "delete":
    values, positional = flags(args[1:], set(), {"--force"})
    if positional[0] not in state["instances"]:
        die("instance not found")
    del state["instances"][positional[0]]
elif command == "export":
    values, positional = flags(args[1:], set())
    name, path = positional
    if name not in state["instances"]:
        die("instance not found")
    with open(path, "wb") as out:
        if not os.environ.get("FAKE_INCUS_EMPTY_EXPORT"):
            out.write(b"fake backup of " + name.encode())
elif command == "config":
    sub, name, key, value = args[1:5]
    if sub != "set" or name not in state["instances"]:
        die("bad config command", 2)
    state["instances"][name]["config"][key] = value
elif command == "file":
    values, positional = flags(args[1:], set())
    if positional[0] != "push":
        die("only file push is supported here", 2)
    target = positional[2].split("/", 1)[0]
    if target not in state["instances"] or state["instances"][target]["status"] != "Running":
        die("instance not running")
    state["instances"][target].setdefault("files", []).append(positional[2])
elif command == "exec":
    values, positional = flags(args[1:], {"--env"})
    name = positional[0]
    if name not in state["instances"] or state["instances"][name]["status"] != "Running":
        die("instance not running")
    state["instances"][name].setdefault("ran", []).append({"env": values.get("--env", []), "argv": positional[1:]})
    if os.environ.get("FAKE_INCUS_FAIL_EXEC"):
        die("injected exec failure")
else:
    die(f"unknown command {command}", 2)
save(state)

#!/usr/bin/env python3
"""A stand-in for Apple's `container` program, strict about flags (an unknown flag is an error, like a real tool).
State lives in the JSON file $FAKE_CONTAINER_STATE; every call is logged to $FAKE_CONTAINER_LOG.
Failure switches (env): FAKE_CONTAINER_FAIL=<subcommand>, FAKE_CONTAINER_EMPTY_EXPORT=1, FAKE_CONTAINER_SYSTEM_STUCK=1.
How a new container behaves (env FAKE_CONTAINER_BOOT): ok (default), systemd-dies (the systemd script's container quits at once, like the real Mac Studio did),
systemd-needs-caps (it quits unless NET_ADMIN and SYS_ADMIN were added), both-die, late-exit (quits 2 seconds after it started), never-answers (stays up, the start file is never there)."""
import fcntl
import json
import os
import sys
import time

ESC = "\x1b"
INIT_MODE_FILE = "/metaservice-init-mode"

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
    state = json.load(open(STATE))
    for box in state["containers"].values():
        if box["state"] == "running" and box.get("exit_at") and time.time() >= box["exit_at"]:
            box.update(state="stopped", exit_code=1, log="Segmentation fault", exit_at=None)
    return state


def systemd_boot_log(name):
    """What the real Mac Studio printed when systemd could not mount /run (colours included)."""
    return "\n".join([
        f"vminitd: id: {name}, pid: 71 started managed process",
        "vminitd: memory threshold exceeded: 93%",
        'Failed to mount tmpfs (type tmpfs) on /run (MS_NOSUID|MS_NODEV|MS_STRICTATIME "mode=0755,size=20%,nr_inodes=800k"): Operation not permitted',
        'Failed to mount tmpfs (type tmpfs) on /run/lock (MS_NOSUID|MS_NODEV|MS_NOEXEC "mode=1777,size=5242880"): Operation not permitted',
        f"[{ESC}[0;1;31m!!!!!!{ESC}[0m] Failed to mount API filesystems.",
        "Exiting PID 1...",
        f"vminitd: id: {name}, status: 255 managed process exit",
    ]) + "\n"


def new_container(name, values, positional, ip):
    """A container as it would come up. The script it was given says whether it is the systemd one or the plain one."""
    script = positional[3]
    systemd = "exec /sbin/init" in script
    caps = values.get("--cap-add", [])
    boot = os.environ.get("FAKE_CONTAINER_BOOT", "ok")
    quits = (boot == "both-die" or (systemd and boot == "systemd-dies")
             or (systemd and boot == "systemd-needs-caps" and not {"NET_ADMIN", "SYS_ADMIN"} <= set(caps)))
    box = {"state": "running", "ip": ip, "cpus": values["--cpus"][0], "memory": values["--memory"][0], "labels": values.get("--label", []),
           "image": positional[0], "cmd": positional[1:], "caps": caps, "init_mode": "systemd" if systemd else "plain",
           "answers": boot != "never-answers", "log": "", "boot_log": "", "exit_code": None, "exit_at": None}
    if boot == "late-exit":
        box["exit_at"] = time.time() + 2
    if quits:
        box.update(state="stopped", exit_code=255, boot_log=systemd_boot_log(name) if systemd else f"vminitd: id: {name}, status: 255 managed process exit\n")
        box["log"] = "" if systemd else "sleep: cannot execute\n"
    return box


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

if args == ["--version"]:
    print(f"container CLI version {os.environ.get('FAKE_CONTAINER_VERSION', '1.5.0')} (build: release, commit: 0000000)")
    sys.exit(0)

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
    values, positional = take_flags(args[1:], {"--name", "--cpus", "--memory", "--label", "--cap-add"}, {"--detach"})
    if state["system"] != "running":
        die("the container system is not running")
    name = values["--name"][0]
    if name in state["containers"]:
        die("name in use")
    if positional[0] not in state["images"]:
        die("image not found")
    state["next_ip"] += 1
    state["containers"][name] = new_container(name, values, positional, f"192.168.65.{state['next_ip']}")
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
    out = [{"id": n, "status": {"state": state["containers"][n]["state"], "networks": ([{"ipv4Address": state["containers"][n]["ip"] + "/24"}] if state["containers"][n]["state"] == "running" else []),
                               **({"exitCode": state["containers"][n]["exit_code"]} if state["containers"][n].get("exit_code") is not None else {})}} for n in names]
    print(json.dumps(out))
elif command == "logs":
    values, positional = take_flags(args[1:], set(), {"--boot"})
    if positional[0] not in state["containers"]:
        die("no such container")
    print(state["containers"][positional[0]].get("boot_log" if "--boot" in values else "log", ""), end="")
elif command == "cp":
    if len(args) != 3 or ":" not in args[2] or args[2].split(":", 1)[0] not in state["containers"]:
        die("cp needs a host path and container:path of a known container", 2)
    if state["containers"][args[2].split(":", 1)[0]]["state"] != "running":
        die("the container must be running")
    state["containers"][args[2].split(":", 1)[0]].setdefault("files", []).append(args[2].split(":", 1)[1])
elif command == "exec":
    values, positional = take_flags(args[1:], {"-e"}, set())
    if positional[0] not in state["containers"] or state["containers"][positional[0]]["state"] != "running":
        die("no such running container")
    state["containers"][positional[0]].setdefault("ran", []).append({"env": values.get("-e", []), "argv": positional[1:]})
    if positional[1:] == ["cat", INIT_MODE_FILE]:
        if not state["containers"][positional[0]].get("answers", True):
            die("cat: no such file", 1)
        print(state["containers"][positional[0]].get("init_mode", "systemd"))
    if os.environ.get("FAKE_CONTAINER_FAIL_EXEC"):
        die("injected exec failure")
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

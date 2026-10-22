"""The GPUs of the Fake Agent's GET /v1/stats. A machine spec is a list of kinds, one GPU each:
`nvidia` (everything, with programs), `amd` (everything the driver shows, no programs), `intel` (name and clock only, the rest null),
`apple` (use and memory only, the computer's own memory as the total), `hostile` (markup in text and numbers outside every limit),
`many` (twelve cards in one entry: more than the contract allows), `silent` (a card that gives no number at all)."""
import math

GIB = 1024 ** 3
MIB = 1024 ** 2

KIND_NVIDIA = "nvidia"
KIND_AMD = "amd"
KIND_INTEL = "intel"
KIND_APPLE = "apple"
KIND_HOSTILE = "hostile"
KIND_MANY = "many"
KIND_SILENT = "silent"
GPU_KINDS = (KIND_NVIDIA, KIND_AMD, KIND_INTEL, KIND_APPLE, KIND_HOSTILE, KIND_MANY, KIND_SILENT)

HOSTILE_GPU_NAME = "<img src=x onerror=alert(1)> GPU"
HOSTILE_VENDOR = "<script>alert(3)</script>"
HOSTILE_PROGRAM = "<b>miner</b>" + "x" * 100
MANY_COUNT = 12
PROGRAMS_SENT = 12
APPLE_MEMORY_TOTAL = 36 * GIB


def wave(tick, phase, low, high):
    return round(low + (high - low) * (0.5 + 0.5 * math.sin(tick * 0.7 + phase)), 1)


def programs(tick):
    return [{"name": f"python{n}", "memory_bytes": (6 - n) * GIB + tick * MIB} for n in range(3)]


def nvidia(tick, phase):
    return {
        "name": "NVIDIA GeForce RTX 5090", "vendor": "nvidia", "utilization_percent": wave(tick, phase, 5, 95), "memory_used_bytes": (4 + tick % 5) * GIB,
        "memory_total_bytes": 32 * GIB, "temperature_celsius": wave(tick, phase, 45, 78), "power_watts": wave(tick, phase, 60, 480), "power_limit_watts": 575.0,
        "fan_percent": wave(tick, phase, 30, 70), "clock_mhz": wave(tick, phase, 600, 2400), "processes": programs(tick),
    }


def amd(tick, phase):
    return {
        "name": "AMD Radeon RX 7900 XTX", "vendor": "amd", "utilization_percent": wave(tick, phase, 2, 80), "memory_used_bytes": (2 + tick % 4) * GIB,
        "memory_total_bytes": 24 * GIB, "temperature_celsius": wave(tick, phase, 40, 70), "power_watts": wave(tick, phase, 30, 300), "power_limit_watts": 327.0,
        "fan_percent": wave(tick, phase, 20, 60), "clock_mhz": wave(tick, phase, 500, 2400),
    }


def intel(tick, phase):
    return {
        "name": "Intel graphics (i915)", "vendor": "intel", "utilization_percent": None, "memory_used_bytes": None, "memory_total_bytes": None,
        "temperature_celsius": None, "clock_mhz": wave(tick, phase, 300, 1100),
    }


def apple(tick, phase):
    return {
        "name": "Apple M3 Max GPU", "vendor": "apple", "utilization_percent": wave(tick, phase, 1, 60), "memory_used_bytes": (1 + tick % 6) * GIB,
        "memory_total_bytes": APPLE_MEMORY_TOTAL, "temperature_celsius": None,
    }


def silent(tick, phase):
    return {"name": "Silent GPU", "vendor": "unknown", "utilization_percent": None, "memory_used_bytes": None, "memory_total_bytes": None, "temperature_celsius": None}


def hostile(tick, phase):
    """Every number outside its limit and every text a trap: the parent keeps text as text and drops the numbers."""
    return {
        "name": HOSTILE_GPU_NAME + "y" * 100, "vendor": HOSTILE_VENDOR, "utilization_percent": 140.0, "memory_used_bytes": -5, "memory_total_bytes": 2 ** 60,
        "temperature_celsius": 900.0, "power_watts": 5000.0, "power_limit_watts": -3.0, "fan_percent": 130.0, "clock_mhz": 99999.0,
        "processes": [{"name": HOSTILE_PROGRAM, "memory_bytes": n * MIB} for n in range(1, PROGRAMS_SENT + 1)] + [{"name": "bad", "memory_bytes": -1}],
    }


BUILDERS = {KIND_NVIDIA: nvidia, KIND_AMD: amd, KIND_INTEL: intel, KIND_APPLE: apple, KIND_HOSTILE: hostile, KIND_SILENT: silent}


def readings(kinds, tick):
    """The `gpus` list for these kinds at this tick. Empty when the machine has none."""
    gpus = []
    for kind in kinds:
        if kind == KIND_MANY:
            gpus.extend(nvidia(tick, index) for index in range(MANY_COUNT))
            continue
        gpus.append(BUILDERS[kind](tick, len(gpus)))
    return gpus

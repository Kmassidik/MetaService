"""The optional numbers of the Fake Agent's GET /v1/stats (cores and threads, CPU breakdown, disk speed, network errors, frequency, temperature).
Three kinds of machine: `full` is a Linux machine that gives everything, `mac` is a Mac (no frequency or temperature, four CPU states, clusters, no drops on the way out),
`none` is an older helper that sends none of them."""
import math

EXTRAS_FULL = "full"
EXTRAS_MAC = "mac"
EXTRAS_NONE = "none"
EXTRAS_KINDS = (EXTRAS_FULL, EXTRAS_MAC, EXTRAS_NONE)

MEGABYTE = 1024 * 1024
BASE_FREQUENCY_MHZ = 3400.0
BOOST_FREQUENCY_MHZ = 4900.0
IDLE_TEMPERATURE_CELSIUS = 42.0
HOT_TEMPERATURE_CELSIUS = 78.0
PROCESS_COUNT_BASE = 380


def one_decimal(value):
    return round(value, 1)


def wave(tick, phase=0.0, low=0.0, high=1.0):
    return low + (high - low) * (0.5 + 0.5 * math.sin(tick * 0.9 + phase))


class Extras:
    """Builds the optional parts. `logical` CPUs, `physical` cores; `kind` is one of EXTRAS_KINDS."""

    def __init__(self, kind, logical, physical):
        self.kind, self.logical, self.physical = kind, logical, min(physical, logical)

    @property
    def sends(self):
        return self.kind != EXTRAS_NONE

    def cpu(self, tick, measuring, total_percent):
        """Added to the `cpu` object."""
        if not self.sends:
            return {}
        parts = {"physical_cores": self.physical, "core_of": self._core_of()}
        clusters = self._clusters()
        if clusters:
            parts["clusters"] = clusters
        if self.kind == EXTRAS_FULL:
            parts["breakdown"] = None if measuring else self._linux_breakdown(total_percent)
            parts["frequency_mhz"] = self._frequency(tick)
            parts["temperature_celsius"] = one_decimal(wave(tick, 1.0, IDLE_TEMPERATURE_CELSIUS, HOT_TEMPERATURE_CELSIUS))
        elif not measuring:
            parts["breakdown"] = self._mac_breakdown(total_percent)
        return parts

    def top(self, tick, measuring):
        """Added at the top of the answer."""
        if not self.sends:
            return {}
        parts = {"process_count": PROCESS_COUNT_BASE + tick % 7}
        if not measuring:
            parts["disk_io"] = {"read_bytes_per_second": one_decimal(wave(tick, 2.0, 0.2, 80) * MEGABYTE), "write_bytes_per_second": one_decimal(wave(tick, 4.0, 0.1, 30) * MEGABYTE)}
        return parts

    def network(self, tick):
        """Added to the `network` object: running totals."""
        if not self.sends:
            return {}
        counts = {"errors_in_total": tick // 5, "errors_out_total": tick // 9, "drops_in_total": tick // 3}
        if self.kind == EXTRAS_FULL:
            counts["drops_out_total"] = tick // 7
        return counts

    def threads(self, index):
        """Added to one process, or nothing."""
        return {"threads": 1 + index * 3} if self.sends else {}

    def _core_of(self):
        """Like Linux: the second thread of core 0 is the CPU after the last core, so siblings are far apart in the list."""
        return [cpu % self.physical for cpu in range(self.logical)]

    def _clusters(self):
        if self.kind != EXTRAS_MAC or self.physical != self.logical or self.logical < 2:
            return []
        performance = max(1, self.logical // 2)
        return [{"name": "Performance", "logical": performance}, {"name": "Efficiency", "logical": self.logical - performance}]

    def _frequency(self, tick):
        speed = wave(tick, 0.5, BASE_FREQUENCY_MHZ, BOOST_FREQUENCY_MHZ)
        return {"average": one_decimal(speed), "max": one_decimal(min(BOOST_FREQUENCY_MHZ, speed + 300))}

    def _linux_breakdown(self, total_percent):
        busy = total_percent
        system, iowait, irq, softirq, steal, nice = (one_decimal(busy * share) for share in (0.25, 0.08, 0.02, 0.03, 0.01, 0.02))
        user = one_decimal(max(0.0, busy - system - iowait - irq - softirq - steal - nice))
        return {"user": user, "nice": nice, "system": system, "idle": one_decimal(max(0.0, 100.0 - busy)), "iowait": iowait, "irq": irq, "softirq": softirq, "steal": steal}

    def _mac_breakdown(self, total_percent):
        system = one_decimal(total_percent * 0.3)
        nice = one_decimal(total_percent * 0.02)
        return {"user": one_decimal(max(0.0, total_percent - system - nice)), "system": system, "nice": nice, "idle": one_decimal(max(0.0, 100.0 - total_percent))}

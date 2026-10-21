//! Memory from /proc/meminfo (kB in the file, bytes out).
use super::model::Memory;
use std::collections::HashMap;

const BYTES_PER_KB: u64 = 1024;

pub fn parse(text: &str) -> Option<Memory> {
    let kb: HashMap<&str, u64> = text.lines().filter_map(|line| {
        let (key, rest) = line.split_once(':')?;
        Some((key, rest.split_whitespace().next()?.parse().ok()?))
    }).collect();
    let bytes = |key: &str| kb.get(key).copied().unwrap_or(0) * BYTES_PER_KB;
    let total = *kb.get("MemTotal")? * BYTES_PER_KB;
    let free = bytes("MemFree").min(total);
    let cached = (bytes("Buffers") + bytes("Cached") + bytes("SReclaimable")).min(total - free);
    let swap_total = bytes("SwapTotal");
    Some(Memory {
        total_bytes: total,
        used_bytes: total - free - cached,
        cached_bytes: cached,
        free_bytes: free,
        swap_total_bytes: swap_total,
        swap_used_bytes: swap_total.saturating_sub(bytes("SwapFree")),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const MEMINFO: &str = "MemTotal:       1000 kB\nMemFree:         100 kB\nBuffers:          50 kB\nCached:          250 kB\nSReclaimable:    100 kB\nSwapTotal:       200 kB\nSwapFree:        150 kB\n";

    #[test]
    fn used_cached_and_free_add_up_to_total() {
        let memory = parse(MEMINFO).unwrap();
        assert_eq!((memory.total_bytes, memory.free_bytes, memory.cached_bytes, memory.used_bytes), (1000 * 1024, 100 * 1024, 400 * 1024, 500 * 1024));
        assert_eq!(memory.used_bytes + memory.cached_bytes + memory.free_bytes, memory.total_bytes);
        assert_eq!((memory.swap_total_bytes, memory.swap_used_bytes), (200 * 1024, 50 * 1024));
    }

    #[test]
    fn cached_never_passes_what_is_left() {
        let memory = parse("MemTotal: 100 kB\nMemFree: 90 kB\nCached: 500 kB\n").unwrap();
        assert_eq!(memory.used_bytes + memory.cached_bytes + memory.free_bytes, memory.total_bytes);
    }

    #[test]
    fn no_total_means_no_answer() {
        assert!(parse("MemFree: 1 kB\n").is_none());
    }
}

//! NVIDIA GPUs through `nvidia-smi`, with fixed argument lists, no shell and a short time limit.
//! No program or no answer means no NVIDIA readings. The program list is a second call whose failure only means no list.
use super::VENDOR_NVIDIA;
use crate::stats::model::{cut, one_decimal, GpuProgram, GpuStats, MAX_GPUS, MAX_GPU_PROGRAMS, MAX_NAME_CHARS};
use std::collections::HashMap;
use std::io::Read;
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

pub const QUERY_TIMEOUT: Duration = Duration::from_secs(3);
/// The identifier is last: it only ties a program to its card and never leaves this file.
const CARD_ARGUMENTS: [&str; 2] = [
    "--query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw,power.limit,fan.speed,clocks.sm,uuid",
    "--format=csv,noheader,nounits",
];
const PROGRAM_ARGUMENTS: [&str; 2] = ["--query-compute-apps=gpu_uuid,process_name,used_memory", "--format=csv,noheader,nounits"];
/// The same program list with the process id, for the memory watchdog (it ties a program to its container by the id).
const PID_PROGRAM_ARGUMENTS: [&str; 2] = ["--query-compute-apps=gpu_uuid,pid,process_name,used_memory", "--format=csv,noheader,nounits"];
const PID_PROGRAM_FIELDS: usize = 4;
const CARD_FIELDS: usize = 10;
const PROGRAM_FIELDS: usize = 3;
const BYTES_PER_MIB: u64 = 1024 * 1024;
const POLL: Duration = Duration::from_millis(20);
const MAX_WATTS: f64 = 2000.0;
const MAX_MHZ: f64 = 20000.0;
const MAX_PERCENT: f64 = 100.0;
/// Outside this range a temperature is a broken sensor (0 means "no value").
const MIN_CELSIUS: f64 = 1.0;
const MAX_CELSIUS: f64 = 150.0;
/// A fresh program file can briefly be "busy" while another thread forks; asking again a moment later works.
const BUSY_RETRIES: u32 = 100;
const BUSY_WAIT: Duration = Duration::from_millis(10);

/// A card with the identifier its programs are listed under.
#[derive(Debug, PartialEq)]
pub struct Card {
    pub gpu: GpuStats,
    pub uuid: String,
}

/// None when the program does not run, fails, is too slow, or says nothing we can read.
pub fn query(program: &str, timeout: Duration) -> Option<Vec<GpuStats>> {
    let started = Instant::now();
    let text = run(program, &CARD_ARGUMENTS, timeout)?;
    let cards = parse(&text);
    if cards.is_empty() {
        return None;
    }
    let programs = run(program, &PROGRAM_ARGUMENTS, timeout.saturating_sub(started.elapsed())).map(|text| parse_programs(&text));
    Some(attach_programs(cards, programs))
}

fn attach_programs(cards: Vec<Card>, programs: Option<HashMap<String, Vec<GpuProgram>>>) -> Vec<GpuStats> {
    let Some(mut by_card) = programs else { return cards.into_iter().map(|card| card.gpu).collect() };
    cards.into_iter().map(|card| GpuStats { processes: Some(by_card.remove(&card.uuid).unwrap_or_default()), ..card.gpu }).collect()
}

fn spawn(program: &str, arguments: &[&str]) -> Option<Child> {
    for _ in 0..BUSY_RETRIES {
        match Command::new(program).args(arguments).stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn() {
            Ok(child) => return Some(child),
            Err(error) if error.raw_os_error() == Some(libc::ETXTBSY) => std::thread::sleep(BUSY_WAIT),
            Err(_) => return None,
        }
    }
    None
}

/// The program's output when it ends well inside the time limit.
fn run(program: &str, arguments: &[&str], timeout: Duration) -> Option<String> {
    let mut child = spawn(program, arguments)?;
    let deadline = Instant::now() + timeout;
    let status = loop {
        if let Some(status) = child.try_wait().ok()? {
            break status;
        }
        if Instant::now() >= deadline {
            let _ = child.kill();
            let _ = child.wait();
            return None;
        }
        std::thread::sleep(POLL);
    };
    let mut text = String::new();
    child.stdout.take()?.read_to_string(&mut text).ok()?;
    status.success().then_some(text)
}

/// A program on a card: its process id and the memory it holds in MiB.
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub struct PidMemory {
    pub pid: u32,
    pub used_mib: u64,
}

/// Every program on every card with its process id. None when the program does not run, fails, or is too slow.
pub fn query_pid_memory(program: &str, timeout: Duration) -> Option<Vec<PidMemory>> {
    run(program, &PID_PROGRAM_ARGUMENTS, timeout).map(|text| parse_pid_memory(&text))
}

/// Lines like `GPU-aaa, 4242, python3, 1024`. A line without a number for the id or the memory (`[N/A]`) is left out.
pub fn parse_pid_memory(text: &str) -> Vec<PidMemory> {
    text.lines().filter_map(|line| {
        let fields: Vec<&str> = line.split(',').map(str::trim).collect();
        if fields.len() != PID_PROGRAM_FIELDS { return None; }
        Some(PidMemory { pid: fields[1].parse().ok()?, used_mib: fields[3].parse().ok()? })
    }).collect()
}

pub fn parse(text: &str) -> Vec<Card> {
    text.lines().filter_map(parse_line).take(MAX_GPUS).collect()
}

fn parse_line(line: &str) -> Option<Card> {
    let fields: Vec<&str> = line.split(',').map(str::trim).collect();
    if fields.len() != CARD_FIELDS || fields[0].is_empty() {
        return None;
    }
    let gpu = GpuStats {
        utilization_percent: number(fields[1], MAX_PERCENT),
        memory_used_bytes: mib(fields[2]),
        memory_total_bytes: mib(fields[3]),
        temperature_celsius: fields[4].parse::<f64>().ok().filter(|v| (MIN_CELSIUS..=MAX_CELSIUS).contains(v)).map(one_decimal),
        power_watts: number(fields[5], MAX_WATTS),
        power_limit_watts: number(fields[6], MAX_WATTS),
        fan_percent: number(fields[7], MAX_PERCENT),
        clock_mhz: number(fields[8], MAX_MHZ).filter(|mhz| *mhz > 0.0),
        ..GpuStats::named(cut(fields[0], MAX_NAME_CHARS), VENDOR_NVIDIA)
    };
    Some(Card { gpu, uuid: fields[9].to_string() })
}

/// "[N/A]", "[Not Supported]" and empty text do not parse, so they become null, as does anything outside 0 to `max`.
fn number(text: &str, max: f64) -> Option<f64> {
    text.parse::<f64>().ok().filter(|v| (0.0..=max).contains(v)).map(one_decimal)
}

fn mib(text: &str) -> Option<u64> {
    text.parse::<u64>().ok()?.checked_mul(BYTES_PER_MIB)
}

/// Programs per card, the biggest memory first, at most eight each. A program whose memory is not told is left out.
pub fn parse_programs(text: &str) -> HashMap<String, Vec<GpuProgram>> {
    let mut by_card: HashMap<String, Vec<GpuProgram>> = HashMap::new();
    for line in text.lines() {
        let fields: Vec<&str> = line.split(',').map(str::trim).collect();
        if fields.len() != PROGRAM_FIELDS || fields[1].is_empty() {
            continue;
        }
        let Some(memory_bytes) = mib(fields[2]) else { continue };
        by_card.entry(fields[0].to_string()).or_default().push(GpuProgram { name: cut(program_name(fields[1]), MAX_NAME_CHARS), memory_bytes });
    }
    for programs in by_card.values_mut() {
        programs.sort_by_key(|program| std::cmp::Reverse(program.memory_bytes));
        programs.truncate(MAX_GPU_PROGRAMS);
    }
    by_card
}

/// `nvidia-smi` tells the program's path; the last part is the name people know.
fn program_name(path: &str) -> &str {
    path.rsplit('/').next().filter(|name| !name.is_empty()).unwrap_or(path)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    /// A loaded computer (a build running beside the tests) can take seconds to start a fresh script; the tests that expect an answer wait for it.
    const PATIENT: Duration = Duration::from_secs(30);
    const CARD_ANSWER: &str = "NVIDIA GeForce RTX 5090, 40, 2048, 32768, 55, 310.25, 575.00, 30, 2400, GPU-aaa\n\
        NVIDIA Thing, [N/A], [N/A], 8192, [Not Supported], [N/A], [N/A], [N/A], [N/A], GPU-bbb\n";
    const PROGRAM_ANSWER: &str = "GPU-aaa, /usr/bin/python3, 1024\nGPU-aaa, /opt/llama/server, 4096\nGPU-bbb, [N/A], 10\nGPU-bbb, worker, [N/A]\n";

    /// Written and closed before it is run, so no half-written script is ever executed.
    fn script(body: &str) -> String {
        let path = std::env::temp_dir().join(format!("ms-smi-{}", rand::random::<u64>()));
        std::fs::write(&path, format!("#!/bin/sh\n{body}\n")).unwrap();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755)).unwrap();
        path.to_string_lossy().into_owned()
    }

    #[test]
    fn pid_memory_lines() {
        let parsed = parse_pid_memory("GPU-aaa, 4242, /usr/bin/python3, 1024\nGPU-aaa, 77, worker, [N/A]\nGPU-bbb, x, y, 5\nshort, 1\nGPU-bbb, 9, a, b, 7\nGPU-bbb, 9, name, 300\n");
        assert_eq!(parsed, [PidMemory { pid: 4242, used_mib: 1024 }, PidMemory { pid: 9, used_mib: 300 }]);
        assert!(parse_pid_memory("").is_empty());
    }

    #[test]
    fn reads_the_csv_and_turns_mib_into_bytes() {
        let cards = parse(CARD_ANSWER);
        assert_eq!(cards[0].uuid, "GPU-aaa");
        let first = &cards[0].gpu;
        assert_eq!((first.name.as_str(), first.vendor), ("NVIDIA GeForce RTX 5090", "nvidia"));
        assert_eq!((first.utilization_percent, first.memory_used_bytes, first.memory_total_bytes), (Some(40.0), Some(2048 * BYTES_PER_MIB), Some(32768 * BYTES_PER_MIB)));
        assert_eq!((first.temperature_celsius, first.power_watts, first.power_limit_watts), (Some(55.0), Some(310.3), Some(575.0)));
        assert_eq!((first.fan_percent, first.clock_mhz, first.processes.is_none()), (Some(30.0), Some(2400.0), true));
    }

    #[test]
    fn not_available_values_are_null_on_a_second_card() {
        let second = &parse(CARD_ANSWER)[1].gpu;
        let unknown = (second.utilization_percent, second.memory_used_bytes, second.temperature_celsius, second.power_watts, second.power_limit_watts, second.fan_percent, second.clock_mhz);
        assert_eq!(unknown, (None, None, None, None, None, None, None));
        assert_eq!(second.memory_total_bytes, Some(8192 * BYTES_PER_MIB));
    }

    #[test]
    fn out_of_range_numbers_become_null() {
        let cards = parse("Odd, 140, 1, 2, 900, 5000, -4, 250, 0, GPU-x\n");
        let odd = &cards[0].gpu;
        assert_eq!((odd.utilization_percent, odd.power_watts, odd.power_limit_watts, odd.fan_percent, odd.clock_mhz), (None, None, None, None, None));
        assert_eq!(odd.temperature_celsius, None);
    }

    #[test]
    fn broken_lines_are_dropped() {
        assert!(parse("garbage\n, 1, 2, 3, 4, 5, 6, 7, 8, 9\nonly, two\nNVIDIA Old, 1, 2, 3, 4\n").is_empty());
    }

    #[test]
    fn programs_are_grouped_by_card_biggest_first_and_cut() {
        let programs = parse_programs(PROGRAM_ANSWER);
        assert_eq!(programs["GPU-aaa"], vec![GpuProgram { name: "server".into(), memory_bytes: 4096 * BYTES_PER_MIB }, GpuProgram { name: "python3".into(), memory_bytes: 1024 * BYTES_PER_MIB }]);
        assert_eq!(programs["GPU-bbb"].len(), 1, "a program without memory is left out");
        let many: String = (0..12).map(|n| format!("GPU-aaa, {}, {n}\n", "x".repeat(100))).collect();
        let listed = &parse_programs(&many)["GPU-aaa"];
        assert_eq!((listed.len(), listed[0].name.chars().count(), listed[0].memory_bytes), (MAX_GPU_PROGRAMS, MAX_NAME_CHARS, 11 * BYTES_PER_MIB));
    }

    #[test]
    fn runs_the_program_twice_and_gives_each_card_its_programs() {
        let program = script(
            "case \"$1\" in\n--query-gpu*) echo 'Fake GPU, 10, 100, 200, 30, 50, 100, 20, 1500, GPU-1'; echo 'Quiet GPU, 1, 1, 2, 30, 5, 10, 20, 100, GPU-2';;\n--query-compute-apps*) echo 'GPU-1, /bin/job, 7';;\nesac",
        );
        let gpus = query(&program, PATIENT).unwrap();
        assert_eq!(gpus[0].name, "Fake GPU");
        assert_eq!(gpus[0].processes, Some(vec![GpuProgram { name: "job".into(), memory_bytes: 7 * BYTES_PER_MIB }]));
        assert_eq!(gpus[1].processes, Some(Vec::new()), "the call worked and this card has none");
    }

    #[test]
    fn a_failing_second_call_only_means_no_program_list() {
        let program = script("case \"$1\" in\n--query-gpu*) echo 'Fake GPU, 10, 100, 200, 30, 50, 100, 20, 1500, GPU-1';;\n*) exit 3;;\nesac");
        let gpus = query(&program, PATIENT).unwrap();
        assert_eq!((gpus[0].name.as_str(), gpus[0].processes.is_none()), ("Fake GPU", true));
    }

    #[test]
    fn no_readings_when_the_program_is_missing_fails_or_is_slow() {
        assert!(query("/no/such/nvidia-smi", QUERY_TIMEOUT).is_none());
        assert!(query(&script("exit 9"), PATIENT).is_none());
        assert!(query(&script("echo nonsense"), PATIENT).is_none());
        let started = Instant::now();
        assert!(query(&script("sleep 5"), Duration::from_millis(200)).is_none());
        assert!(started.elapsed() < Duration::from_secs(3));
    }
}

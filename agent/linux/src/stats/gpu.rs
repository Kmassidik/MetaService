//! NVIDIA GPUs through `nvidia-smi`, with a fixed argument list, no shell and a short time limit. No program or no answer means no GPU block.
use super::model::{cut, one_decimal, GpuStats, MAX_GPUS, MAX_NAME_CHARS};
use std::io::Read;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

pub const QUERY_TIMEOUT: Duration = Duration::from_secs(3);
const QUERY_ARGUMENTS: [&str; 2] = ["--query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu", "--format=csv,noheader,nounits"];
const FIELDS: usize = 5;
const BYTES_PER_MIB: u64 = 1024 * 1024;
const POLL: Duration = Duration::from_millis(20);

/// None when the program does not run, fails, is too slow, or says nothing we can read.
pub fn query(program: &str, timeout: Duration) -> Option<Vec<GpuStats>> {
    let mut child = Command::new(program).args(QUERY_ARGUMENTS).stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn().ok()?;
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
    status.success().then(|| parse(&text)).filter(|gpus| !gpus.is_empty())
}

pub fn parse(text: &str) -> Vec<GpuStats> {
    text.lines().filter_map(parse_line).take(MAX_GPUS).collect()
}

fn parse_line(line: &str) -> Option<GpuStats> {
    let fields: Vec<&str> = line.split(',').map(str::trim).collect();
    if fields.len() != FIELDS || fields[0].is_empty() {
        return None;
    }
    Some(GpuStats {
        name: cut(fields[0], MAX_NAME_CHARS),
        utilization_percent: fields[1].parse::<f64>().ok().filter(|v| (0.0..=100.0).contains(v)).map(one_decimal),
        memory_used_bytes: mib(fields[2]),
        memory_total_bytes: mib(fields[3]),
        temperature_celsius: fields[4].parse::<f64>().ok().filter(|v| v.is_finite()).map(one_decimal),
    })
}

/// "[N/A]" and "[Not Supported]" do not parse, so they become null.
fn mib(text: &str) -> Option<u64> {
    text.parse::<u64>().ok()?.checked_mul(BYTES_PER_MIB)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    fn script(body: &str) -> String {
        let path = std::env::temp_dir().join(format!("ms-smi-{}", rand::random::<u64>()));
        std::fs::write(&path, format!("#!/bin/sh\n{body}\n")).unwrap();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755)).unwrap();
        path.to_string_lossy().into_owned()
    }

    #[test]
    fn reads_the_csv_and_turns_mib_into_bytes() {
        let gpus = parse("NVIDIA GeForce RTX 5090, 40, 2048, 32768, 55\nNVIDIA Thing, [N/A], [N/A], 8192, [Not Supported]\n");
        assert_eq!(gpus[0], GpuStats { name: "NVIDIA GeForce RTX 5090".into(), utilization_percent: Some(40.0), memory_used_bytes: Some(2048 * BYTES_PER_MIB), memory_total_bytes: Some(32768 * BYTES_PER_MIB), temperature_celsius: Some(55.0) });
        assert_eq!((gpus[1].utilization_percent, gpus[1].memory_used_bytes, gpus[1].temperature_celsius), (None, None, None));
        assert_eq!(gpus[1].memory_total_bytes, Some(8192 * BYTES_PER_MIB));
    }

    #[test]
    fn broken_lines_are_dropped() {
        assert!(parse("garbage\n, 1, 2, 3, 4\nonly, two\n").is_empty());
    }

    #[test]
    fn runs_the_program_and_reads_its_answer() {
        let program = script("echo 'Fake GPU, 10, 100, 200, 30'");
        assert_eq!(query(&program, QUERY_TIMEOUT).unwrap()[0].name, "Fake GPU");
    }

    #[test]
    fn no_block_when_the_program_is_missing_fails_or_is_slow() {
        assert!(query("/no/such/nvidia-smi", QUERY_TIMEOUT).is_none());
        assert!(query(&script("exit 9"), QUERY_TIMEOUT).is_none());
        assert!(query(&script("echo nonsense"), QUERY_TIMEOUT).is_none());
        let started = Instant::now();
        assert!(query(&script("sleep 5"), Duration::from_millis(200)).is_none());
        assert!(started.elapsed() < Duration::from_secs(3));
    }
}

//! Which logical CPUs (threads) share a physical core, from /sys/devices/system/cpu/cpu*/topology.
use std::collections::HashMap;
use std::path::Path;

const CPU_DIR: &str = "sys/devices/system/cpu";

#[derive(Debug, Clone, PartialEq)]
pub struct Topology {
    pub physical_cores: usize,
    /// For each logical CPU, in the order asked, the index of its physical core (first seen is 0).
    pub core_of: Vec<usize>,
}

/// One entry per CPU id. When any id cannot be read, every CPU counts as its own core (no sibling grouping).
pub fn read(root: &Path, ids: &[usize]) -> Topology {
    let pairs: Option<Vec<(i64, i64)>> = ids.iter().map(|id| package_and_core(root, *id)).collect();
    match pairs {
        Some(pairs) => group(&pairs),
        None => alone(ids.len()),
    }
}

fn package_and_core(root: &Path, id: usize) -> Option<(i64, i64)> {
    let folder = root.join(CPU_DIR).join(format!("cpu{id}/topology"));
    let package = number_in(&folder.join("physical_package_id"))?;
    let core = number_in(&folder.join("core_id"))?;
    Some((package, core))
}

fn number_in(path: &Path) -> Option<i64> {
    let value: i64 = std::fs::read_to_string(path).ok()?.trim().parse().ok()?;
    (value >= 0).then_some(value)
}

/// Equal (package, core) pairs are threads of one core.
fn group(pairs: &[(i64, i64)]) -> Topology {
    let mut seen: HashMap<(i64, i64), usize> = HashMap::new();
    let core_of = pairs.iter().map(|pair| {
        let next = seen.len();
        *seen.entry(*pair).or_insert(next)
    }).collect();
    Topology { physical_cores: seen.len(), core_of }
}

fn alone(count: usize) -> Topology {
    Topology { physical_cores: count, core_of: (0..count).collect() }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tree(cpus: &[(usize, i64, i64)]) -> std::path::PathBuf {
        let root = std::env::temp_dir().join(format!("ms-topology-{}", rand::random::<u64>()));
        for (id, package, core) in cpus {
            let folder = root.join(CPU_DIR).join(format!("cpu{id}/topology"));
            std::fs::create_dir_all(&folder).unwrap();
            std::fs::write(folder.join("physical_package_id"), format!("{package}\n")).unwrap();
            std::fs::write(folder.join("core_id"), format!("{core}\n")).unwrap();
        }
        root
    }

    #[test]
    fn two_threads_per_core_are_grouped() {
        let root = tree(&[(0, 0, 0), (1, 0, 1), (2, 0, 0), (3, 0, 1)]);
        let topology = read(&root, &[0, 1, 2, 3]);
        assert_eq!(topology, Topology { physical_cores: 2, core_of: vec![0, 1, 0, 1] });
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn the_same_core_number_in_two_sockets_is_two_cores() {
        let root = tree(&[(0, 0, 0), (1, 1, 0)]);
        assert_eq!(read(&root, &[0, 1]).physical_cores, 2);
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn unreadable_topology_counts_every_cpu_as_a_core() {
        let root = tree(&[(0, 0, 0)]);
        assert_eq!(read(&root, &[0, 1]), Topology { physical_cores: 2, core_of: vec![0, 1] });
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn a_negative_core_number_is_unreadable() {
        let root = tree(&[(0, 0, -1)]);
        assert_eq!(read(&root, &[0]).physical_cores, 1);
        std::fs::remove_dir_all(root).unwrap();
    }
}

//! Puts the chat bundle where it belongs: on this machine (run by the Agent) or inside a workload (run by systemd there).
//! It downloads from the Root with the machine token, checks the checksum and the archive, and only then installs anything.
use crate::config::Config;
use crate::engine::Engine;
use crate::files::write_private;
use crate::service::BundleInstalling;
use crate::supervisor::Supervisor;
use crate::validate::BundleRequest;
use flate2::read::GzDecoder;
use rand::Rng;
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::io::Read;
use std::path::{Component, Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::Duration;

const MAX_BYTES: u64 = 64 * 1024 * 1024;
const MAX_ENTRIES: usize = 200;
const KEEP_VERSIONS: usize = 3;
const HEALTH_TRIES: u32 = 15;

/// Installs inside a workload: python3 if missing, a locked-down user, the files, a systemd service, and a health check.
/// Fixed text. The version and port arrive as MS_VERSION and MS_PORT; the archive and key were copied in beforehand.
pub const WORKLOAD_SCRIPT: &str = r#"set -e
command -v python3 >/dev/null || { export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y -qq --no-install-recommends python3 >/dev/null; }
id -u metachat >/dev/null 2>&1 || useradd --system --home-dir /opt/metaservice --shell /usr/sbin/nologin metachat
dir="/opt/metaservice/chat/$MS_VERSION"
rm -rf "$dir"; mkdir -p "$dir"
tar -xzf /tmp/metaservice-chat.tar.gz -C "$dir" --no-same-owner
chown -R root:root /opt/metaservice/chat
install -o metachat -g metachat -m 600 /tmp/metaservice-chat.key /opt/metaservice/chat.key
install -d -o metachat -g metachat -m 700 /opt/metaservice/chat-data
rm -f /tmp/metaservice-chat.tar.gz /tmp/metaservice-chat.key
ln -sfn "$dir" /opt/metaservice/chat/current
brain=""; if [ -n "$MS_BRAIN_URL" ]; then brain="--brain-url $MS_BRAIN_URL"; fi
cat > /etc/systemd/system/metaservice-chat.service <<UNIT
[Unit]
Description=MetaService chat
After=network.target
[Service]
User=metachat
ReadWritePaths=/opt/metaservice/chat-data
ExecStart=/usr/bin/python3 /opt/metaservice/chat/current/service/chat.py --port $MS_PORT --key-file /opt/metaservice/chat.key $brain
Restart=always
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable metaservice-chat >/dev/null 2>&1
systemctl restart metaservice-chat
for _ in 1 2 3 4 5 6 7 8 9 10; do
  python3 -c "import json,sys,urllib.request; sys.exit(0 if json.load(urllib.request.urlopen('http://127.0.0.1:$MS_PORT/health', timeout=2))['version'] == '$MS_VERSION' else 1)" 2>/dev/null && exit 0
  sleep 1
done
exit 1
"#;

#[derive(Default)]
struct Persisted {
    keys: HashMap<String, String>,
    version: Option<String>,
}

pub struct BundleInstaller {
    config: Config,
    engine: Arc<dyn Engine>,
    root: Option<String>,
    machine_token: Option<String>,
    supervisor: Option<Arc<Supervisor>>,
    state: Mutex<Persisted>,
    one_at_a_time: Mutex<()>,
}

impl BundleInstaller {
    pub fn new(config: Config, engine: Arc<dyn Engine>, root: Option<String>, machine_token: Option<String>, supervisor: Option<Arc<Supervisor>>) -> Arc<BundleInstaller> {
        let keys = std::fs::read(config.state_dir.join("chat-keys.json")).ok().and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
        let version = std::fs::read(config.state_dir.join("bundle.json")).ok().and_then(|b| serde_json::from_slice::<Value>(&b).ok())
            .and_then(|v| v["version"].as_str().map(str::to_string));
        Arc::new(BundleInstaller { config, engine, root, machine_token, supervisor, state: Mutex::new(Persisted { keys, version }), one_at_a_time: Mutex::new(()) })
    }

    /// On start: run the version that was installed before, if any.
    pub fn resume(&self) {
        let (version, key) = { let state = self.state.lock().unwrap(); (state.version.clone(), state.keys.get("machine").cloned()) };
        if let (Some(version), Some(key), Some(supervisor)) = (version, key, &self.supervisor) {
            if let Ok(key_file) = self.key_file("machine", &key) {
                supervisor.run(self.chat_arguments(&version, &key_file));
            }
        }
    }

    fn download(&self, request: &BundleRequest) -> Result<Vec<u8>, String> {
        let (Some(root), Some(token)) = (&self.root, &self.machine_token) else { return Err("this Agent has no Root to download from".into()) };
        let reply = ureq::get(&format!("{root}/v1/bundles/{}/noarch", request.version)).timeout(Duration::from_secs(60)).set("Authorization", &format!("Bearer {token}")).call()
            .map_err(|_| "the Root did not give the bundle".to_string())?;
        let mut bytes = Vec::new();
        reply.into_reader().take(MAX_BYTES + 1).read_to_end(&mut bytes).map_err(|e| e.to_string())?;
        if bytes.len() as u64 > MAX_BYTES {
            return Err("the bundle is too large".into());
        }
        if hex(&Sha256::digest(&bytes)) != request.sha256 {
            return Err("the bundle does not match its checksum".into());
        }
        Ok(bytes)
    }

    fn tmp_dir(&self) -> Result<PathBuf, String> {
        let dir = self.config.state_dir.join("tmp");
        std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
        Ok(dir)
    }

    fn key_file(&self, target: &str, key: &str) -> Result<PathBuf, String> {
        let path = self.config.state_dir.join(format!("chat-{target}.key"));
        write_private(&path, key.as_bytes()).map_err(|e| e.to_string())?;
        Ok(path)
    }

    fn chat_arguments(&self, version: &str, key_file: &Path) -> Vec<String> {
        let folder = self.config.state_dir.join("bundles").join(version);
        let bind = self.config.chat_bind.clone().unwrap_or_else(|| self.config.bind.clone());
        let mut arguments = vec![
            folder.join("service/chat.py").display().to_string(), "--port".into(), self.config.chat_port.to_string(), "--bind".into(), bind, "--key-file".into(),
            key_file.display().to_string(), "--web-dir".into(), folder.join("web").display().to_string(), "--version".into(), version.to_string(),
        ];
        if let Some(url) = self.brain_url() {
            arguments.extend(["--brain-url".to_string(), url]);
        }
        arguments
    }

    /// Where the chat asks for AI replies: the Root this Agent reports to. An address, not a secret.
    fn brain_url(&self) -> Option<String> {
        self.root.as_ref().map(|root| root.trim_end_matches('/').to_string())
    }

    fn healthy(&self, version: &str) -> bool {
        for _ in 0..HEALTH_TRIES {
            let answer = ureq::get(&format!("http://127.0.0.1:{}/health", self.config.chat_port)).timeout(Duration::from_secs(2)).call().ok()
                .and_then(|r| serde_json::from_reader::<_, Value>(r.into_reader()).ok());
            if answer.is_some_and(|v| v["version"] == version) {
                return true;
            }
            std::thread::sleep(Duration::from_secs(1));
        }
        false
    }

    fn install_here(&self, bytes: &[u8], key: &str, request: &BundleRequest) -> Result<(), String> {
        let Some(supervisor) = &self.supervisor else { return Err("python3 was not found on this machine".into()) };
        let folder = self.config.state_dir.join("bundles").join(&request.version);
        let _ = std::fs::remove_dir_all(&folder);
        std::fs::create_dir_all(&folder).map_err(|e| e.to_string())?;
        extract(bytes, &folder)?;
        let (previous, old_key) = { let state = self.state.lock().unwrap(); (state.version.clone(), state.keys.get("machine").cloned()) };
        supervisor.run(self.chat_arguments(&request.version, &self.key_file("machine", key)?));
        if !self.healthy(&request.version) {
            match (previous, old_key) {
                (Some(old), Some(old_key)) => supervisor.run(self.chat_arguments(&old, &self.key_file("machine", &old_key)?)),
                _ => supervisor.stop(),
            }
            return Err("the new chat did not start, so the old one was put back".into());
        }
        self.state.lock().unwrap().version = Some(request.version.clone());
        write_private(&self.config.state_dir.join("bundle.json"), serde_json::json!({"version": request.version}).to_string().as_bytes()).map_err(|e| e.to_string())?;
        self.prune(&request.version);
        Ok(())
    }

    fn prune(&self, current: &str) {
        let folder = self.config.state_dir.join("bundles");
        let mut all: Vec<String> = std::fs::read_dir(&folder).into_iter().flatten().flatten().filter_map(|e| e.file_name().into_string().ok()).collect();
        all.sort();
        let keep_from = all.len().saturating_sub(KEEP_VERSIONS);
        for old in all.iter().take(keep_from).filter(|v| v.as_str() != current) {
            let _ = std::fs::remove_dir_all(folder.join(old));
        }
    }

    fn install_inside(&self, workload: &str, bytes: &[u8], key: &str, request: &BundleRequest) -> Result<(), String> {
        let tmp = self.tmp_dir()?;
        let archive = tmp.join(format!("push-{workload}.tar.gz"));
        let key_path = tmp.join(format!("push-{workload}.key"));
        write_private(&archive, bytes).map_err(|e| e.to_string())?;
        write_private(&key_path, key.as_bytes()).map_err(|e| e.to_string())?;
        let outcome = self.push_and_run(workload, &archive, &key_path, request);
        let _ = std::fs::remove_file(&archive);
        let _ = std::fs::remove_file(&key_path);
        outcome
    }

    fn push_and_run(&self, workload: &str, archive: &Path, key_path: &Path, request: &BundleRequest) -> Result<(), String> {
        let failed = |e: crate::models::EngineError| format!("{e:?}");
        self.engine.push(workload, &archive.display().to_string(), "/tmp/metaservice-chat.tar.gz").map_err(failed)?;
        self.engine.push(workload, &key_path.display().to_string(), "/tmp/metaservice-chat.key").map_err(failed)?;
        let environment = [("MS_VERSION".to_string(), request.version.clone()), ("MS_PORT".to_string(), self.config.chat_port.to_string()), ("MS_BRAIN_URL".to_string(), self.brain_url().unwrap_or_default())];
        self.engine.exec(workload, &["sh".into(), "-c".into(), WORKLOAD_SCRIPT.into()], &environment).map_err(failed)?;
        self.engine.set_bundle_version(workload, &request.version).map_err(failed)
    }

    fn remember_key(&self, target: &str, key: &str) -> Result<(), String> {
        let mut state = self.state.lock().unwrap();
        state.keys.insert(target.to_string(), key.to_string());
        write_private(&self.config.state_dir.join("chat-keys.json"), &serde_json::to_vec(&state.keys).map_err(|e| e.to_string())?).map_err(|e| e.to_string())
    }
}

impl BundleInstalling for BundleInstaller {
    fn installed_version(&self) -> Option<String> {
        self.state.lock().unwrap().version.clone()
    }

    /// One install at a time, so two cannot swap the running chat back and forth.
    fn install(&self, request: &BundleRequest) -> Result<HashMap<String, String>, String> {
        let _only_one = self.one_at_a_time.lock().unwrap();
        let bytes = self.download(request)?;
        check_archive(&bytes, &request.version)?;
        let target = request.workload_id.clone().unwrap_or_else(|| "machine".into());
        let key = self.state.lock().unwrap().keys.get(&target).cloned().unwrap_or_else(random_key);
        match &request.workload_id {
            Some(workload) => self.install_inside(workload, &bytes, &key, request)?,
            None => self.install_here(&bytes, &key, request)?,
        }
        self.remember_key(&target, &key)?;
        Ok(HashMap::from([("version".to_string(), request.version.clone()), ("port".to_string(), self.config.chat_port.to_string()), ("chat_key".to_string(), key)]))
    }
}

pub fn find_python() -> Option<String> {
    ["/usr/bin/python3", "/usr/local/bin/python3", "/opt/homebrew/bin/python3", "/run/current-system/sw/bin/python3"].iter().find(|p| Path::new(p).is_file()).map(|p| p.to_string())
}

fn random_key() -> String {
    const ALPHABET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    let mut random = rand::thread_rng();
    (0..40).map(|_| ALPHABET[random.gen_range(0..ALPHABET.len())] as char).collect()
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

/// The archive may hold only plain files and folders with safe relative names, and its manifest must be the version that was asked for.
pub fn check_archive(bytes: &[u8], version: &str) -> Result<(), String> {
    let mut archive = tar::Archive::new(GzDecoder::new(bytes));
    let mut manifest: Option<Value> = None;
    let mut count = 0usize;
    for entry in archive.entries().map_err(|_| "the bundle archive is not acceptable")? {
        let mut entry = entry.map_err(|_| "the bundle archive is not acceptable")?;
        count += 1;
        if count > MAX_ENTRIES || !(entry.header().entry_type().is_file() || entry.header().entry_type().is_dir()) {
            return Err("the bundle holds something other than files".into());
        }
        let path = entry.path().map_err(|_| "the bundle has an unreadable file name")?.into_owned();
        if !path.components().all(|c| matches!(c, Component::Normal(_))) {
            return Err("the bundle has an unsafe file name".into());
        }
        if path == Path::new("manifest.json") {
            let mut text = String::new();
            entry.by_ref().take(64 * 1024).read_to_string(&mut text).map_err(|_| "the manifest cannot be read")?;
            manifest = serde_json::from_str(&text).ok();
        }
    }
    match manifest {
        Some(m) if m["name"] == "metaservice-chat" && m["version"] == version => Ok(()),
        _ => Err("the bundle is not the version that was asked for".into()),
    }
}

fn extract(bytes: &[u8], into: &Path) -> Result<(), String> {
    let mut archive = tar::Archive::new(GzDecoder::new(bytes));
    archive.set_preserve_permissions(true);
    archive.set_unpack_xattrs(false);
    for entry in archive.entries().map_err(|e| e.to_string())? {
        let mut entry = entry.map_err(|e| e.to_string())?;
        if !entry.unpack_in(into).map_err(|e| e.to_string())? {
            return Err("the bundle has an unsafe file name".into());
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn archive(entries: &[(&str, &[u8], tar::EntryType)]) -> Vec<u8> {
        let mut builder = tar::Builder::new(Vec::new());
        for (name, data, kind) in entries {
            let mut header = tar::Header::new_gnu();
            header.set_entry_type(*kind);
            header.set_size(data.len() as u64);
            header.set_mode(0o644);
            header.set_cksum();
            builder.append_data(&mut header, name, *data).unwrap();
        }
        let tar_bytes = builder.into_inner().unwrap();
        let mut out = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::fast());
        std::io::Write::write_all(&mut out, &tar_bytes).unwrap();
        out.finish().unwrap()
    }

    const MANIFEST: &[u8] = br#"{"name":"metaservice-chat","version":"1.2.3"}"#;

    #[test]
    fn a_good_archive_passes_and_the_version_must_match() {
        let good = archive(&[("manifest.json", MANIFEST, tar::EntryType::Regular), ("service/chat.py", b"x", tar::EntryType::Regular)]);
        assert!(check_archive(&good, "1.2.3").is_ok());
        assert!(check_archive(&good, "1.2.4").is_err());
        assert!(check_archive(&archive(&[("service/chat.py", b"x", tar::EntryType::Regular)]), "1.2.3").is_err(), "no manifest");
        assert!(check_archive(b"not a tar", "1.2.3").is_err());
    }

    #[test]
    fn links_and_unsafe_names_are_refused() {
        for kind in [tar::EntryType::Symlink, tar::EntryType::Link, tar::EntryType::Fifo, tar::EntryType::Char] {
            let bad = archive(&[("manifest.json", MANIFEST, tar::EntryType::Regular), ("evil", b"", kind)]);
            assert!(check_archive(&bad, "1.2.3").is_err(), "{kind:?}");
        }
        let many: Vec<(String, Vec<u8>)> = (0..210).map(|i| (format!("f{i}"), vec![])).collect();
        let entries: Vec<(&str, &[u8], tar::EntryType)> = std::iter::once(("manifest.json", MANIFEST, tar::EntryType::Regular)).chain(many.iter().map(|(n, d)| (n.as_str(), d.as_slice(), tar::EntryType::Regular))).collect();
        assert!(check_archive(&archive(&entries), "1.2.3").is_err(), "too many entries");
    }

    #[test]
    fn the_workload_script_is_fixed_text_that_takes_values_only_from_the_environment() {
        for needle in ["$MS_VERSION", "$MS_PORT", "metachat", "NoNewPrivileges=true", "ProtectSystem=strict"] {
            assert!(WORKLOAD_SCRIPT.contains(needle), "{needle}");
        }
        assert!(!WORKLOAD_SCRIPT.contains("{}") && !WORKLOAD_SCRIPT.contains("{0}"));
    }

    #[test]
    fn keys_are_long_and_different() {
        let (a, b) = (random_key(), random_key());
        assert!(a.len() >= 32 && a != b && a.chars().all(|c| c.is_ascii_alphanumeric()));
    }
}

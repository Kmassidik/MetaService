//! The runner's wire format: **newline-delimited JSON**, one request per line, one answer per line.
//!
//! Each line is a JSON object read with the helper's own strict reader ([`crate::validate::Object`]), so an unknown field, a missing field, a number
//! outside its bounds or an id that is not the contract's 20 lowercase letters and digits is refused whole — nothing is salvaged from a line that does
//! not match. A line longer than [`MAX_LINE`] is refused and the connection is closed, so a caller cannot stream its way past the cap.
//!
//! There are five operations and no more. There is no shell and no free-form argv: the caller names an operation and its numbers, and every program, flag
//! and path is a constant of the runner's build.
use crate::sandbox::record::{is_sandbox_id, MAX_RAM_MB, MAX_VCPU, MIN_RAM_MB, MIN_VCPU};
use crate::validate::Object;
use serde_json::{json, Value};
use std::io::BufRead;

/// The protocol version this build speaks. A client and a runner that disagree say so instead of guessing.
pub const PROTOCOL: u64 = 1;
/// The longest request or answer line, in bytes.
pub const MAX_LINE: usize = 4096;

/// Every request there is: five operations, no more.
const OPERATIONS: [&str; 5] = ["health", "create-network", "delete-network", "start", "stop"];

/// One request: the whole list.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Request {
    /// `{"op":"health"}`: is the runner there, and which protocol does it speak.
    Health,
    /// `{"op":"create-network","id":"…","internet":true}`: the namespace, the tap, the veth pair and the firewall rules.
    CreateNetwork { id: String, internet: bool },
    /// `{"op":"delete-network","id":"…"}`: all of it back out, rules included. Repeating it is not an error.
    DeleteNetwork { id: String },
    /// `{"op":"start","id":"…","vcpu":2,"ram_mb":512}`: Firecracker through the jailer, from that network.
    Start { id: String, vcpu: u32, ram_mb: u64 },
    /// `{"op":"stop","id":"…"}`: the process only; the network stays until `delete-network`.
    Stop { id: String },
}

impl Request {
    pub fn parse(line: &str) -> Result<Request, String> {
        let value: Value = serde_json::from_str(line).map_err(|_| "a request is one JSON object on one line".to_string())?;
        let op = value.get("op").and_then(Value::as_str).ok_or("every request names its op")?;
        if !OPERATIONS.contains(&op) {
            return Err(format!("{op:?} is not one of {OPERATIONS:?}"));
        }
        // Read again with exactly this operation's fields: a field that belongs to another request is an unknown field here.
        let allowed: &[&str] = match op {
            "health" => &["op"],
            "create-network" => &["op", "id", "internet"],
            "delete-network" | "stop" => &["op", "id"],
            _ => &["op", "id", "vcpu", "ram_mb"],
        };
        let object = Object::parse(line.as_bytes(), allowed)?;
        let id = || sandbox_id(&object);
        match op {
            "health" => Ok(Request::Health),
            "create-network" => Ok(Request::CreateNetwork { id: id()?, internet: object.boolean("internet")? }),
            "delete-network" => Ok(Request::DeleteNetwork { id: id()? }),
            "start" => Ok(Request::Start { id: id()?, vcpu: object.int("vcpu", MIN_VCPU, MAX_VCPU)? as u32, ram_mb: object.int("ram_mb", MIN_RAM_MB, MAX_RAM_MB)? }),
            _ => Ok(Request::Stop { id: id()? }),
        }
    }
}

/// One line, read as it arrives so a caller cannot stream past [`MAX_LINE`], and ending exactly at its newline: a line that does not fit or does not
/// end is refused rather than half-read. None at a clean end of the connection, which is how a caller says it is done.
pub fn read_line(reader: &mut impl BufRead) -> Result<Option<String>, String> {
    let mut line: Vec<u8> = Vec::new();
    loop {
        let available = reader.fill_buf().map_err(|e| format!("cannot read a line: {e}"))?;
        if available.is_empty() {
            return if line.is_empty() { Ok(None) } else { Err("a line must end with a newline".into()) };
        }
        let newline = available.iter().position(|byte| *byte == b'\n');
        let take = newline.map_or(available.len(), |at| at + 1);
        line.extend_from_slice(&available[..take]);
        reader.consume(take);
        if line.len() > MAX_LINE {
            return Err(format!("one line is at most {MAX_LINE} bytes"));
        }
        let Some(_) = newline else { continue };
        let text = String::from_utf8(line).map_err(|_| "a line must be text".to_string())?;
        return Ok(Some(text.trim_end_matches('\n').to_string()));
    }
}

/// An id as every request that names a sandbox carries it: the contract's shape, so it can never be a path or a flag.
fn sandbox_id(object: &Object) -> Result<String, String> {
    let id = object.text("id")?;
    if is_sandbox_id(id) {
        return Ok(id.to_string());
    }
    Err("id must be 20 lowercase letters or digits".into())
}

/// One answer. Only `health` carries a version; only the steps that touch a sandbox carry its slot. A step that failed inside an otherwise good answer
/// is not put on the wire: the runner logs it, and the helper only needs to know whether the operation happened.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Reply {
    Health { version: String, protocol: u64 },
    Done { slot: Option<u8>, steps: usize },
    Failed { error: String },
}

impl Reply {
    pub fn to_line(&self) -> String {
        let answer = match self {
            Reply::Health { version, protocol } => json!({ "ok": true, "version": version, "protocol": protocol }),
            Reply::Done { slot, steps } => json!({ "ok": true, "slot": slot, "steps": steps }),
            Reply::Failed { error } => json!({ "ok": false, "error": error }),
        };
        answer.to_string()
    }

    /// An answer from the other end of the socket, read as strictly as a request.
    pub fn parse(line: &str) -> Result<Reply, String> {
        let object = Object::parse(line.as_bytes(), &["ok", "error", "version", "protocol", "slot", "steps"])?;
        if !object.boolean("ok")? {
            return Ok(Reply::Failed { error: object.text("error").unwrap_or("the runner refused it").to_string() });
        }
        if object.sent("version") {
            return Ok(Reply::Health { version: object.text("version")?.to_string(), protocol: object.int("protocol", 0, u64::MAX)? });
        }
        let slot = if object.has("slot") { Some(object.int("slot", 0, u64::from(super::super::firecracker::SLOTS - 1))? as u8) } else { None };
        Ok(Reply::Done { slot, steps: object.int("steps", 0, u64::MAX)? as usize })
    }
}

/// What the caller of the runner is told: a plain reason, never a path or a command line, and short enough to log whole.
pub fn failure(error: &str) -> Reply {
    Reply::Failed { error: error.chars().take(200).collect() }
}

#[cfg(test)]
mod tests {
    use super::*;

    const ID: &str = "abcdefghij0123456789";

    #[test]
    fn every_request_in_the_list_is_read_whole() {
        assert_eq!(Request::parse(r#"{"op":"health"}"#), Ok(Request::Health));
        assert_eq!(Request::parse(&format!(r#"{{"op":"create-network","id":"{ID}","internet":true}}"#)), Ok(Request::CreateNetwork { id: ID.into(), internet: true }));
        assert_eq!(Request::parse(&format!(r#"{{"op":"delete-network","id":"{ID}"}}"#)), Ok(Request::DeleteNetwork { id: ID.into() }));
        assert_eq!(Request::parse(&format!(r#"{{"op":"start","id":"{ID}","vcpu":2,"ram_mb":512}}"#)), Ok(Request::Start { id: ID.into(), vcpu: 2, ram_mb: 512 }));
        assert_eq!(Request::parse(&format!(r#"{{"op":"stop","id":"{ID}"}}"#)), Ok(Request::Stop { id: ID.into() }));
        assert_eq!(Request::parse(&format!(r#"{{"op":"create-network","id":"{ID}","internet":false}}"#)), Ok(Request::CreateNetwork { id: ID.into(), internet: false }));
    }

    #[test]
    fn a_hostile_id_is_refused_like_every_other_bad_field() {
        for id in ["a b", "../x", "--help", "", "ABCDEFGHIJ0123456789", "abc"] {
            let line = format!(r#"{{"op":"stop","id":"{id}"}}"#);
            assert!(Request::parse(&line).is_err(), "{id:?}");
        }
    }

    #[test]
    fn a_request_that_is_not_exactly_one_of_the_list_is_refused() {
        for line in [
            "", "not json", "[]", r#"{"op":"shell","command":"reboot"}"#, r#"{"op":"health","x":1}"#, r#"{"op":"stop"}"#,
            r#"{"op":"stop","id":"abcdefghij0123456789","command":"reboot"}"#, r#"{"op":"create-network","id":"abcdefghij0123456789"}"#,
            r#"{"op":"create-network","id":"abcdefghij0123456789","internet":"yes"}"#, r#"{"id":"abcdefghij0123456789"}"#,
        ] {
            assert!(Request::parse(line).is_err(), "{line:?}");
        }
        for (vcpu, ram_mb) in [(0, 512), (33, 512), (2, 0), (2, 65537), (2, 128)] {
            let line = format!(r#"{{"op":"start","id":"{ID}","vcpu":{vcpu},"ram_mb":{ram_mb}}}"#);
            assert!(Request::parse(&line).is_err(), "{vcpu} vCPU and {ram_mb} MB");
        }
    }

    #[test]
    fn an_answer_reads_back_as_the_same_answer() {
        let answers = [
            Reply::Health { version: "0.1.0".into(), protocol: PROTOCOL },
            Reply::Done { slot: Some(7), steps: 13 },
            Reply::Done { slot: None, steps: 2 },
            Reply::Failed { error: "no free slot on this machine".into() },
        ];
        for answer in answers {
            assert_eq!(Reply::parse(&answer.to_line()), Ok(answer.clone()), "{}", answer.to_line());
        }
        let failed = Reply::parse(r#"{"ok":false,"error":"nope"}"#).ok().unwrap();
        assert_eq!(failed, Reply::Failed { error: "nope".into() });
        assert!(Reply::parse(r#"{"ok":true,"extra":1}"#).is_err(), "an answer with a field this build does not know is refused too");
    }

    #[test]
    fn a_line_is_read_up_to_its_newline_and_no_further() {
        let mut reader = std::io::BufReader::new(&b"one\ntwo\n\n"[..]);
        assert_eq!(read_line(&mut reader), Ok(Some("one".into())));
        assert_eq!(read_line(&mut reader), Ok(Some("two".into())));
        assert_eq!(read_line(&mut reader), Ok(Some(String::new())), "an empty line is read; what it means is the server's business");
        assert_eq!(read_line(&mut reader), Ok(None));
        let mut unterminated = std::io::BufReader::new(&b"half"[..]);
        assert!(read_line(&mut unterminated).is_err(), "a line that does not end is refused, not guessed");
        let overlong = vec![b'x'; MAX_LINE + 2];
        let mut long = std::io::BufReader::new(&overlong[..]);
        assert_eq!(read_line(&mut long).err(), Some(format!("one line is at most {MAX_LINE} bytes")));
    }

    #[test]
    fn a_failure_is_short_enough_to_log_whole() {
        let long = "x".repeat(10_000);
        assert_eq!(failure(&long), Reply::Failed { error: "x".repeat(200) });
    }
}

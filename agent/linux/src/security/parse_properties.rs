//! Property tests for the parse invariants (docs/security-model.md §3): the same sshd message
//! always parses to the same event, every failed shape carries user and address, and the count
//! semantics match the Attempt kind. Seeded-random over the known shapes.
use super::parse::{parse, Attempt, Parsed};

fn rng(seed: u64) -> impl FnMut() -> u64 {
    let mut state = seed;
    move || {
        state = state.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = state;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^ (z >> 31)
    }
}

/// The failed-login shapes the Linux parser knows, with {user} and {address} slots.
const FAILED_SHAPES: [&str; 4] = [
    "Failed password for {user} from {address} port {port} ssh2",
    "Failed password for invalid user {user} from {address} port {port} ssh2",
    "Invalid user {user} from {address} port {port}",
    "Connection closed by invalid user {user} {address} port {port} [preauth]",
];

fn sshd_line(message: &str) -> String {
    format!("box sshd[123]: {message}")
}

#[test]
fn every_failed_shape_yields_user_and_address() {
    for seed in 1u64..=50 {
        let mut next = rng(seed);
        for shape in FAILED_SHAPES {
            let user = format!("u{}", next() % 1000);
            let address = format!("10.0.{}.{}", next() % 256, next() % 256);
            let port = 1024 + next() % 60000;
            let message = shape
                .replace("{user}", &user)
                .replace("{address}", &address)
                .replace("{port}", &port.to_string());
            let parsed = parse(&sshd_line(&message)).expect("a failed shape must parse");
            match parsed {
                Parsed::Failed { user: got_user, address: got_address, .. } => {
                    assert_eq!(got_user.as_deref(), Some(user.as_str()), "seed {seed} shape {shape}");
                    assert_eq!(got_address.as_deref(), Some(address.as_str()), "seed {seed} shape {shape}");
                }
                other => panic!("seed {seed}: {shape} parsed as {other:?}, not Failed"),
            }
        }
    }
}

#[test]
fn parse_is_deterministic() {
    // Same line, parsed twice: identical result (a parse has no hidden state).
    let message = "Failed password for root from 1.2.3.4 port 22 ssh2";
    let a = parse(&sshd_line(message));
    let b = parse(&sshd_line(message));
    assert_eq!(a, b);
}

#[test]
fn password_try_and_summary_are_distinguished() {
    // "Failed password" is one try; "Invalid user" is a summary of a connection (counted once).
    let try_line = parse(&sshd_line("Failed password for root from 1.2.3.4 port 22 ssh2"));
    let summary = parse(&sshd_line("Invalid user root from 1.2.3.4 port 22"));
    match (try_line, summary) {
        (Some(Parsed::Failed { attempt: Attempt::Try, .. }), Some(Parsed::Failed { attempt: Attempt::Summary, .. })) => {}
        other => panic!("attempt kinds wrong: {other:?}"),
    }
}

#[test]
fn garbage_never_parses_into_an_event() {
    for seed in 1u64..=100 {
        let mut next = rng(seed);
        let junk = format!("zz{} qq{} {}", next() % 9999, next() % 9999, next() % 9999);
        assert!(parse(&junk).is_none(), "junk {junk} parsed");
    }
}

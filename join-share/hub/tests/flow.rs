//! The whole join flow, in process: real routers, fake WireGuard, temp parent
//! database and builds folder, moving clock. No sockets, no sudo, no pf.
use axum::body::Body;
use axum::http::{Method, Request, StatusCode};
use axum::Router;
use http_body_util::BodyExt;
use join_share_hub::clock::Clock;
use join_share_hub::config::Config;
use join_share_hub::crypto::{base64_encode, sha256_hex};
use join_share_hub::peers::FakeWg;
use join_share_hub::state::Shared;
use join_share_hub::{http_admin, http_public, startup, testkit};
use rusqlite::Connection;
use serde_json::{json, Value};
use std::os::unix::fs::PermissionsExt;
use std::path::PathBuf;
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::Arc;
use tower::ServiceExt;

const START: i64 = 1_800_000_000;
const HELPER_BYTES: &[u8] = b"fake helper binary";

struct Harness {
    dir: PathBuf,
    parent_db: PathBuf,
    now: Arc<AtomicI64>,
    wg: Arc<FakeWg>,
    state: Shared,
    public: Router,
    admin: Router,
}

impl Harness {
    fn new() -> Self {
        Self::with_rate_limit(1000)
    }

    fn with_rate_limit(limit: u32) -> Self {
        let (dir, parent_db) = testkit::parent_db();
        let builds = dir.join("builds");
        std::fs::create_dir_all(&builds).unwrap();
        let mac_agent = dir.join("mac-agent");
        for path in [mac_agent.clone(), builds.join("metaservice-agent-linux-x86_64"), builds.join("metaservice-agent-linux-arm64")] {
            std::fs::write(&path, HELPER_BYTES).unwrap();
            std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755)).unwrap();
        }
        let vars = vec![
            ("JOIN_SHARE_ENDPOINT", "mini.example.com:51830".to_string()),
            ("JOIN_SHARE_PUBLIC_URL", "https://join.example.com".to_string()),
            ("JOIN_SHARE_PARENT_DB", parent_db.display().to_string()),
            ("JOIN_SHARE_BUILDS_DIR", builds.display().to_string()),
            ("JOIN_SHARE_MAC_AGENT", mac_agent.display().to_string()),
            ("JOIN_SHARE_STATE", dir.join("state").display().to_string()),
            ("JOIN_SHARE_RATE_LIMIT", limit.to_string()),
        ];
        let config = Config::from_lookup(&|k| vars.iter().find(|(n, _)| *n == k).map(|(_, v)| v.clone())).unwrap();
        let now = Arc::new(AtomicI64::new(START));
        let clock: Clock = {
            let now = now.clone();
            Arc::new(move || now.load(Ordering::SeqCst))
        };
        let wg = Arc::new(FakeWg::default());
        let state = startup::build_state(config, wg.clone(), clock).unwrap();
        let public = http_public::router(state.clone());
        let admin = http_admin::router(state.clone());
        Self { dir, parent_db, now, wg, state, public, admin }
    }

    fn advance(&self, secs: i64) {
        self.now.fetch_add(secs, Ordering::SeqCst);
    }

    async fn public(&self, method: Method, uri: &str, body: Option<Value>) -> (StatusCode, String) {
        send(&self.public, method, uri, None, body).await
    }

    async fn admin(&self, method: Method, uri: &str, body: Option<Value>) -> (StatusCode, String) {
        send(&self.admin, method, uri, Some(self.state.admin_key.as_str()), body).await
    }

    async fn new_link(&self, os: &str, cpu: &str) -> String {
        let (status, body) = self.admin(Method::POST, "/admin/links", Some(json!({"os": os, "cpu": cpu}))).await;
        assert_eq!(status, StatusCode::OK, "{body}");
        parse(&body)["link"].as_str().unwrap().to_string()
    }

    /// Registers a pending mac machine with the given key seed; returns the register reply.
    async fn register(&self, link: &str, seed: u8) -> Value {
        let (status, body) = self.public(Method::POST, &format!("/j/{link}/register"), Some(register_body(seed))).await;
        assert_eq!(status, StatusCode::OK, "{body}");
        parse(&body)
    }

    async fn approve(&self, pending: &Value, code: &str, name: &str) -> (StatusCode, Value) {
        let uri = format!("/admin/pending/{}/approve", pending["pending"].as_str().unwrap());
        let body = json!({"code": code, "name": name, "share": {"cores": 2, "ram_mb": 4096, "disk_gb": 20}});
        let (status, text) = self.admin(Method::POST, &uri, Some(body)).await;
        (status, parse(&text))
    }

    fn status_uri(link: &str, pending: &Value) -> String {
        format!("/j/{link}/status?pending={}&secret={}", pending["pending"].as_str().unwrap(), pending["secret"].as_str().unwrap())
    }
}

impl Drop for Harness {
    fn drop(&mut self) {
        testkit::cleanup(&self.dir);
    }
}

fn parse(text: &str) -> Value {
    serde_json::from_str(text).unwrap_or_else(|_| panic!("not json: {text}"))
}

fn register_body(seed: u8) -> Value {
    json!({
        "wg_public_key": base64_encode(&[seed; 32]), "os": "mac", "cpu": "arm64", "hostname": "far-mac",
        "share": {"cores": 4, "ram_mb": 8192, "disk_gb": 50}
    })
}

async fn send(router: &Router, method: Method, uri: &str, key: Option<&str>, body: Option<Value>) -> (StatusCode, String) {
    let mut builder = Request::builder().method(method).uri(uri);
    if let Some(key) = key {
        builder = builder.header("x-admin-key", key);
    }
    let request = match body {
        Some(json) => builder.header("content-type", "application/json").body(Body::from(json.to_string())),
        None => builder.body(Body::empty()),
    }
    .unwrap();
    let response = router.clone().oneshot(request).await.unwrap();
    let status = response.status();
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    (status, String::from_utf8_lossy(&bytes).to_string())
}

fn enrollment_rows(h: &Harness) -> Vec<(String, String, i64, i64, String)> {
    let conn = Connection::open(&h.parent_db).unwrap();
    let mut stmt = conn.prepare("SELECT token_hash, machine_name, created_at, expires_at, expected_ip FROM enrollments").unwrap();
    let rows = stmt.query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?))).unwrap();
    rows.map(|r| r.unwrap()).collect()
}

#[tokio::test]
async fn whole_flow_from_link_to_removal() {
    let h = Harness::new();
    let link = h.new_link("mac", "arm64").await;

    let (status, script) = h.public(Method::GET, &format!("/j/{link}?os=mac&cpu=arm64"), None).await;
    assert_eq!(status, StatusCode::OK);
    assert!(script.contains(&link));
    assert!(!script.contains("@LINK@") && !script.contains("@PUBLIC_URL@"));

    let reg = h.register(&link, 1).await;
    assert_eq!(reg["code"].as_str().unwrap().len(), 6);
    assert_eq!(reg["expires_in"], 900);

    let (_, text) = h.public(Method::GET, &Harness::status_uri(&link, &reg), None).await;
    assert_eq!(parse(&text), json!({"state": "pending"}));

    // Helper is refused before approval.
    let dl = format!("/dl/darwin-arm64/metaservice-agent?pending={}&secret={}", reg["pending"].as_str().unwrap(), reg["secret"].as_str().unwrap());
    assert_eq!(h.public(Method::GET, &dl, None).await.0, StatusCode::NOT_FOUND);

    // Admin sees it, without the code.
    let (_, text) = h.admin(Method::GET, "/admin/pending", None).await;
    assert!(text.contains("far-mac") && !text.contains(reg["code"].as_str().unwrap()));

    let wrong = if reg["code"] == "000000" { "000001" } else { "000000" };
    let (status, body) = h.approve(&reg, wrong, "my-mac").await;
    assert_eq!((status, body["tries_left"].clone()), (StatusCode::FORBIDDEN, json!(4)));
    assert_eq!(body["error"], "wrong_code");

    let (status, body) = h.approve(&reg, reg["code"].as_str().unwrap(), "my-mac").await;
    assert_eq!((status, body["address"].as_str()), (StatusCode::OK, Some("10.77.0.2")));

    let (_, text) = h.public(Method::GET, &Harness::status_uri(&link, &reg), None).await;
    let approved = parse(&text);
    assert_eq!(approved["state"], "approved");
    let wireguard = &approved["wireguard"];
    assert_eq!(wireguard["address"], "10.77.0.2/32");
    assert_eq!(wireguard["hub_public_key"], h.state.hub_public_key.as_str());
    assert_eq!(wireguard["endpoint"], "mini.example.com:51830");
    assert_eq!((wireguard["allowed_ips"].clone(), wireguard["keepalive"].clone()), (json!("10.77.0.1/32"), json!(25)));
    let machine = &approved["machine"];
    assert_eq!(machine["name"], "my-mac");
    assert_eq!(machine["parent_url"], "http://10.77.0.1:9102");
    // The lowered share (asked 4/8192/50, approved 2/4096/20) is what the status reports.
    assert_eq!(machine["share"], json!({"cores": 2, "ram_mb": 4096, "disk_gb": 20}));
    assert_eq!((machine["helper_bind"].clone(), machine["helper_port"].clone()), (json!("10.77.0.2"), json!(9101)));
    assert_eq!(approved["download"]["sha256"], sha256_hex(HELPER_BYTES).as_str());
    assert_eq!(approved["download"]["url"], format!("https://join.example.com{dl}").as_str());

    // The enrollment row has the hash of the token handed out, pinned to the address.
    let token = machine["enrollment_token"].as_str().unwrap();
    assert_eq!(enrollment_rows(&h), vec![(sha256_hex(token.as_bytes()), "my-mac".into(), START, START + 900, "10.77.0.2".into())]);

    // The token is given once.
    let (_, text) = h.public(Method::GET, &Harness::status_uri(&link, &reg), None).await;
    let again = parse(&text);
    assert_eq!(again["state"], "approved");
    assert!(again["machine"].get("enrollment_token").is_none());
    assert_eq!(again["machine"]["share"], machine["share"]);

    // Download: right pair only.
    let (status, body) = h.public(Method::GET, &dl, None).await;
    assert_eq!((status, body.as_bytes()), (StatusCode::OK, HELPER_BYTES));
    let other = dl.replace("darwin-arm64", "linux-x86_64");
    assert_eq!(h.public(Method::GET, &other, None).await.0, StatusCode::NOT_FOUND);

    // Peers list and removal; the address is free for the next machine.
    let (_, text) = h.admin(Method::GET, "/admin/peers", None).await;
    assert_eq!(parse(&text)[0]["name"], "my-mac");
    assert_eq!(h.wg.peers().len(), 1);
    assert_eq!(h.admin(Method::DELETE, "/admin/peers/my-mac", None).await.0, StatusCode::OK);
    assert!(h.wg.peers().is_empty());
    let second_link = h.new_link("mac", "arm64").await;
    let second = h.register(&second_link, 2).await;
    let (_, body) = h.approve(&second, second["code"].as_str().unwrap(), "other-mac").await;
    assert_eq!(body["address"], "10.77.0.2");
}

#[tokio::test]
async fn unknown_expired_and_used_links_all_give_the_same_404() {
    let h = Harness::new();
    let unknown = h.public(Method::GET, "/j/nope?os=mac&cpu=arm64", None).await;
    assert_eq!((unknown.0, parse(&unknown.1)), (StatusCode::NOT_FOUND, json!({"error": "unknown_link"})));
    let (s, _) = h.public(Method::POST, "/j/nope/register", Some(register_body(1))).await;
    assert_eq!(s, StatusCode::NOT_FOUND);
    assert_eq!(h.public(Method::GET, "/j/nope/status?pending=a&secret=b", None).await.0, StatusCode::NOT_FOUND);

    let expiring = h.new_link("mac", "arm64").await;
    h.advance(901);
    let expired = h.public(Method::GET, &format!("/j/{expiring}?os=mac&cpu=arm64"), None).await;
    assert_eq!((expired.0, parse(&expired.1)), (StatusCode::NOT_FOUND, json!({"error": "unknown_link"})));

    let used = h.new_link("mac", "arm64").await;
    h.register(&used, 1).await;
    let (s, body) = h.public(Method::GET, &format!("/j/{used}?os=mac&cpu=arm64"), None).await;
    assert_eq!((s, parse(&body)), (StatusCode::NOT_FOUND, json!({"error": "unknown_link"})));
    let (s, _) = h.public(Method::POST, &format!("/j/{used}/register"), Some(register_body(2))).await;
    assert_eq!(s, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn wrong_status_secret_is_the_same_404() {
    let h = Harness::new();
    let link = h.new_link("mac", "arm64").await;
    let reg = h.register(&link, 1).await;
    let uri = format!("/j/{link}/status?pending={}&secret=wrong", reg["pending"].as_str().unwrap());
    assert_eq!(h.public(Method::GET, &uri, None).await.0, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn five_wrong_codes_refuse_and_expiry_is_reported() {
    let h = Harness::new();
    let link = h.new_link("mac", "arm64").await;
    let reg = h.register(&link, 1).await;
    let wrong = if reg["code"] == "000000" { "000001" } else { "000000" };
    for left in [4, 3, 2, 1, 0] {
        let (status, body) = h.approve(&reg, wrong, "m").await;
        assert_eq!((status, body["tries_left"].clone()), (StatusCode::FORBIDDEN, json!(left)));
    }
    let (_, text) = h.public(Method::GET, &Harness::status_uri(&link, &reg), None).await;
    assert_eq!(parse(&text), json!({"state": "refused"}));
    let (status, _) = h.approve(&reg, reg["code"].as_str().unwrap(), "m").await;
    assert_eq!(status, StatusCode::CONFLICT);

    let link = h.new_link("mac", "arm64").await;
    let late = h.register(&link, 2).await;
    h.advance(901);
    let (_, text) = h.public(Method::GET, &Harness::status_uri(&link, &late), None).await;
    assert_eq!(parse(&text), json!({"state": "expired"}));
    let (status, _) = h.approve(&late, late["code"].as_str().unwrap(), "m").await;
    assert_eq!(status, StatusCode::GONE);
}

#[tokio::test]
async fn unsupported_pairs_are_400() {
    let h = Harness::new();
    let (s, body) = h.admin(Method::POST, "/admin/links", Some(json!({"os": "windows", "cpu": "x86_64"}))).await;
    assert_eq!((s, parse(&body)["error"].clone()), (StatusCode::BAD_REQUEST, json!("windows_soon")));
    let (s, body) = h.admin(Method::POST, "/admin/links", Some(json!({"os": "mac", "cpu": "x86_64"}))).await;
    assert_eq!((s, parse(&body)["error"].clone()), (StatusCode::BAD_REQUEST, json!("no_build")));
    let (s, _) = h.admin(Method::POST, "/admin/links", Some(json!({"os": "beos", "cpu": "arm64"}))).await;
    assert_eq!(s, StatusCode::BAD_REQUEST);

    // A link for mac/arm64 cannot be used as another pair.
    let link = h.new_link("mac", "arm64").await;
    let (s, _) = h.public(Method::GET, &format!("/j/{link}?os=linux&cpu=x86_64"), None).await;
    assert_eq!(s, StatusCode::BAD_REQUEST);
    let mut body = register_body(1);
    body["os"] = json!("linux");
    body["cpu"] = json!("x86_64");
    let (s, _) = h.public(Method::POST, &format!("/j/{link}/register"), Some(body)).await;
    assert_eq!(s, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn supported_table_lists_states() {
    let h = Harness::new();
    let (s, text) = h.admin(Method::GET, "/admin/supported", None).await;
    let table = parse(&text);
    assert_eq!(s, StatusCode::OK);
    assert_eq!(table[0]["cpus"][0], json!({"cpu": "arm64", "state": "ready"}));
    assert_eq!(table[0]["cpus"][1]["state"], "missing");
    assert_eq!(table[1]["cpus"][0]["state"], "untested");
    assert_eq!(table[1]["cpus"][1]["state"], "ready");
    assert_eq!(table[2]["cpus"][0]["state"], "soon");
}

#[tokio::test]
async fn name_taken_in_hub_or_parent_is_409() {
    let h = Harness::new();
    let first = h.new_link("mac", "arm64").await;
    let reg = h.register(&first, 1).await;
    assert_eq!(h.approve(&reg, reg["code"].as_str().unwrap(), "My-Mac").await.0, StatusCode::OK);

    let second = h.new_link("mac", "arm64").await;
    let reg2 = h.register(&second, 2).await;
    let (status, body) = h.approve(&reg2, reg2["code"].as_str().unwrap(), "my-mac").await;
    assert_eq!((status, body["error"].clone()), (StatusCode::CONFLICT, json!("name_taken")));

    Connection::open(&h.parent_db).unwrap().execute("INSERT INTO machines (id, name) VALUES ('m1', 'Office')", []).unwrap();
    let (status, _) = h.approve(&reg2, reg2["code"].as_str().unwrap(), "office").await;
    assert_eq!(status, StatusCode::CONFLICT);
    // Still pending, so a free name works afterwards.
    assert_eq!(h.approve(&reg2, reg2["code"].as_str().unwrap(), "free-name").await.0, StatusCode::OK);
}

#[tokio::test]
async fn bad_choices_are_400_and_wireguard_failure_leaves_nothing() {
    let h = Harness::new();
    let link = h.new_link("mac", "arm64").await;
    let reg = h.register(&link, 1).await;
    let code = reg["code"].as_str().unwrap();
    assert_eq!(h.approve(&reg, code, "bad name").await.0, StatusCode::BAD_REQUEST);
    let uri = format!("/admin/pending/{}/approve", reg["pending"].as_str().unwrap());
    let too_much = json!({"code": code, "name": "m", "share": {"cores": 64, "ram_mb": 1, "disk_gb": 1}});
    assert_eq!(h.admin(Method::POST, &uri, Some(too_much)).await.0, StatusCode::BAD_REQUEST);

    h.wg.set_fail_add(true);
    assert_eq!(h.approve(&reg, code, "m").await.0, StatusCode::BAD_GATEWAY);
    assert!(enrollment_rows(&h).is_empty());
    h.wg.set_fail_add(false);
    assert_eq!(h.approve(&reg, code, "m").await.0, StatusCode::OK);
}

#[tokio::test]
async fn refuse_marks_refused() {
    let h = Harness::new();
    let link = h.new_link("mac", "arm64").await;
    let reg = h.register(&link, 1).await;
    let uri = format!("/admin/pending/{}/refuse", reg["pending"].as_str().unwrap());
    assert_eq!(h.admin(Method::POST, &uri, None).await.0, StatusCode::OK);
    let (_, text) = h.public(Method::GET, &Harness::status_uri(&link, &reg), None).await;
    assert_eq!(parse(&text), json!({"state": "refused"}));
    assert_eq!(h.admin(Method::POST, "/admin/pending/nope/refuse", None).await.0, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn admin_routes_need_the_key_but_the_page_does_not() {
    let h = Harness::new();
    let routes = [
        (Method::POST, "/admin/links"),
        (Method::GET, "/admin/supported"),
        (Method::GET, "/admin/pending"),
        (Method::POST, "/admin/pending/x/approve"),
        (Method::POST, "/admin/pending/x/refuse"),
        (Method::GET, "/admin/peers"),
        (Method::DELETE, "/admin/peers/x"),
    ];
    for (method, uri) in routes {
        let none = send(&h.admin, method.clone(), uri, None, None).await;
        let wrong = send(&h.admin, method, uri, Some("not-the-key"), None).await;
        assert_eq!((none.0, wrong.0), (StatusCode::UNAUTHORIZED, StatusCode::UNAUTHORIZED), "{uri}");
    }
    for uri in ["/", "/app.js", "/style.css"] {
        assert_eq!(send(&h.admin, Method::GET, uri, None, None).await.0, StatusCode::OK, "{uri}");
    }
}

#[tokio::test]
async fn oversized_bodies_are_refused() {
    let h = Harness::new();
    let link = h.new_link("mac", "arm64").await;
    let mut body = register_body(1);
    body["hostname"] = json!("x".repeat(20 * 1024));
    let (status, _) = h.public(Method::POST, &format!("/j/{link}/register"), Some(body)).await;
    assert_eq!(status, StatusCode::PAYLOAD_TOO_LARGE);
    // The link was not burnt by the refused request.
    assert_eq!(h.public(Method::GET, &format!("/j/{link}?os=mac&cpu=arm64"), None).await.0, StatusCode::OK);
}

#[tokio::test]
async fn rate_limit_is_per_ip() {
    let h = Harness::with_rate_limit(3);
    for _ in 0..3 {
        assert_eq!(h.public(Method::GET, "/j/nope", None).await.0, StatusCode::NOT_FOUND);
    }
    assert_eq!(h.public(Method::GET, "/j/nope", None).await.0, StatusCode::TOO_MANY_REQUESTS);
    // Another client IP (as the tunnel reports it) is not limited; time passing resets.
    let other = Request::builder().uri("/j/nope").header("cf-connecting-ip", "9.9.9.9").body(Body::empty()).unwrap();
    assert_eq!(h.public.clone().oneshot(other).await.unwrap().status(), StatusCode::NOT_FOUND);
    h.advance(61);
    assert_eq!(h.public(Method::GET, "/j/nope", None).await.0, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn start_up_writes_conf_and_keys_with_private_modes() {
    let h = Harness::new();
    startup::bring_up(&h.state).unwrap();
    let state_dir = &h.state.config.state_dir;
    for file in ["admin.key", "hub.key", "wg-metaservice.conf"] {
        let mode = std::fs::metadata(state_dir.join(file)).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o600, "{file}");
    }
    assert_eq!(h.wg.calls(), vec!["down", "up", "pf-load"]);
}

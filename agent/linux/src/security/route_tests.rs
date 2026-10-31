//! Grouping of failed tries, hostile text, and the route through the real axum router.
use super::model::EventType;
use super::tests::{append, failed, iso_line, kinds, some, Rig, NOW};
use super::Security;
use crate::http::{router, App};
use crate::ssh_keys_tests::{service_over, TOKEN};
use axum::body::Body;
use axum::extract::ConnectInfo;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::Value;
use std::net::SocketAddr;
use std::sync::Arc;
use tower::ServiceExt;

// ---- grouping

#[test]
fn one_connection_is_one_try_however_many_lines_it_leaves() {
    let rig = Rig::new();
    let line = |text: &str| format!("{} host sshd[1]: {text}\n", iso_line(NOW - 60));
    append(
        &rig.auth(),
        &line("Invalid user oracle from 203.0.113.5 port 100"),
    );
    append(
        &rig.auth(),
        &line("Failed password for invalid user oracle from 203.0.113.5 port 100 ssh2"),
    );
    append(
        &rig.auth(),
        &line("Connection closed by invalid user oracle 203.0.113.5 port 100 [preauth]"),
    );
    append(
        &rig.auth(),
        &line("Failed password for root from 203.0.113.6 port 200 ssh2"),
    );
    append(
        &rig.auth(),
        &line("Failed password for root from 203.0.113.6 port 200 ssh2"),
    );
    append(
        &rig.auth(),
        &line("Failed password for root from 203.0.113.6 port 200 ssh2"),
    );
    append(
        &rig.auth(),
        &line("Disconnected from authenticating user root 203.0.113.6 port 200 [preauth]"),
    );
    append(&rig.auth(), &line("Unable to negotiate with 203.0.113.7 port 300: no matching key exchange method found. [preauth]"));
    append(&rig.auth(), &line("Unable to negotiate with 203.0.113.7 port 301: no matching key exchange method found. [preauth]"));
    let answer = rig.security().events(None, 500);
    let mut got = kinds(&answer);
    got.sort_by_key(|(_, _, address, _)| address.clone());
    assert_eq!(
        got,
        vec![
            (
                EventType::FailedLogin,
                some("oracle"),
                some("203.0.113.5"),
                1
            ),
            (EventType::FailedLogin, some("root"), some("203.0.113.6"), 3),
            (EventType::FailedLogin, None, some("203.0.113.7"), 2),
        ]
    );
}

#[test]
fn hostile_names_reach_the_parent_clean() {
    let rig = Rig::new();
    append(&rig.auth(), &format!("{} host sshd[1]: Failed password for invalid user {}\u{1b}[31m\u{202e}x from 203.0.113.5 port 1 ssh2\n", iso_line(NOW - 60), "A".repeat(300)));
    let answer = rig.security().events(None, 500);
    let user = answer.events[0].user.clone().unwrap();
    assert_eq!(user.chars().count(), 64);
    assert!(user.chars().all(|c| !c.is_control() && c != '\u{202e}'));
    assert!(answer.events[0].detail.as_deref().unwrap().chars().count() <= 160);
}

// ---- through the real router

async fn get(app: Arc<App>, path: &str, token: &str) -> (StatusCode, Value) {
    let mut request = Request::builder()
        .method("GET")
        .uri(path)
        .header("authorization", format!("Bearer {token}"))
        .body(Body::empty())
        .unwrap();
    request
        .extensions_mut()
        .insert(ConnectInfo(SocketAddr::from(([127, 0, 0, 1], 40000))));
    let response = router(app).oneshot(request).await.unwrap();
    let status = response.status();
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    (
        status,
        serde_json::from_slice(&bytes).unwrap_or(Value::Null),
    )
}

fn app_over(security: Security) -> Arc<App> {
    let engine = Arc::new(crate::engine::SimulatedEngine::new(
        crate::engine::default_capabilities(),
    ));
    let mut app = App::new(service_over(engine), TOKEN.into(), 3, None);
    Arc::get_mut(&mut app)
        .expect("only one holder yet")
        .security = Arc::new(security);
    app
}

#[tokio::test]
async fn the_route_answers_the_contract_and_refuses_bad_input() {
    let rig = Rig::new();
    append(&rig.auth(), &failed(5, "root", "203.0.113.1", 1));
    let app = app_over(rig.security());
    let (status, body) = get(app.clone(), "/v1/security/events", TOKEN).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["reset"], false);
    assert!(body["cursor"].as_str().unwrap().starts_with("v1."));
    let event = &body["events"][0];
    assert_eq!(
        (
            event["type"].clone(),
            event["user"].clone(),
            event["address"].clone(),
            event["count"].clone()
        ),
        (
            "failed_login".into(),
            "root".into(),
            "203.0.113.1".into(),
            1.into()
        )
    );
    assert!(event["method"].is_null() && event["until"].is_null() && event["detail"].is_string());
    for key in [
        "password_login",
        "ban_tool",
        "firewall",
        "auto_updates",
        "starts_after_reboot",
        "pending_updates",
    ] {
        assert!(body["baseline"].get(key).is_some(), "{key}");
    }
    let cursor = body["cursor"].as_str().unwrap().to_string();
    let (_, next) = get(
        app.clone(),
        &format!("/v1/security/events?after={cursor}&limit=1"),
        TOKEN,
    )
    .await;
    assert_eq!(
        (
            next["events"].as_array().unwrap().len(),
            next["reset"].clone()
        ),
        (0, false.into())
    );
    let (status, garbled) = get(app.clone(), "/v1/security/events?after=nonsense", TOKEN).await;
    assert_eq!(
        (
            status,
            garbled["reset"].clone(),
            garbled["events"].as_array().unwrap().len()
        ),
        (StatusCode::OK, true.into(), 1)
    );
    for bad in ["limit=0", "limit=2001", "limit=x", "limit=-3"] {
        let (status, body) = get(app.clone(), &format!("/v1/security/events?{bad}"), TOKEN).await;
        assert_eq!(
            (status, body["error"]["code"].clone()),
            (StatusCode::BAD_REQUEST, "invalid_input".into()),
            "{bad}"
        );
    }
}

#[tokio::test]
async fn the_route_needs_the_token_and_shares_the_lockout() {
    let rig = Rig::new();
    let app = app_over(rig.security());
    for _ in 0..3 {
        assert_eq!(
            get(app.clone(), "/v1/security/events", "wrong").await.0,
            StatusCode::UNAUTHORIZED
        );
    }
    assert_eq!(
        get(app.clone(), "/v1/security/events", TOKEN).await.0,
        StatusCode::TOO_MANY_REQUESTS,
        "three wrong tokens lock the address out"
    );
}

#[tokio::test]
async fn the_facts_say_security_is_served() {
    let rig = Rig::new();
    let (status, facts) = get(app_over(rig.security()), "/v1/facts", TOKEN).await;
    assert_eq!(
        (status, facts["capabilities"]["security"].clone()),
        (StatusCode::OK, true.into())
    );
}

#[test]
fn the_dump_prints_the_route_json_for_given_files() {
    let rig = Rig::new();
    append(&rig.auth(), &failed(5, "root", "203.0.113.1", 1));
    let text = super::dump(rig.auth().to_str().unwrap(), None, 500, true).unwrap();
    let json: Value = serde_json::from_str(&text).unwrap();
    assert_eq!(json["events"][0]["address"], "203.0.113.1");
    assert!(super::dump("/nonexistent/auth.log", None, 500, false).is_err());
}

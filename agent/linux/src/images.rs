//! What `GET /v1/images` answers: which ready-made images this machine has prepared. The stock image needs no preparing, so it is always ready.
//! OpenClaw and Hermes are not prepared images: they are installed inside the VM after it starts (`PUT /v1/workloads/{id}/app`), so they are always ready too.
use serde_json::{json, Value};

/// What the person reads next to an app that is installed after the VM starts.
const APP_CAPTION: &str = "Installs after the VM starts, about 2 minutes";

pub fn prepared() -> Value {
    json!({"images": [
        {"id": "blank", "ready": true, "built_at": null},
        {"id": "openclaw", "ready": true, "built_at": null, "caption": APP_CAPTION},
        {"id": "hermes", "ready": true, "built_at": null, "caption": APP_CAPTION},
    ]})
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_stock_image_is_listed_first_and_it_is_ready() {
        let answer = prepared();
        let images = answer["images"].as_array().unwrap();
        assert_eq!(images[0]["id"], "blank");
        assert_eq!(images[0]["ready"], true);
        assert!(images[0]["built_at"].is_null(), "the stock image has no build time");
        assert_eq!(images[0].as_object().unwrap().len(), 3);
    }

    #[test]
    fn the_two_apps_are_ready_with_the_install_caption() {
        let answer = prepared();
        let images = answer["images"].as_array().unwrap();
        assert_eq!(images.len(), 3);
        for (entry, id) in images[1..].iter().zip(["openclaw", "hermes"]) {
            assert_eq!(entry["id"], id);
            assert_eq!(entry["ready"], true);
            assert_eq!(entry["caption"], "Installs after the VM starts, about 2 minutes");
        }
    }
}

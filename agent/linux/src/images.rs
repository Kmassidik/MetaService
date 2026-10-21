//! What `GET /v1/images` answers: which ready-made images this machine has prepared. Only the stock image exists so far,
//! and it needs no preparing, so the answer is always the same.
use serde_json::{json, Value};

pub fn prepared() -> Value {
    json!({"images": [{"id": "blank", "ready": true, "built_at": null}]})
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_the_stock_image_is_listed_and_it_is_ready() {
        let answer = prepared();
        let images = answer["images"].as_array().unwrap();
        assert_eq!(images.len(), 1);
        assert_eq!(images[0]["id"], "blank");
        assert_eq!(images[0]["ready"], true);
        assert!(images[0]["built_at"].is_null(), "the stock image has no build time");
        assert_eq!(images[0].as_object().unwrap().len(), 3);
    }
}

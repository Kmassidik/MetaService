//! The rules for what the browser may send into a console. Pure: no sockets, no processes.
use serde::Deserialize;

/// The most keystrokes or paste one binary frame may carry.
pub const MAX_INPUT_BYTES: usize = 64 * 1024;
/// The socket accepts frames a little above the cap, so an oversized one reaches our own rule and closes with 1008 rather than the library's 1009.
pub const SOCKET_FRAME_BYTES: usize = MAX_INPUT_BYTES * 2;
pub const MAX_COLS: u16 = 500;
pub const MAX_ROWS: u16 = 300;
pub const START_COLS: u16 = 80;
pub const START_ROWS: u16 = 24;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Size {
    pub cols: u16,
    pub rows: u16,
}

pub const START_SIZE: Size = Size { cols: START_COLS, rows: START_ROWS };

#[derive(Debug, PartialEq, Eq)]
pub enum Input {
    Keys(Vec<u8>),
    Resize(Size),
    /// Too big, malformed or out of range: the console closes with 1008.
    Refused,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct ResizeMessage {
    resize: [i64; 2],
}

pub fn from_binary(bytes: &[u8]) -> Input {
    if bytes.len() > MAX_INPUT_BYTES {
        return Input::Refused;
    }
    Input::Keys(bytes.to_vec())
}

pub fn from_text(text: &str) -> Input {
    if text.len() > MAX_INPUT_BYTES {
        return Input::Refused;
    }
    match serde_json::from_str::<ResizeMessage>(text).ok().and_then(|message| size_in_range(message.resize)) {
        Some(size) => Input::Resize(size),
        None => Input::Refused,
    }
}

fn size_in_range([cols, rows]: [i64; 2]) -> Option<Size> {
    let cols = u16::try_from(cols).ok().filter(|c| (1..=MAX_COLS).contains(c))?;
    let rows = u16::try_from(rows).ok().filter(|r| (1..=MAX_ROWS).contains(r))?;
    Some(Size { cols, rows })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keys_up_to_the_cap_pass_and_one_more_byte_is_refused() {
        assert_eq!(from_binary(&vec![b'a'; MAX_INPUT_BYTES]), Input::Keys(vec![b'a'; MAX_INPUT_BYTES]));
        assert_eq!(from_binary(&vec![b'a'; MAX_INPUT_BYTES + 1]), Input::Refused);
        assert_eq!(from_binary(&[]), Input::Keys(vec![]));
    }

    #[test]
    fn resize_inside_the_bounds_is_accepted_at_both_edges() {
        assert_eq!(from_text(r#"{"resize":[1,1]}"#), Input::Resize(Size { cols: 1, rows: 1 }));
        assert_eq!(from_text(r#"{"resize":[500,300]}"#), Input::Resize(Size { cols: 500, rows: 300 }));
        assert_eq!(from_text(r#"{"resize":[132,43]}"#), Input::Resize(Size { cols: 132, rows: 43 }));
    }

    #[test]
    fn resize_outside_the_bounds_or_malformed_is_refused() {
        let refused = [
            r#"{"resize":[0,24]}"#, r#"{"resize":[80,0]}"#, r#"{"resize":[501,24]}"#, r#"{"resize":[80,301]}"#, r#"{"resize":[-1,24]}"#,
            r#"{"resize":[80]}"#, r#"{"resize":[80,24,1]}"#, r#"{"resize":["80","24"]}"#, r#"{"resize":[80.5,24]}"#, r#"{"resize":[99999999999,24]}"#,
            r#"{"resize":[80,24],"extra":1}"#, r#"{"other":[80,24]}"#, "hello", "", "[80,24]", "null",
        ];
        for text in refused {
            assert_eq!(from_text(text), Input::Refused, "{text}");
        }
    }

    #[test]
    fn an_oversized_text_frame_is_refused() {
        let padding = " ".repeat(MAX_INPUT_BYTES);
        assert_eq!(from_text(&format!(r#"{{"resize":[80,24]}}{padding}"#)), Input::Refused);
    }
}

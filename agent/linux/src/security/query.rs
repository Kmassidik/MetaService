//! The query of `GET /v1/security/events`: `after` (the opaque cursor) and `limit` (1 to 2000, 500 when absent).

pub const DEFAULT_LIMIT: usize = 500;
pub const MAX_LIMIT: usize = 2000;
const REFUSED: &str = "limit must be a whole number from 1 to 2000";

#[derive(Debug, PartialEq, Eq)]
pub struct Query {
    /// None when `after` is absent or empty.
    pub after: Option<String>,
    pub limit: usize,
}

/// `raw` is the text after the `?`. Other parameters are ignored; the first of a repeated one counts.
pub fn parse(raw: Option<&str>) -> Result<Query, &'static str> {
    let (mut after, mut limit) = (None, None);
    for pair in raw.unwrap_or("").split('&') {
        let (key, value) = pair.split_once('=').unwrap_or((pair, ""));
        match key {
            "after" if after.is_none() => after = Some(value),
            "limit" if limit.is_none() => limit = Some(value),
            _ => {}
        }
    }
    Ok(Query {
        after: after.filter(|value| !value.is_empty()).map(str::to_string),
        limit: limit.map_or(Ok(DEFAULT_LIMIT), number)?,
    })
}

fn number(text: &str) -> Result<usize, &'static str> {
    if text.is_empty() || text.len() > 5 || !text.bytes().all(|b| b.is_ascii_digit()) {
        return Err(REFUSED);
    }
    text.parse()
        .ok()
        .filter(|value| (1..=MAX_LIMIT).contains(value))
        .ok_or(REFUSED)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_and_values() {
        assert_eq!(
            parse(None),
            Ok(Query {
                after: None,
                limit: 500
            })
        );
        assert_eq!(
            parse(Some("after=&limit=1")),
            Ok(Query {
                after: None,
                limit: 1
            })
        );
        assert_eq!(
            parse(Some("x=1&after=v1.a-x.f-x&limit=2000")),
            Ok(Query {
                after: Some("v1.a-x.f-x".into()),
                limit: 2000
            })
        );
        assert_eq!(parse(Some("limit=5&limit=9")).unwrap().limit, 5);
    }

    #[test]
    fn a_limit_out_of_range_or_not_a_number_is_refused() {
        for bad in [
            "limit=0",
            "limit=2001",
            "limit=-1",
            "limit=abc",
            "limit=",
            "limit=1.5",
            "limit=%31",
            "limit=99999999999",
            "limit=+5",
        ] {
            assert_eq!(parse(Some(bad)), Err(REFUSED), "{bad}");
        }
    }
}

//! The optional `processes` query of `GET /v1/stats`: `1` or absent lists the top programs, `0` skips the walk through /proc (the costly part).

const PARAMETER: &str = "processes";
const REFUSED: &str = "processes must be 1 or 0";

/// `query` is the raw text after the `?`. Other parameters are ignored; this one must be given once, as exactly `1` or `0`.
pub fn wants_processes(query: Option<&str>) -> Result<bool, &'static str> {
    let mut values = query.unwrap_or("").split('&').filter_map(value_of_parameter);
    let Some(first) = values.next() else { return Ok(true) };
    if values.next().is_some() {
        return Err(REFUSED);
    }
    match first {
        "1" => Ok(true),
        "0" => Ok(false),
        _ => Err(REFUSED),
    }
}

/// `processes=x` gives `x`; `processes` alone gives the empty text; any other key gives nothing.
fn value_of_parameter(pair: &str) -> Option<&str> {
    let (key, value) = pair.split_once('=').unwrap_or((pair, ""));
    (key == PARAMETER).then_some(value)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn no_query_or_another_parameter_keeps_the_list() {
        assert_eq!(wants_processes(None), Ok(true));
        assert_eq!(wants_processes(Some("")), Ok(true));
        assert_eq!(wants_processes(Some("other=0")), Ok(true));
    }

    #[test]
    fn one_and_zero() {
        assert_eq!(wants_processes(Some("processes=1")), Ok(true));
        assert_eq!(wants_processes(Some("processes=0")), Ok(false));
        assert_eq!(wants_processes(Some("a=b&processes=0&c=d")), Ok(false));
    }

    #[test]
    fn anything_else_is_refused() {
        for bad in ["processes=", "processes", "processes=2", "processes=true", "processes=00", "processes=%30", "processes= 0", "processes=0;x"] {
            assert_eq!(wants_processes(Some(bad)), Err(REFUSED), "{bad}");
        }
    }

    #[test]
    fn the_parameter_twice_is_refused() {
        assert!(wants_processes(Some("processes=1&processes=0")).is_err());
        assert!(wants_processes(Some("processes=0&processes=0")).is_err());
    }
}

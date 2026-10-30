//! The narrow root helper. The hub starts it as `sudo -n join-share-root <subcommand> ...`.
use join_share_hub::{root_args, root_run};
use std::process::ExitCode;

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let request = match root_args::parse(&args) {
        Ok(request) => request,
        Err(reason) => {
            eprintln!("join-share-root: refused: {reason}");
            return ExitCode::from(2);
        }
    };
    match root_run::execute(request) {
        Ok(output) => {
            println!("{output}");
            ExitCode::SUCCESS
        }
        Err(reason) => {
            eprintln!("join-share-root: {reason}");
            ExitCode::from(1)
        }
    }
}

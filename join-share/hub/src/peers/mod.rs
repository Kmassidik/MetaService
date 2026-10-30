//! WireGuard side: addresses, config text, and the control trait with its two implementations.
pub mod alloc;
pub mod fake;
pub mod hubconf;
pub mod sudo;
pub mod wg;

pub use alloc::Net;
pub use fake::FakeWg;
pub use wg::{PeerStat, WgControl};

//! Steam for the console, through the Steam client itself.
//!
//! The OS does not replace Steam and never sees an account's password: Steam runs
//! hidden in the background, signed in through its own window, and this crate asks it
//! for the library, hours and achievements, and tells it to install, launch and stop
//! games. It talks to the client's local debugging port (127.0.0.1 only) and runs
//! small scripts inside it; all of those are in [`js`].
//!
//! `ugos-steam` is the command the shell runs. Every command prints JSON.

pub mod cdp;
pub mod error;
pub mod friends;
pub mod host;
pub mod js;
pub mod launch;
pub mod local;
pub mod model;
pub mod say;
pub mod steam;
pub mod task;
pub mod vdf;
pub mod ws;

pub use error::{Error, Result};
pub use steam::Steam;

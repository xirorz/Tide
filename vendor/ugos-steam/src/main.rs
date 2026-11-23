//! `ugos-steam`: what the console's screens run to show and drive Steam.
//!
//! Every command prints one JSON value on standard output. A failure prints
//! `{"error": {"code": "...", "message": "..."}}` and exits with 1; the codes are
//! listed in docs/steam-integration.md.

use clap::{Parser, Subcommand};
use serde_json::{json, Value};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;
use ugos_steam::cdp::DevTools;
use ugos_steam::host::{self, RealHost};
use ugos_steam::launch::{self, Phase};
use ugos_steam::steam::{Patience, Retry, Steam};
use ugos_steam::{js, say, Error};

#[derive(Parser)]
#[command(name = "tide-steam", version, about = "Steam for Tide: library, hours, achievements, installs and launches")]
struct Cli {
    /// The command that starts Steam.
    #[arg(long, global = true, env = "UGOS_STEAM_COMMAND", default_value = "steam")]
    steam_command: String,
    /// Steam's debugging port, on 127.0.0.1 only.
    #[arg(long, global = true, env = "UGOS_STEAM_PORT", default_value_t = 8080)]
    port: u16,
    /// Where the last library and game answers are kept.
    #[arg(long, global = true, env = "UGOS_STEAM_STATE", default_value = "~/.local/state/tide/steam")]
    state: PathBuf,
    /// Steam's own folder, for reading installed games when Steam is not running.
    /// Default: ~/.local/share/Steam, then ~/.steam/steam.
    #[arg(long, global = true, env = "UGOS_STEAM_ROOT")]
    steam_root: Option<PathBuf>,
    /// Seconds Steam's account list must have been waiting before `status` and `start`
    /// say "choose an account". Steam shows that list for a moment while it signs a
    /// remembered account in by itself; until this time has passed the answer is "starting".
    #[arg(long, global = true, env = "UGOS_STEAM_SETTLE", default_value_t = 4.0)]
    settle: f64,
    /// Also print what is going on while a long command runs (start, stop, install,
    /// uninstall, launch --wait): one JSON object per line, each with a `phase` and a
    /// `message` for the screen. The last line is the command's answer.
    #[arg(long, global = true)]
    progress: bool,
    #[command(subcommand)]
    command: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// not-installed, not-running, starting, needs-account-choice, needs-sign-in or ready.
    Status,
    /// Start Steam hidden, with its debugging port on this machine only.
    Start {
        /// Seconds to wait for Steam to answer.
        #[arg(long, default_value_t = 90)]
        wait: u64,
    },
    /// Without an app id: shut Steam down. With one: end that running game.
    Stop {
        appid: Option<u32>,
        /// With an app id: stay until the game has really closed (20 seconds at most).
        #[arg(long)]
        wait: bool,
    },
    /// The accounts Steam remembers on this machine.
    Accounts,
    /// Pick an account in Steam's own account list.
    ChooseAccount { name: String },
    /// Owned games, with hours and cover addresses.
    Library {
        /// Also applications, tools and the like.
        #[arg(long)]
        all: bool,
    },
    /// One game: hours and achievements.
    Game { appid: u32 },
    /// The folders games can be installed to.
    Folders,
    /// Install an owned game with no Steam window.
    Install {
        appid: u32,
        /// Index from `folders`. Default: Steam's default folder.
        #[arg(long)]
        folder: Option<u32>,
        /// Only report the space needed.
        #[arg(long)]
        dry_run: bool,
        /// The player has read and accepted the game's licence agreements (the ones a
        /// first try listed with the code licence-required).
        #[arg(long)]
        accept_licences: bool,
    },
    Uninstall { appid: u32 },
    /// The download queue, with progress and speed.
    Downloads,
    /// Pause all downloads.
    Pause,
    /// Resume downloads.
    Resume,
    /// Start an installed game.
    Launch {
        appid: u32,
        /// Stay until the game has run and closed; ending this command (SIGTERM) ends the
        /// game. Time Steam spends preparing the game (update, first-time setup) is waited out.
        #[arg(long)]
        wait: bool,
        /// With --wait: seconds Steam may spend preparing the game before the launch is
        /// called off.
        #[arg(long, default_value_t = 900)]
        prepare_timeout: u32,
    },
    /// Skip the step a launch is on, like the Skip button in Steam's own launch window.
    /// Only shader processing can be skipped. For the player's press, never automatic.
    LaunchSkip { appid: u32 },
    /// The apps Steam is running now.
    Running,
    /// The signed-in player and their friends: name, picture id, online, away or
    /// offline, and the game being played. In a game first, then online, away, offline.
    Friends {
        /// Instead: which of Steam's fields were found and how many friends had each.
        /// Names of fields and counts only, never a person's name, id or picture.
        #[arg(long)]
        check: bool,
    },
    /// Steam's in-game overlay: status, off or on.
    Overlay { action: OverlayAction },
    /// Steam's toast pop-ups (download finished, friend online, ...): status, off or on.
    ///
    /// WARNING: "off" and "on" change the Steam ACCOUNT's setting, on every computer
    /// where that account is signed in to Steam, not just on this one. Steam keeps this
    /// switch with the account and syncs it. Nothing runs this by itself; only use it
    /// when the player has chosen it.
    Toasts { action: OverlayAction },
    /// The Steam client's version, and the one these commands were checked against.
    Version,
}

#[derive(Clone, Copy, clap::ValueEnum)]
enum OverlayAction {
    Status,
    Off,
    On,
}

static STOP: AtomicBool = AtomicBool::new(false);
/// Set by `launch --wait --progress`: every line printed is one whole JSON object.
static ONE_LINE: AtomicBool = AtomicBool::new(false);

extern "C" fn on_signal(_: libc::c_int) {
    STOP.store(true, Ordering::SeqCst);
}

fn now() -> u64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

/// An error, with what is known about the game it concerns.
struct Failure {
    error: Error,
    appid: Option<u32>,
    name: Option<String>,
}

impl From<Error> for Failure {
    fn from(error: Error) -> Failure {
        Failure { error, appid: None, name: None }
    }
}

/// With --progress: one line saying what is going on now.
fn tell(progress: bool, phase: &str, about: Value) {
    if progress {
        println!("{}", say::with(about, phase));
    }
}

fn run(cli: Cli) -> std::result::Result<Value, Failure> {
    let client = DevTools { port: cli.port };
    let real_host = RealHost { command: cli.steam_command };
    let steam = Steam { client: &client, host: &real_host, state_dir: home_path(cli.state), steam_root: cli.steam_root, now: now(), settle: Duration::from_secs_f64(cli.settle.clamp(0.0, 60.0)) };
    let progress = cli.progress;
    if progress {
        ONE_LINE.store(true, Ordering::SeqCst);
    }
    let status_answer = |report: &ugos_steam::model::StatusReport| say::with(value(report), say::of_status(report.status));
    Ok(match cli.command {
        Cmd::Status => status_answer(&steam.status()?),
        Cmd::Start { wait } => {
            let until = std::time::Instant::now() + Duration::from_secs(wait);
            tell(progress, "starting-steam", json!({}));
            host::start(&real_host, &client, cli.port, Duration::from_secs(wait))?;
            // The port answers a few seconds before Steam knows whether anyone is signed in.
            let mut report = steam.status()?;
            while report.status == ugos_steam::model::Status::Starting && std::time::Instant::now() < until {
                std::thread::sleep(Duration::from_millis(500));
                report = steam.status()?;
            }
            status_answer(&report)
        }
        Cmd::Stop { appid: None, .. } => {
            tell(progress, "stopping-steam", json!({}));
            host::stop(&real_host, &client, Duration::from_secs(60))?;
            status_answer(&steam.status()?)
        }
        Cmd::Stop { appid: Some(appid), wait } => {
            let was_running = steam.stop_app(appid)?;
            let about = json!({ "appid": appid, "was_running": was_running });
            let closed = if was_running && wait {
                tell(progress, "stopping", about.clone());
                Some(steam.wait_until_closed(appid, Duration::from_secs(1), 20)?)
            } else {
                None
            };
            say::with(about, say::of_stop(was_running, closed))
        }
        Cmd::Accounts => json!({ "accounts": steam.accounts()? }),
        Cmd::ChooseAccount { name } => value(&steam.choose_account(&name, 60, Duration::from_millis(500))?),
        Cmd::Library { all } => value(&steam.library(all)?),
        Cmd::Game { appid } => value(&steam.game(appid)?),
        Cmd::Folders => json!({ "folders": steam.folders()? }),
        Cmd::Install { appid, folder, dry_run, accept_licences } => {
            if !dry_run {
                tell(progress, "installing", json!({ "appid": appid }));
            }
            let report = steam.install(appid, folder, dry_run, accept_licences).map_err(|error| Failure { error, appid: Some(appid), name: None })?;
            say::with(value(&report), say::of_install(report.started))
        }
        Cmd::Uninstall { appid } => {
            tell(progress, "removing", json!({ "appid": appid }));
            say::with(json!({ "appid": appid, "name": steam.uninstall(appid)?, "removed": true }), "removed")
        }
        Cmd::Downloads => value(&steam.downloads()?),
        Cmd::Pause => value(&steam.set_downloads(false)?),
        Cmd::Resume => value(&steam.set_downloads(true)?),
        Cmd::Launch { appid, wait, prepare_timeout } => {
            let launched = steam.launch(appid)?;
            let name = launched.name;
            let about = json!({ "appid": appid, "name": name, "launched": true });
            if !wait {
                say::with(about, "preparing")
            } else {
                unsafe {
                    libc::signal(libc::SIGTERM, on_signal as *const () as libc::sighandler_t);
                    libc::signal(libc::SIGINT, on_signal as *const () as libc::sighandler_t);
                }
                let mut on_phase = |phase: &Phase| {
                    if progress {
                        println!("{}", launch::line(phase, appid, &name));
                    }
                };
                // One look a second. 20 s for a game to appear once Steam says it is
                // done preparing, and 20 s for it to go when told.
                let patience = Patience { tick: Duration::from_secs(1), preparing: prepare_timeout, settle: 20, grace: 20 };
                let ended = match steam.wait_for_exit(appid, launched.since, &STOP, patience, &mut on_phase) {
                    Ok(ended) => ended,
                    Err(e) => return Err(Failure { error: e, appid: Some(appid), name: Some(name) }),
                };
                let (phase, ended) = say::of_wait(&ended);
                let mut answer = say::with(about, phase);
                answer["ended"] = json!(ended);
                answer
            }
        }
        Cmd::LaunchSkip { appid } => {
            let task = steam.skip_launch_step(appid).map_err(|error| Failure { error, appid: Some(appid), name: None })?;
            say::with(json!({ "appid": appid, "skipped": true, "task": task }), "preparing")
        }
        Cmd::Friends { check: false } => value(&steam.friends()?),
        Cmd::Friends { check: true } => steam.friends_check()?,
        Cmd::Running => json!({ "running": steam.running()?, "preparing": steam.preparing() }),
        Cmd::Overlay { action } => match action {
            OverlayAction::Status => json!({ "enabled": steam.overlay()? }),
            OverlayAction::Off => value(&steam.set_overlay(false, Retry::DEFAULT)?),
            OverlayAction::On => value(&steam.set_overlay(true, Retry::DEFAULT)?),
        },
        Cmd::Toasts { action } => match action {
            OverlayAction::Status => json!({ "enabled": steam.toasts()? }),
            OverlayAction::Off => value(&steam.set_toasts(false, Retry::DEFAULT)?),
            OverlayAction::On => value(&steam.set_toasts(true, Retry::DEFAULT)?),
        },
        Cmd::Version => {
            let client = match steam.client_version() {
                Ok(v) => v,
                Err(Error::NotRunning) => Value::Null,
                Err(e) => return Err(e.into()),
            };
            json!({ "ugos_steam": env!("CARGO_PKG_VERSION"), "verified_on": js::VERIFIED_ON, "client": client })
        }
    })
}

fn value<T: serde::Serialize>(v: &T) -> Value {
    serde_json::to_value(v).unwrap_or(Value::Null)
}

fn main() {
    let (out, code) = match run(Cli::parse()) {
        Ok(value) => (value, 0),
        Err(Failure { error: e, appid, name }) => {
            let mut out = json!({ "error": { "code": e.code(), "message": e.to_string() } });
            if let Some(appid) = appid {
                out["appid"] = json!(appid);
                out["name"] = json!(name);
            }
            match &e {
                Error::LicenceRequired(licences) => out["error"]["licences"] = json!(licences),
                Error::SettingNotApplied { enabled, attempts, .. } => {
                    out["applied"] = json!(false);
                    out["enabled"] = json!(enabled);
                    out["attempts"] = json!(attempts);
                }
                Error::LaunchFailed { steam_error, detail, task } => {
                    out["steam_error"] = json!(steam_error);
                    out["detail"] = json!(detail);
                    out["task"] = json!(task);
                }
                Error::LaunchDidNotStart { task } | Error::LaunchTimeout { task, .. } => out["task"] = json!(task),
                _ => {}
            }
            if let Some(phase) = say::of_error(&e) {
                out = say::with(out, phase);
            }
            (out, 1)
        }
    };
    if ONE_LINE.load(Ordering::SeqCst) {
        println!("{out}");
    } else {
        println!("{}", serde_json::to_string_pretty(&out).unwrap_or_else(|_| "null".into()));
    }
    std::process::exit(code);
}

/// Tide: "~/…" in --state (and its default) means the home folder.
fn home_path(p: std::path::PathBuf) -> std::path::PathBuf {
    match (p.strip_prefix("~"), std::env::var_os("HOME")) {
        (Ok(rest), Some(home)) => std::path::PathBuf::from(home).join(rest),
        _ => p,
    }
}

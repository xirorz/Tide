//! The commands. Each asks the running Steam client through [`Client`], decides what
//! the answer means, and keeps a copy of slow-changing answers under the state folder.

use crate::cdp::{is_sign_in, Client, SHARED_PAGE};
use crate::error::{Error, Result};
use crate::js;
use crate::local;
use crate::launch::{Phase, Snapshot, Tracker};
use crate::model::*;
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

/// What the commands need to know about this machine besides the Steam client itself.
pub trait Host {
    /// The Steam command exists.
    fn installed(&self) -> bool;
    /// A Steam process is running, whether or not it answers yet.
    fn process_running(&self) -> bool;
}

pub struct Steam<'a> {
    pub client: &'a dyn Client,
    pub host: &'a dyn Host,
    /// Where answers are kept: `library.json` and `games/<appid>.json`.
    pub state_dir: PathBuf,
    /// Steam's own folder, for the local-files fallback. None: look in the usual places.
    pub steam_root: Option<PathBuf>,
    /// Unix time, stamped on what is cached.
    pub now: u64,
    /// How long Steam's account list must have been waiting before it is believed
    /// (see `status`).
    pub settle: Duration,
}

/// Steam's own sign-in state while it waits for the player at its sign-in window.
const WAITING_FOR_PLAYER: i64 = 1;

fn parse<T: DeserializeOwned>(call: &'static str, value: Value) -> Result<T> {
    serde_json::from_value(value).map_err(|e| Error::UnexpectedShape { call, detail: e.to_string() })
}

#[derive(Deserialize)]
struct State {
    #[serde(default)]
    login_state: Option<i64>,
    /// Milliseconds the client has been seen waiting for the player; None when not waiting.
    #[serde(default)]
    waiting_ms: Option<u64>,
    account: String,
    apps: u64,
    collections: bool,
    #[serde(default)]
    settings: bool,
}

#[derive(Deserialize)]
struct SettingValue {
    loaded: bool,
    value: Option<bool>,
}

#[derive(Deserialize)]
struct Skipped {
    skipped: bool,
    #[serde(default)]
    task: Option<String>,
}

#[derive(Deserialize)]
struct Launching {
    owned: bool,
    #[serde(default)]
    installed: bool,
    #[serde(default)]
    name: String,
    #[serde(default)]
    since: u64,
}

/// A launch that has been asked for: the game's name, and the number of Steam's last
/// game-action event before it, so this launch's events can be told from older ones.
#[derive(Debug, Clone, PartialEq)]
pub struct Launched {
    pub name: String,
    pub since: u64,
}

/// How often and how long to look while a setting settles.
#[derive(Debug, Clone, Copy)]
pub struct Retry {
    /// Rounds of "send if needed, then read back".
    pub rounds: u32,
    /// Matching reads in a row that count as "it stuck".
    pub hold: u32,
    /// Time between reads.
    pub tick: Duration,
}

impl Retry {
    /// At most 10 rounds of up to 3 reads one second apart: about 40 seconds at worst.
    pub const DEFAULT: Retry = Retry { rounds: 10, hold: 3, tick: Duration::from_secs(1) };
}

/// How long to wait at each stage of a launch, in looks `tick` apart.
#[derive(Debug, Clone, Copy)]
pub struct Patience {
    pub tick: Duration,
    /// Looks Steam may spend preparing (update, first-time setup) before the launch is called off.
    pub preparing: u32,
    /// Looks with nothing happening before deciding the game is not coming.
    pub settle: u32,
    /// Looks a game gets to close after being told to.
    pub grace: u32,
}

#[derive(Deserialize)]
struct SignInPage {
    inputs: u64,
}

#[derive(Deserialize)]
struct RawGame {
    appid: u32,
    name: String,
    #[serde(rename = "type")]
    app_type: u64,
    installed: bool,
    size_on_disk: u64,
    minutes_played: u64,
    last_played: u64,
    cover: Option<String>,
    icon: Option<String>,
    #[serde(default)]
    installed_elsewhere: Vec<String>,
    #[serde(default)]
    in_games: bool,
}

impl RawGame {
    /// `on_disk`: the app ids with a finished appmanifest in Steam's library folders,
    /// when those could be read. That decides "installed on this device"; what the
    /// client says is only used when the folders cannot be looked at.
    fn game(self, on_disk: Option<&HashSet<u32>>) -> Game {
        let installed = on_disk.map(|ids| ids.contains(&self.appid)).unwrap_or(self.installed);
        Game {
            appid: self.appid,
            name: self.name,
            kind: kind_of(self.app_type).into(),
            installed,
            installed_elsewhere: self.installed_elsewhere,
            size_on_disk: if installed { self.size_on_disk } else { 0 },
            minutes_played: self.minutes_played,
            last_played: self.last_played,
            cover: self.cover,
            icon: self.icon,
        }
    }
}

#[derive(Deserialize)]
struct RawLibrary {
    account: String,
    /// Steam's library folders, as the client lists them.
    #[serde(default)]
    folders: Vec<String>,
    games: Vec<RawGame>,
}

/// The library as kept on disk: everything owned, with Steam's own "is a game" mark.
#[derive(Serialize, Deserialize)]
struct CachedLibrary {
    fetched_at: u64,
    account: String,
    apps: Vec<CachedApp>,
}

#[derive(Serialize, Deserialize)]
struct CachedApp {
    #[serde(flatten)]
    game: Game,
    in_games: bool,
}

#[derive(Deserialize)]
struct RawDetails {
    owned: bool,
    #[serde(default)]
    folders: Vec<String>,
    overview: Option<RawGame>,
    achievements: Option<Vec<Achievement>>,
}

#[derive(Deserialize, Default)]
struct InstallInfo {
    #[serde(default)]
    state: u64,
    #[serde(default)]
    needed: u64,
    #[serde(default)]
    free: u64,
    #[serde(default)]
    folder: u32,
    #[serde(default)]
    error: i64,
    #[serde(default)]
    error_detail: String,
}

/// What the two install scripts answer; `install_size` fills only the first half.
#[derive(Deserialize)]
struct Installing {
    owned: bool,
    #[serde(default)]
    installed: bool,
    #[serde(default = "yes")]
    folder_exists: bool,
    #[serde(default)]
    loaded: bool,
    #[serde(default)]
    name: String,
    #[serde(default)]
    dialog_title: Option<String>,
    #[serde(default)]
    info: InstallInfo,
    #[serde(default = "yes")]
    quiet: bool,
    /// "no-space", "licence" or "attention" when the script stopped and cancelled.
    #[serde(default)]
    stopped: Option<String>,
    #[serde(default)]
    licences: Vec<Licence>,
    #[serde(default)]
    started: bool,
    #[serde(default)]
    states: Vec<u64>,
}

fn yes() -> bool {
    true
}

#[derive(Deserialize)]
struct Owned {
    owned: bool,
    #[serde(default)]
    installed: bool,
    #[serde(default)]
    removed: bool,
    #[serde(default)]
    name: String,
}

#[derive(Debug, PartialEq)]
pub enum Ended {
    /// The game was seen running and then went away by itself.
    Exited,
    /// We were told to stop it, and it went.
    Stopped,
    /// We were told to stop it and it is still there after the grace time.
    StillRunning,
}

fn write_atomically(path: &Path, text: &str) -> Result<()> {
    let io = |source| Error::Io { path: path.to_path_buf(), source };
    if let Some(dir) = path.parent() {
        fs::create_dir_all(dir).map_err(io)?;
    }
    let tmp = path.with_extension("json.tmp");
    fs::write(&tmp, text).map_err(io)?;
    fs::rename(&tmp, path).map_err(io)
}

fn read_json<T: DeserializeOwned>(path: &Path) -> Option<T> {
    serde_json::from_str(&fs::read_to_string(path).ok()?).ok()
}

impl Steam<'_> {
    pub fn status(&self) -> Result<StatusReport> {
        let report = |status| StatusReport { status, account: None, persona: None, settings_loaded: None, preparing: Vec::new() };
        let pages = match self.client.pages() {
            Ok(pages) => pages,
            Err(Error::NotRunning) => {
                return Ok(report(if self.host.process_running() {
                    Status::Starting
                } else if self.host.installed() {
                    Status::NotRunning
                } else {
                    Status::NotInstalled
                }))
            }
            Err(e) => return Err(e),
        };
        if !pages.iter().any(|p| p == SHARED_PAGE) {
            return Ok(report(Status::Starting));
        }
        // A page can go away between listing and asking while Steam starts; that is "starting".
        let soft = |e: &Error| matches!(e, Error::NotReady(_) | Error::NoAccountChoice | Error::Timeout(_) | Error::Connection { .. } | Error::NotRunning);
        let state: State = match self.client.run(&js::state()) {
            Ok(v) => parse("state", v)?,
            Err(e) if soft(&e) => return Ok(report(Status::Starting)),
            Err(e) => return Err(e),
        };
        if !state.account.is_empty() && state.collections && state.apps > 0 {
            let persona = self.accounts().ok().and_then(|all| all.into_iter().find(|a| a.account == state.account)).map(|a| a.persona);
            return Ok(StatusReport { status: Status::Ready, account: Some(state.account), persona, settings_loaded: Some(state.settings), preparing: self.preparing() });
        }
        if !pages.iter().any(|p| is_sign_in(p)) {
            return Ok(report(Status::Starting));
        }
        let page: SignInPage = match self.client.run(&js::sign_in_page()) {
            Ok(v) => parse("sign_in_page", v)?,
            Err(e) if soft(&e) => return Ok(report(Status::Starting)),
            Err(e) => return Err(e),
        };
        // The account list has no text fields; the form for name and password does.
        let saved = if page.inputs == 0 { self.accounts().map(|a| a.len()).unwrap_or(0) } else { 0 };
        if saved == 0 {
            // Nothing to sign in with by itself: this is final at once.
            return Ok(report(Status::NeedsSignIn));
        }
        // The account list is also on screen for a few seconds while Steam signs a
        // remembered account in by itself, so seeing it is not enough.
        // 1. Steam's sign-in state says whether it is waiting for the player or busy
        //    signing in. Busy: still starting.
        if state.login_state.is_some_and(|s| s != WAITING_FOR_PLAYER) {
            return Ok(report(Status::Starting));
        }
        // 2. Before an automatic sign-in begins, Steam is briefly in the waiting state
        //    too, and nothing recorded tells that moment from a real wait. So the wait
        //    has to have lasted `settle` before it is reported. When the time is not
        //    known (the mark could not be kept), the list is taken at its word.
        if state.waiting_ms.is_some_and(|ms| u128::from(ms) < self.settle.as_millis()) {
            return Ok(report(Status::Starting));
        }
        Ok(report(Status::NeedsAccountChoice))
    }

    fn require_ready(&self) -> Result<StatusReport> {
        let report = self.status()?;
        match report.status {
            Status::Ready => Ok(report),
            Status::NotInstalled => Err(Error::NotInstalled("steam".into())),
            Status::NotRunning => Err(Error::NotRunning),
            Status::Starting => Err(Error::NotReady("it is still starting".into())),
            Status::NeedsAccountChoice => Err(Error::NotReady("an account has to be chosen first".into())),
            Status::NeedsSignIn => Err(Error::NotReady("someone has to sign in first".into())),
        }
    }

    pub fn accounts(&self) -> Result<Vec<Account>> {
        parse("accounts", self.client.run(&js::accounts())?)
    }

    /// Presses the account in Steam's list. `name` is the account name, or the display
    /// name when only one saved account has it. Returns once Steam has moved on.
    pub fn choose_account(&self, name: &str, patience: u32, tick: Duration) -> Result<StatusReport> {
        let now = self.status()?;
        match now.status {
            Status::NeedsAccountChoice => {}
            Status::Ready if now.account.as_deref() == Some(name) || now.persona.as_deref() == Some(name) => return Ok(now),
            _ => return Err(Error::NoAccountChoice),
        }
        let accounts = self.accounts()?;
        let by_persona: Vec<&Account> = accounts.iter().filter(|a| a.persona == name).collect();
        let account = match accounts.iter().find(|a| a.account == name) {
            Some(a) => a,
            None if by_persona.len() == 1 => by_persona[0],
            None => return Err(Error::AccountNotFound(name.into())),
        };
        let pressed = self.client.run(&js::choose_account(&account.account))?;
        if pressed["found"] != true {
            return Err(Error::AccountNotFound(name.into()));
        }
        let mut report = self.status()?;
        for _ in 0..patience {
            if !matches!(report.status, Status::NeedsAccountChoice | Status::Starting) {
                break;
            }
            std::thread::sleep(tick);
            report = self.status()?;
        }
        Ok(report)
    }

    fn library_file(&self) -> PathBuf {
        self.state_dir.join("library.json")
    }

    fn game_file(&self, appid: u32) -> PathBuf {
        self.state_dir.join("games").join(format!("{appid}.json"))
    }

    /// Owned games. Fresh from Steam when it is ready; otherwise what it said last
    /// time, marked stale; otherwise the installed games found in Steam's files.
    pub fn library(&self, include_all: bool) -> Result<Library> {
        let pick = |cached: CachedLibrary, source: &str, stale| Library {
            source: source.into(),
            stale,
            fetched_at: cached.fetched_at,
            account: cached.account,
            games: cached.apps.into_iter().filter(|a| include_all || a.in_games).map(|a| a.game).collect(),
        };
        if self.status()?.status == Status::Ready {
            let raw: RawLibrary = parse("library", self.client.run(&js::library())?)?;
            let on_disk = local::installed_ids(&raw.folders);
            let cached = CachedLibrary {
                fetched_at: self.now,
                account: raw.account,
                apps: raw.games.into_iter().map(|g| CachedApp { in_games: g.in_games, game: g.game(on_disk.as_ref()) }).collect(),
            };
            // A cache that cannot be written (read-only disk, tests) does not spoil the answer.
            let _ = write_atomically(&self.library_file(), &serde_json::to_string(&cached).unwrap_or_default());
            return Ok(pick(cached, "steam", false));
        }
        if let Some(cached) = read_json::<CachedLibrary>(&self.library_file()) {
            return Ok(pick(cached, "cache", true));
        }
        let games = local::steam_root(self.steam_root.as_deref()).map(|root| local::installed_games(&root, include_all)).unwrap_or_default();
        Ok(Library { source: "local-files".into(), stale: true, fetched_at: 0, account: String::new(), games })
    }

    pub fn game(&self, appid: u32) -> Result<GameDetails> {
        let details = |source: &str, stale, fetched_at, game: Game, achievements: Option<Vec<Achievement>>| GameDetails {
            source: source.into(),
            stale,
            fetched_at,
            hours_played: (game.minutes_played as f64 / 6.0).round() / 10.0,
            achievements_unlocked: achievements.as_ref().map(|a| a.iter().filter(|x| x.unlocked).count()).unwrap_or(0),
            achievements_total: achievements.as_ref().map(|a| a.len()).unwrap_or(0),
            game,
            achievements,
        };
        let status = self.status()?;
        if status.status == Status::Ready {
            let raw: RawDetails = parse("game", self.client.run(&js::game(appid))?)?;
            let Some(overview) = raw.overview.filter(|_| raw.owned) else { return Err(Error::NotOwned(appid)) };
            let on_disk = local::installed_ids(&raw.folders);
            let answer = details("steam", false, self.now, overview.game(on_disk.as_ref()), raw.achievements);
            let _ = write_atomically(&self.game_file(appid), &serde_json::to_string(&answer).unwrap_or_default());
            return Ok(answer);
        }
        if let Some(mut cached) = read_json::<GameDetails>(&self.game_file(appid)) {
            cached.source = "cache".into();
            cached.stale = true;
            return Ok(cached);
        }
        // Never opened before: the library copy still has its name, hours and cover.
        if let Some(app) = read_json::<CachedLibrary>(&self.library_file()).and_then(|l| l.apps.into_iter().find(|a| a.game.appid == appid)) {
            return Ok(details("cache", true, 0, app.game, None));
        }
        Err(match status.status {
            Status::NotInstalled => Error::NotInstalled("steam".into()),
            Status::NotRunning => Error::NotRunning,
            _ => Error::NotReady("and nothing is kept about this game yet".into()),
        })
    }

    pub fn folders(&self) -> Result<Vec<Folder>> {
        self.require_ready()?;
        parse("folders", self.client.run(&js::folders())?)
    }

    /// Hands an owned game to Steam's download queue, with no Steam window. With
    /// `dry_run` it only asks how much space is needed.
    ///
    /// A game with licence agreements is not installed unless `licences_accepted` is
    /// set: the first try fails with the list, the screen shows the texts, and only the
    /// player's yes brings the second call with the flag.
    pub fn install(&self, appid: u32, folder: Option<u32>, dry_run: bool, licences_accepted: bool) -> Result<InstallReport> {
        self.require_ready()?;
        let done: Installing = if dry_run {
            parse("install_size", self.client.run(&js::install_size(appid, folder))?)?
        } else {
            parse("install", self.client.run(&js::install(appid, folder, licences_accepted))?)?
        };
        if !done.owned {
            return Err(Error::NotOwned(appid));
        }
        if done.installed {
            return Err(Error::AlreadyInstalled(appid));
        }
        if !done.folder_exists {
            return Err(Error::NoSuchFolder(folder.unwrap_or(0)));
        }
        let info = done.info;
        if !done.loaded {
            let why = if info.error_detail.is_empty() { install_state(info.state).to_string() } else { info.error_detail };
            return Err(Error::InstallFailed(format!("Steam's install manager did not take the game ({why})")));
        }
        if info.needed > info.free || done.stopped.as_deref() == Some("no-space") {
            return Err(Error::NoSpace { needed: info.needed, free: info.free });
        }
        let report = |started| InstallReport { appid, name: done.name.clone(), folder: info.folder, bytes_needed: info.needed, bytes_free: info.free, started, quiet: done.quiet, dialog_title: done.dialog_title.clone() };
        if dry_run {
            return Ok(report(false));
        }
        match (done.stopped.as_deref(), info.state) {
            // Asked for before anything was started, or Steam asked after all.
            (Some("licence"), _) if !licences_accepted && !done.licences.is_empty() => Err(Error::LicenceRequired(done.licences)),
            (Some(_), state) => Err(Error::InstallNeedsAttention(install_state(state).into())),
            (None, _) if !done.started => Err(Error::InstallFailed("the install manager lost the game before it could start".into())),
            // Done: the manager emptied itself (0) or says complete (14).
            (None, 0 | 14) => Ok(report(true)),
            (None, state @ (15 | 16)) => Err(Error::InstallFailed(if info.error_detail.is_empty() {
                format!("{} (Steam error {})", install_state(state), info.error)
            } else {
                info.error_detail.clone()
            })),
            // Still creating or fetching app information: it is under way.
            (None, 9) => Ok(report(true)),
            (None, _) if done.states.len() > 1 => Ok(report(true)),
            (None, state) => Err(Error::InstallFailed(format!("the install manager stayed at \"{}\"", install_state(state)))),
        }
    }

    pub fn uninstall(&self, appid: u32) -> Result<String> {
        self.require_ready()?;
        let done: Owned = parse("uninstall", self.client.run(&js::uninstall(appid))?)?;
        match done {
            Owned { owned: false, .. } => Err(Error::NotOwned(appid)),
            Owned { installed: false, .. } => Err(Error::AppNotInstalled(appid)),
            Owned { removed: false, .. } => Err(Error::Timeout("the game to be removed".into())),
            Owned { name, .. } => Ok(name),
        }
    }

    pub fn downloads(&self) -> Result<Downloads> {
        self.require_ready()?;
        parse("downloads", self.client.run(&js::downloads())?)
    }

    pub fn set_downloads(&self, on: bool) -> Result<Downloads> {
        self.require_ready()?;
        self.client.run(&js::enable_downloads(on))?;
        self.downloads()
    }

    /// Presses Play. The game itself appears later; `wait_for_exit` follows it.
    pub fn launch(&self, appid: u32) -> Result<Launched> {
        self.require_ready()?;
        let asked: Launching = parse("launch", self.client.run(&js::launch(appid))?)?;
        match asked {
            Launching { owned: false, .. } => Err(Error::NotOwned(appid)),
            Launching { installed: false, .. } => Err(Error::AppNotInstalled(appid)),
            Launching { name, since, .. } => Ok(Launched { name, since }),
        }
    }

    /// The signed-in player and their friends, in the order the console lists them.
    pub fn friends(&self) -> Result<crate::friends::Friends> {
        self.require_ready()?;
        let raw: crate::friends::RawFriends = parse("friends", self.client.run(&js::friends(crate::friends::fields()))?)?;
        Ok(crate::friends::shape(&raw))
    }

    /// Where the friends fields were found and how many friends had each: names and
    /// counts only, for correcting `friends::fields()` after a Steam update.
    pub fn friends_check(&self) -> Result<Value> {
        self.require_ready()?;
        self.client.run(&js::friends_check(crate::friends::fields()))
    }

    pub fn running(&self) -> Result<Vec<RunningApp>> {
        self.require_ready()?;
        parse("running", self.client.run(&js::running())?)
    }

    /// Games Steam is in the middle of starting. Empty when that cannot be asked: it is
    /// extra information and never a reason for `status` or `running` to fail.
    pub fn preparing(&self) -> Vec<PreparingApp> {
        self.client.run(&js::activity()).ok().and_then(|v| serde_json::from_value(v).ok()).unwrap_or_default()
    }

    /// Asks Steam to end a running app. False when it was not running.
    pub fn stop_app(&self, appid: u32) -> Result<bool> {
        self.require_ready()?;
        Ok(self.client.run(&js::stop_app(appid))?["running"] == true)
    }

    /// After `stop_app`: looks until the app is no longer running. False when it is
    /// still there after `grace` looks.
    pub fn wait_until_closed(&self, appid: u32, tick: Duration, grace: u32) -> Result<bool> {
        for _ in 0..grace {
            if !self.running()?.iter().any(|a| a.appid == appid) {
                return Ok(true);
            }
            std::thread::sleep(tick);
        }
        Ok(!self.running()?.iter().any(|a| a.appid == appid))
    }

    /// After `launch`: follows the game through Steam's own launch events until it has
    /// run and closed. While Steam is preparing it (an update, first-time setup such as
    /// creating the Proton prefix) this keeps waiting, however often the app flickers
    /// in and out of the running list. `on_phase` is told each time the phase changes.
    ///
    /// When `stop` becomes true the launch is called off or the game asked to close.
    /// A launch Steam cannot complete is an error: `launch-failed` with Steam's error,
    /// `launch-did-not-start`, or `launch-timeout` when Steam is still preparing after
    /// `patience.preparing` looks (the launch is then cancelled).
    pub fn wait_for_exit(&self, appid: u32, since: u64, stop: &AtomicBool, patience: Patience, on_phase: &mut dyn FnMut(&Phase)) -> Result<Ended> {
        let mut tracker = Tracker::new(appid, since, patience.settle);
        let look = |tracker: &mut Tracker| -> Result<Phase> {
            let snapshot: Snapshot = parse("launch_state", self.client.run(&js::launch_state(appid, since))?)?;
            Ok(tracker.see(&snapshot))
        };
        let mut last: Option<Phase> = None;
        let mut preparing = 0u32;
        loop {
            if stop.load(Ordering::SeqCst) {
                // "Closing the game", until it has really gone.
                on_phase(&Phase::Stopping);
                self.client.run(&js::cancel_launch(appid, tracker.action()))?;
                for _ in 0..patience.grace {
                    std::thread::sleep(patience.tick);
                    look(&mut tracker)?;
                    // Called off before it ran, or closed: either way nothing is left.
                    if tracker.gone() {
                        return Ok(Ended::Stopped);
                    }
                }
                return Ok(Ended::StillRunning);
            }
            let phase = look(&mut tracker)?;
            if last.as_ref() != Some(&phase) {
                on_phase(&phase);
                last = Some(phase.clone());
            }
            match phase {
                Phase::Running | Phase::Stopping => {}
                Phase::Ended => return Ok(Ended::Exited),
                Phase::Failed { steam_error: None, detail: None, task } => return Err(Error::LaunchDidNotStart { task }),
                Phase::Failed { steam_error, detail, task } => return Err(Error::LaunchFailed { steam_error, detail, task }),
                Phase::Starting => {}
                Phase::Preparing { task, .. } | Phase::NeedsAttention { task } => {
                    preparing += 1;
                    if preparing > patience.preparing {
                        self.client.run(&js::cancel_launch(appid, tracker.action()))?;
                        return Err(Error::LaunchTimeout { seconds: (patience.tick.as_secs_f64() * patience.preparing as f64).round() as u64, task });
                    }
                }
            }
            std::thread::sleep(patience.tick);
        }
    }

    /// Skips the step a launch is on, the way the Skip button in Steam's own launch
    /// window does. Only for a step that can be skipped (shader processing); anything
    /// else is `nothing-to-skip` and Steam is not asked. Returns the step's name.
    /// Never called by anything but the player's own press.
    pub fn skip_launch_step(&self, appid: u32) -> Result<String> {
        self.require_ready()?;
        let skipped: Skipped = parse("launch_skip", self.client.run(&js::launch_skip(appid))?)?;
        match skipped {
            Skipped { skipped: true, task, .. } => Ok(task.unwrap_or_default()),
            Skipped { task, .. } => Err(Error::NothingToSkip { task: task.filter(|t| !t.is_empty()) }),
        }
    }

    /// A setting as the client has it now. None while the account's settings have not
    /// reached the client yet (a moment after sign-in).
    fn read_setting(&self, setting: &js::BoolSetting) -> Result<Option<bool>> {
        let now: SettingValue = parse("setting", self.client.run(&js::setting_read(setting))?)?;
        Ok(now.value.filter(|_| now.loaded))
    }

    fn setting(&self, setting: &js::BoolSetting) -> Result<bool> {
        self.require_ready()?;
        self.read_setting(setting)?.ok_or_else(|| Error::NotReady("its settings are not loaded yet".into()))
    }

    /// Sets a setting and makes sure it stays set. Each round: wait until the client
    /// has the setting at all; send the value unless it already has it; then read it
    /// back `hold` times, `tick` apart. Only an unbroken run of matching reads counts,
    /// because settings that arrive late from the account (after sign-in) overwrite
    /// what was sent before them. Returns the value last read and the number of sends;
    /// `SettingNotApplied` when the rounds are used up.
    fn apply_setting(&self, setting: &js::BoolSetting, value: bool, retry: Retry) -> Result<(bool, u32)> {
        self.require_ready()?;
        let mut sends = 0;
        let mut last = None;
        for _ in 0..retry.rounds {
            last = self.read_setting(setting)?;
            if last.is_none() {
                std::thread::sleep(retry.tick);
                continue;
            }
            if last != Some(value) {
                self.client.run(&js::setting_send(setting, value))?;
                sends += 1;
            }
            let mut held = true;
            for _ in 0..retry.hold {
                std::thread::sleep(retry.tick);
                last = self.read_setting(setting)?;
                if last != Some(value) {
                    held = false;
                    break;
                }
            }
            if held {
                return Ok((value, sends));
            }
        }
        Err(Error::SettingNotApplied { name: setting.name, enabled: last, attempts: sends })
    }

    /// Steam's in-game overlay: is it on.
    pub fn overlay(&self) -> Result<bool> {
        self.setting(&js::OVERLAY)
    }

    pub fn set_overlay(&self, on: bool, retry: Retry) -> Result<Applied> {
        let (enabled, attempts) = self.apply_setting(&js::OVERLAY, on, retry)?;
        Ok(Applied { enabled, applied: true, attempts })
    }

    /// Steam's toast pop-ups: are they on. (Steam's own setting is "disable all toasts".)
    pub fn toasts(&self) -> Result<bool> {
        Ok(!self.setting(&js::NO_TOASTS)?)
    }

    /// Note: this setting belongs to the account, not the computer (see `js::NO_TOASTS`).
    pub fn set_toasts(&self, on: bool, retry: Retry) -> Result<Applied> {
        match self.apply_setting(&js::NO_TOASTS, !on, retry) {
            Ok((disabled, attempts)) => Ok(Applied { enabled: !disabled, applied: true, attempts }),
            // Reported in the command's sense: "enabled" is toasts on.
            Err(Error::SettingNotApplied { name, enabled, attempts }) => Err(Error::SettingNotApplied { name, enabled: enabled.map(|disabled| !disabled), attempts }),
            Err(e) => Err(e),
        }
    }

    pub fn client_version(&self) -> Result<Value> {
        self.client.run(&js::client_version())
    }
}

//! What the commands print. Field names here are the JSON the shell reads.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum Status {
    NotInstalled,
    NotRunning,
    Starting,
    NeedsAccountChoice,
    NeedsSignIn,
    Ready,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct StatusReport {
    pub status: Status,
    /// The signed-in account's name and display name, when ready.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub account: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub persona: Option<String>,
    /// When ready: the account's settings have reached the client, so `overlay` and
    /// `toasts` can be read. They come a moment after sign-in.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub settings_loaded: Option<bool>,
    /// Games Steam is getting ready to start right now (updating, first-time setup).
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub preparing: Vec<PreparingApp>,
}

/// A game Steam is in the middle of starting.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PreparingApp {
    pub appid: u32,
    pub name: String,
    /// Steam's name for what it is doing with the game ("LaunchApp"), and for the step.
    pub action: Option<String>,
    pub task: Option<String>,
}

/// The outcome of asking for a setting.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Applied {
    /// The value read back at the end, in the command's own sense (overlay on, toasts on).
    pub enabled: bool,
    /// The value asked for was read back, several times in a row.
    pub applied: bool,
    /// How many times the setting had to be sent; 0 when it already had the value.
    pub attempts: u32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Account {
    pub account: String,
    pub persona: String,
    /// Steam can sign this account in without asking for its password.
    pub remembered: bool,
    pub last_login: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Game {
    pub appid: u32,
    pub name: String,
    /// game, application, tool, demo or other.
    pub kind: String,
    /// Installed on this device. A game that is only on another computer is false here.
    pub installed: bool,
    /// Names of other computers of the same account, found on the network, that have
    /// the game installed (Steam can stream from them). Empty for none. A name can be
    /// empty when Steam does not give one.
    #[serde(default)]
    pub installed_elsewhere: Vec<String>,
    /// Bytes; 0 when not installed.
    pub size_on_disk: u64,
    pub minutes_played: u64,
    /// Unix time; 0 when never played.
    pub last_played: u64,
    /// Portrait cover (600x900) and small icon: web addresses, or a local file path
    /// when the entry comes from Steam's files on disk.
    pub cover: Option<String>,
    pub icon: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Library {
    /// steam: fresh from the running client. cache: what the client said last time.
    /// local-files: installed games only, read from Steam's files.
    pub source: String,
    pub stale: bool,
    /// Unix time the list was fetched from Steam; 0 for local-files.
    pub fetched_at: u64,
    pub account: String,
    pub games: Vec<Game>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Achievement {
    pub id: String,
    pub name: String,
    pub description: String,
    pub icon: Option<String>,
    pub unlocked: bool,
    /// Unix time; 0 when locked.
    pub unlocked_at: u64,
    /// Share of all players who have it, 0 to 100.
    pub global_percent: f64,
    pub hidden: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct GameDetails {
    pub source: String,
    pub stale: bool,
    pub fetched_at: u64,
    pub game: Game,
    pub hours_played: f64,
    /// None when Steam gave no achievement list (and for a game only known from the library cache).
    pub achievements: Option<Vec<Achievement>>,
    pub achievements_unlocked: usize,
    pub achievements_total: usize,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Folder {
    pub index: u32,
    pub path: String,
    pub label: String,
    pub capacity: u64,
    pub free: u64,
    pub default: bool,
    pub mounted: bool,
    pub apps: u32,
}

/// A licence agreement a game's publisher wants accepted before it installs.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Licence {
    pub id: String,
    pub version: u64,
    /// Web address of the text, to show to the player.
    pub url: String,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct InstallReport {
    pub appid: u32,
    pub name: String,
    pub folder: u32,
    pub bytes_needed: u64,
    pub bytes_free: u64,
    /// false for a dry run: only the size was asked.
    pub started: bool,
    /// true when no Steam window was involved. false: Steam's interface has changed and
    /// the install went through its visible wizard (see `js::install`).
    pub quiet: bool,
    /// The title of Steam's own Install dialog in the client's language ("Install" in
    /// English): the one Steam window that belongs to an install when `quiet` is false.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub dialog_title: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DownloadItem {
    pub appid: u32,
    pub name: String,
    pub active: bool,
    pub paused: bool,
    pub completed: bool,
    /// Place in the queue; -1 when not queued (scheduled for later, or done).
    pub queue_index: i64,
    /// Unix time Steam plans to start it by itself; 0 for none.
    pub scheduled_for: u64,
    pub bytes_done: u64,
    pub bytes_total: u64,
    pub error: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Downloads {
    /// Steam's word for what it is doing: "None", "Updating", ...
    pub state: String,
    pub paused: bool,
    /// The app being downloaded now; 0 for none.
    pub appid: u32,
    pub bytes_per_second: u64,
    pub percent: f64,
    /// -1 when unknown. Steam leaves it out while a download is being set up.
    #[serde(default = "unknown")]
    pub seconds_left: i64,
    pub installing: bool,
    pub items: Vec<DownloadItem>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RunningApp {
    pub appid: u32,
    pub name: String,
}

fn unknown() -> i64 {
    -1
}

pub fn kind_of(app_type: u64) -> &'static str {
    match app_type {
        1 => "game",
        2 => "application",
        4 => "tool",
        8 => "demo",
        _ => "other",
    }
}

/// Steam's install manager states, by number (from the client's own script).
pub fn install_state(state: u64) -> &'static str {
    match state {
        0 => "none",
        1 => "setup",
        2 => "waiting for the licence",
        3 => "free licence",
        4 => "product key",
        5 => "waiting for app information",
        6 => "password",
        7 => "ready to install",
        8 => "licence agreement",
        9 => "creating",
        10 => "reading from media",
        11 => "change media",
        12 => "waiting for product keys",
        13 => "sign-up",
        14 => "complete",
        15 => "failed",
        16 => "cancelled",
        _ => "unknown",
    }
}

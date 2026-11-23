use std::path::PathBuf;

pub type Result<T> = std::result::Result<T, Error>;

/// Every failure has a short code the shell can act on, and a sentence for a person.
#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("Steam is not installed (no \"{0}\" command)")]
    NotInstalled(String),
    #[error("Steam is not running")]
    NotRunning,
    #[error("Steam is not ready: {0}")]
    NotReady(String),
    #[error("Steam's debugging port {0} is reachable from other machines; Steam was stopped")]
    PortExposed(u16),
    #[error("Steam no longer has {0}; this Steam version is newer than the one ugos-steam was checked against")]
    CallMissing(String),
    #[error("Steam answered {call} with something unexpected: {detail}")]
    UnexpectedShape { call: &'static str, detail: String },
    #[error("Steam did not answer {0} in time")]
    Timeout(String),
    #[error("{call} failed inside Steam: {detail}")]
    Script { call: &'static str, detail: String },
    #[error("no saved account is called \"{0}\"")]
    AccountNotFound(String),
    #[error("Steam is not showing its account list")]
    NoAccountChoice,
    #[error("app {0} is not in this account's library")]
    NotOwned(u32),
    #[error("app {0} is already installed")]
    AlreadyInstalled(u32),
    #[error("app {0} is not installed")]
    AppNotInstalled(u32),
    #[error("there is no install folder with index {0}")]
    NoSuchFolder(u32),
    #[error("not enough free space: {needed} bytes needed, {free} free")]
    NoSpace { needed: u64, free: u64 },
    #[error("this game has {} licence agreement(s) the player must accept first; nothing was installed", .0.len())]
    LicenceRequired(Vec<crate::model::Licence>),
    #[error("Steam needs the player for this install ({0}); it was cancelled")]
    InstallNeedsAttention(String),
    #[error("the install did not start: {0}")]
    InstallFailed(String),
    #[error("Steam's setting {name} did not take the value after {attempts} attempt(s)")]
    SettingNotApplied { name: &'static str, enabled: Option<bool>, attempts: u32 },
    #[error("Steam could not start the game{}", .steam_error.as_ref().map(|e| format!(" ({e})")).unwrap_or_default())]
    LaunchFailed { steam_error: Option<String>, detail: Option<String>, task: Option<String> },
    #[error("Steam ended the launch without the game starting (cancelled in Steam, or the game closed at once)")]
    LaunchDidNotStart { task: Option<String> },
    #[error("Steam was still preparing the game after {seconds} seconds{}; the launch was cancelled", .task.as_ref().map(|t| format!(" (at: {t})")).unwrap_or_default())]
    LaunchTimeout { seconds: u64, task: Option<String> },
    #[error("there is nothing to skip{}", .task.as_ref().map(|t| format!(": Steam is at \"{t}\", which cannot be skipped")).unwrap_or_else(|| ": no launch of this game is being prepared".into()))]
    NothingToSkip { task: Option<String> },
    #[error("cannot talk to Steam on port {port}: {detail}")]
    Connection { port: u16, detail: String },
    #[error("{}: {source}", path.display())]
    Io { path: PathBuf, source: std::io::Error },
    #[error("cannot run \"{program}\": {source}")]
    Spawn { program: String, source: std::io::Error },
    #[error("{0}")]
    BadArgument(String),
}

impl Error {
    pub fn code(&self) -> &'static str {
        match self {
            Error::NotInstalled(_) => "not-installed",
            Error::NotRunning => "not-running",
            Error::NotReady(_) => "not-ready",
            Error::PortExposed(_) => "debug-port-exposed",
            Error::CallMissing(_) => "steam-call-missing",
            Error::UnexpectedShape { .. } => "unexpected-shape",
            Error::Timeout(_) => "timeout",
            Error::Script { .. } => "script-failed",
            Error::AccountNotFound(_) => "account-not-found",
            Error::NoAccountChoice => "no-account-choice",
            Error::NotOwned(_) => "not-owned",
            Error::AlreadyInstalled(_) => "already-installed",
            Error::AppNotInstalled(_) => "app-not-installed",
            Error::NoSuchFolder(_) => "no-such-folder",
            Error::NoSpace { .. } => "no-space",
            Error::LicenceRequired(_) => "licence-required",
            Error::InstallNeedsAttention(_) => "install-needs-attention",
            Error::InstallFailed(_) => "install-failed",
            Error::SettingNotApplied { .. } => "setting-not-applied",
            Error::LaunchFailed { .. } => "launch-failed",
            Error::LaunchDidNotStart { .. } => "launch-did-not-start",
            Error::LaunchTimeout { .. } => "launch-timeout",
            Error::NothingToSkip { .. } => "nothing-to-skip",
            Error::Connection { .. } => "connection-failed",
            Error::Io { .. } => "io",
            Error::Spawn { .. } => "cannot-run",
            Error::BadArgument(_) => "bad-argument",
        }
    }
}

//! The words for the screen. Every long-running command reports a `phase` (a fixed
//! name for the shell's logic) and a `message` (a short English sentence the shell can
//! show as it is). The messages name no command, number, path or technical term.
//!
//! Phase names are part of the command's interface: add new ones, never rename.

use crate::model::Status;
use serde_json::{json, Value};

/// Every phase and its message. docs/steam-integration.md has the same table.
pub const PHASES: [(&str, &str); 20] = [
    // Steam itself
    ("not-installed", "Steam is not installed"),
    ("not-running", "Steam is not running"),
    ("starting-steam", "Starting Steam"),
    ("choose-account", "Choose a Steam account"),
    ("needs-attention", "Steam needs your attention"),
    ("ready", "Steam is ready"),
    ("stopping-steam", "Closing Steam"),
    // A game being started and played
    ("preparing", "Preparing the game"),
    ("starting", "Starting the game"),
    ("running", "The game is running"),
    ("stopping", "Closing the game"),
    ("ended", "The game was closed"),
    ("failed", "The game could not be started"),
    ("not-started", "The game did not start"),
    ("timed-out", "Steam took too long to prepare the game"),
    // Installing and removing
    ("ready-to-install", "Ready to install"),
    ("installing", "Installing"),
    ("needs-licence", "The game has a licence agreement to accept"),
    ("removing", "Removing the game"),
    ("removed", "The game was removed"),
];

pub fn message(phase: &str) -> &'static str {
    PHASES.iter().find(|(name, _)| *name == phase).map(|(_, text)| *text).unwrap_or("")
}

/// Adds `phase` and `message` to an answer. Fields the answer already has are kept,
/// except these two.
pub fn with(mut answer: Value, phase: &str) -> Value {
    if !answer.is_object() {
        answer = json!({});
    }
    answer["phase"] = json!(phase);
    answer["message"] = json!(message(phase));
    answer
}

/// The phase that goes with each of Steam's states. While Steam wants a sign-in in
/// its own window, that is "needs-attention".
pub fn of_status(status: Status) -> &'static str {
    match status {
        Status::NotInstalled => "not-installed",
        Status::NotRunning => "not-running",
        Status::Starting => "starting-steam",
        Status::NeedsAccountChoice => "choose-account",
        Status::NeedsSignIn => "needs-attention",
        Status::Ready => "ready",
    }
}

/// The phase an `install` answer carries: under way, or only looked at (a dry run).
pub fn of_install(started: bool) -> &'static str {
    if started {
        "installing"
    } else {
        "ready-to-install"
    }
}

/// The phase after asking a game to close. `closed` is None when nobody waited to see.
pub fn of_stop(was_running: bool, closed: Option<bool>) -> &'static str {
    match (was_running, closed) {
        (false, _) | (true, Some(true)) => "ended",
        // Asked to close and not gone yet (or not waited for): it is closing.
        (true, _) => "stopping",
    }
}

/// The phase and the `ended` word of a finished `launch --wait`.
pub fn of_wait(ended: &crate::steam::Ended) -> (&'static str, &'static str) {
    match ended {
        crate::steam::Ended::Exited => ("ended", "exited"),
        crate::steam::Ended::Stopped => ("ended", "stopped"),
        // Told to close and still there after the grace time.
        crate::steam::Ended::StillRunning => ("stopping", "still-running"),
    }
}

/// The phase that goes with a failure, for the ones a screen has words for.
pub fn of_error(error: &crate::Error) -> Option<&'static str> {
    Some(match error {
        crate::Error::LaunchFailed { .. } => "failed",
        crate::Error::LaunchDidNotStart { .. } => "not-started",
        crate::Error::LaunchTimeout { .. } => "timed-out",
        crate::Error::LicenceRequired(_) => "needs-licence",
        crate::Error::NotInstalled(_) => "not-installed",
        crate::Error::NotRunning => "not-running",
        _ => return None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_phase_has_a_plain_message() {
        for (phase, text) in PHASES {
            assert!(!text.is_empty() && text.len() <= 48, "{phase}");
            assert!(text.chars().next().unwrap().is_uppercase(), "{phase}");
            // Nothing a player would not say: no numbers, paths, flags or our own names.
            assert!(text.chars().all(|c| c.is_ascii_alphabetic() || c == ' '), "{phase}: {text}");
            for word in ["ugos", "appid", "launch", "process", "command", "Proton", "manifest"] {
                assert!(!text.to_lowercase().contains(&word.to_lowercase()), "{phase}: {text}");
            }
            assert!(phase.chars().all(|c| c.is_ascii_lowercase() || c == '-'), "{phase}");
        }
        let mut names: Vec<&str> = PHASES.iter().map(|(n, _)| *n).collect();
        names.sort();
        names.dedup();
        assert_eq!(names.len(), PHASES.len(), "a phase is listed twice");
    }

    #[test]
    fn the_examples_the_owner_gave_are_there_word_for_word() {
        for text in ["Starting Steam", "Preparing the game", "Steam needs your attention", "Starting the game", "Closing the game", "Installing", "Removing the game"] {
            assert!(PHASES.iter().any(|(_, t)| *t == text), "{text}");
        }
        assert_eq!(message("stopping"), "Closing the game");
        assert_eq!(message("no-such-phase"), "");
    }

    #[test]
    fn each_long_command_ends_on_a_phase_with_words() {
        use crate::steam::Ended;
        use crate::Error;
        // install, and install --dry-run
        assert_eq!((of_install(true), message(of_install(true))), ("installing", "Installing"));
        assert_eq!(message(of_install(false)), "Ready to install");
        // uninstall: "removing" while it works, "removed" at the end
        assert_eq!((message("removing"), message("removed")), ("Removing the game", "The game was removed"));
        // stop of a game: closing until it has really gone
        assert_eq!(message(of_stop(true, None)), "Closing the game");
        assert_eq!(message(of_stop(true, Some(false))), "Closing the game");
        assert_eq!(message(of_stop(true, Some(true))), "The game was closed");
        assert_eq!(of_stop(false, None), "ended");
        // launch --wait
        assert_eq!(of_wait(&Ended::Exited), ("ended", "exited"));
        assert_eq!(of_wait(&Ended::Stopped), ("ended", "stopped"));
        assert_eq!(of_wait(&Ended::StillRunning), ("stopping", "still-running"));
        // start and stop of Steam itself
        assert_eq!((message("starting-steam"), message("stopping-steam")), ("Starting Steam", "Closing Steam"));
        // failures a screen can put into words; the rest have none
        assert_eq!(message(of_error(&Error::LaunchFailed { steam_error: None, detail: None, task: None }).unwrap()), "The game could not be started");
        assert_eq!(message(of_error(&Error::LaunchDidNotStart { task: None }).unwrap()), "The game did not start");
        assert_eq!(message(of_error(&Error::LaunchTimeout { seconds: 900, task: None }).unwrap()), "Steam took too long to prepare the game");
        assert_eq!(of_error(&Error::LicenceRequired(Vec::new())), Some("needs-licence"));
        assert_eq!(of_error(&Error::NotOwned(1)), None);
    }

    #[test]
    fn an_answer_gains_the_two_fields_and_keeps_its_own() {
        let out = with(json!({ "appid": 7, "phase": "old" }), "installing");
        assert_eq!(out, json!({ "appid": 7, "phase": "installing", "message": "Installing" }));
        for status in [Status::NotInstalled, Status::NotRunning, Status::Starting, Status::NeedsAccountChoice, Status::NeedsSignIn, Status::Ready] {
            assert!(!message(of_status(status)).is_empty());
        }
        assert_eq!(message(of_status(Status::Starting)), "Starting Steam");
        assert_eq!(message(of_status(Status::NeedsSignIn)), "Steam needs your attention");
    }
}

//! Where a launch stands, worked out from Steam's own signals.
//!
//! Steam starts a game as a "game action": it begins, goes through tasks (update,
//! first-time setup such as creating the Proton prefix, creating the process), may ask
//! the player something, may fail, and ends once the game's process is up. During the
//! tasks the app can show up as running and go away again (a setup step runs as the
//! app), which is why "was running, is not any more" alone does not mean the game was
//! played and closed. The rule here:
//!
//! - while the game action is active, the launch is being prepared, whatever else is seen;
//! - once it has ended, the game is running while Steam lists the app as running;
//! - it has ended when it ran after that and is gone;
//! - it failed when Steam reported an error, or when the action ended and the game
//!   never came up.
//!
//! [`Tracker`] is fed one [`Snapshot`] per look and remembers what it has seen. It does
//! no waiting and talks to nothing, so every case can be tested from written-down events.

use crate::say;
use crate::task;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

/// One of Steam's game-action events, as `js_actions.inc` keeps them.
#[derive(Debug, Clone, Deserialize)]
pub struct Event {
    pub n: u64,
    /// start, task, request, error, end, or lifetime.
    pub kind: String,
    #[serde(default)]
    pub id: i64,
    #[serde(default)]
    pub app: Option<String>,
    #[serde(default)]
    pub action: Option<String>,
    #[serde(default)]
    pub detail: Option<String>,
    #[serde(default)]
    pub extra: Option<String>,
}

/// A game action Steam lists as active right now.
#[derive(Debug, Clone, Deserialize)]
pub struct ActiveAction {
    #[serde(default)]
    pub id: i64,
    #[serde(default)]
    pub app: Option<String>,
    #[serde(default)]
    pub action: Option<String>,
    #[serde(default)]
    pub task: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Snapshot {
    /// The kinds of event being listened for. Empty when Steam offers none of them.
    #[serde(default)]
    pub listening: Vec<String>,
    /// The app is among Steam's running apps.
    pub running: bool,
    /// None when Steam's list of active game actions could not be read.
    #[serde(default)]
    pub active: Option<Vec<ActiveAction>>,
    #[serde(default)]
    pub events: Vec<Event>,
    /// Steam's count for the step the launch is on, when it could be asked.
    #[serde(default)]
    pub progress: Option<Progress>,
}

/// What Steam's own launch window draws its bar from: so many done of so many.
#[derive(Debug, Clone, Deserialize)]
pub struct Progress {
    #[serde(default)]
    pub done: Option<f64>,
    #[serde(default)]
    pub total: Option<f64>,
}

/// The names are what the commands print as `phase`; `say::PHASES` has the words for each.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(tag = "phase", rename_all = "kebab-case")]
pub enum Phase {
    /// Steam is getting the game ready: updating, first-time setup.
    Preparing {
        /// Steam's own name for the step, when it gives one. For logs, not for the screen.
        task: Option<String>,
        /// How far the step is, when Steam counts it. Left out when it does not.
        #[serde(skip_serializing_if = "Option::is_none")]
        percent: Option<u8>,
        /// The step can be skipped (`launch-skip`), as Steam's own Skip button does.
        skippable: bool,
    },
    /// Steam is asking the player something in a window of its own (a licence text, a
    /// choice of launch option, a cloud save conflict).
    NeedsAttention { task: Option<String> },
    /// Steam has done its part; the game's own process is coming up.
    Starting,
    Running,
    /// The game was told to close and has not gone yet.
    Stopping,
    /// The game ran and is gone.
    Ended,
    Failed {
        /// Steam's error text ("AppError_51"), when it reported one.
        steam_error: Option<String>,
        detail: Option<String>,
        /// The last step Steam named before it failed.
        task: Option<String>,
    },
}

impl Phase {
    /// The phase's printed name.
    pub fn name(&self) -> &'static str {
        match self {
            Phase::Preparing { .. } => "preparing",
            Phase::NeedsAttention { .. } => "needs-attention",
            Phase::Starting => "starting",
            Phase::Running => "running",
            Phase::Stopping => "stopping",
            Phase::Ended => "ended",
            Phase::Failed { steam_error: None, detail: None, .. } => "not-started",
            Phase::Failed { .. } => "failed",
        }
    }
}

/// One line of `launch --wait --progress`: the phase with its fields, the game, the
/// words for the phase (`message`) and, while Steam is working on a step, the words
/// for that step (`task_message`).
pub fn line(phase: &Phase, appid: u32, name: &str) -> Value {
    let mut line = say::with(serde_json::to_value(phase).unwrap_or_else(|_| json!({})), phase.name());
    line["appid"] = json!(appid);
    line["name"] = json!(name);
    if let Phase::Preparing { task, .. } | Phase::NeedsAttention { task } = phase {
        line["task_message"] = json!(task::message(task.as_deref()));
    }
    line
}

pub struct Tracker {
    appid: String,
    /// Events up to this number have been seen.
    seen: u64,
    action: Option<i64>,
    action_ended: bool,
    task: Option<String>,
    needs_player: bool,
    error: Option<(String, Option<String>)>,
    /// The game was seen running with no game action active.
    ran: bool,
    /// Looks in a row with nothing going on and the game not there.
    idle: u32,
    /// How many such looks are waited before deciding the game is not coming.
    settle: u32,
    /// At the last look: a game action was active, or the game was running.
    busy: bool,
}

impl Tracker {
    /// `since`: the number of the last event before this launch (from the `launch` script).
    pub fn new(appid: u32, since: u64, settle: u32) -> Tracker {
        Tracker { appid: appid.to_string(), seen: since, action: None, action_ended: false, task: None, needs_player: false, error: None, ran: false, idle: 0, settle, busy: false }
    }

    /// The game action of this launch, once Steam has named it.
    pub fn action(&self) -> Option<i64> {
        self.action
    }

    /// At the last look nothing of this launch was left: no game action, no game.
    pub fn gone(&self) -> bool {
        !self.busy
    }

    pub fn see(&mut self, snapshot: &Snapshot) -> Phase {
        let mine = |app: &Option<String>| app.as_deref() == Some(self.appid.as_str());
        let mut events: Vec<&Event> = snapshot.events.iter().filter(|e| e.n > self.seen).collect();
        events.sort_by_key(|e| e.n);
        for e in events {
            self.seen = e.n;
            let this_action = self.action == Some(e.id);
            match e.kind.as_str() {
                "start" if mine(&e.app) => {
                    self.action = Some(e.id);
                    self.action_ended = false;
                    self.task = None;
                    self.needs_player = false;
                    self.error = None;
                }
                "task" if this_action => {
                    self.task = e.detail.clone();
                    self.needs_player = false;
                }
                "request" if this_action => {
                    self.task = e.detail.clone();
                    // Not every request is a question: shader processing is announced
                    // as one only because Steam's window for it has a Skip button.
                    self.needs_player = task::request_needs_player(e.detail.as_deref());
                }
                "error" if this_action || mine(&e.app) => self.error = Some((e.detail.clone().unwrap_or_default(), e.extra.clone())),
                "end" if this_action => self.action_ended = true,
                // The process came up after the action was over (or no action was ever
                // announced): the game itself, not a setup step. Catches a game that
                // starts and closes between two looks.
                "lifetime" if mine(&e.app) && e.detail.as_deref() == Some("running") && (self.action.is_none() || self.action_ended) => self.ran = true,
                _ => {}
            }
        }

        // Steam's own list of active actions covers events that were missed.
        let listed = snapshot.active.as_ref().and_then(|list| list.iter().find(|a| mine(&a.app) || (self.action.is_some() && self.action == Some(a.id))));
        if let Some(a) = listed {
            if self.action != Some(a.id) {
                self.action = Some(a.id);
                self.action_ended = false;
            }
            if self.task.is_none() {
                self.task = a.task.clone();
            }
        }
        let hears_the_end = snapshot.listening.iter().any(|k| k == "end");
        let active = match (&snapshot.active, listed) {
            (_, Some(_)) => true,
            // Not in Steam's list, and nobody would have told us it ended: it is over.
            (Some(_), None) if !hears_the_end => false,
            _ => self.action.is_some() && !self.action_ended,
        };
        if !active && self.action.is_some() {
            self.action_ended = true;
        }

        self.busy = active || snapshot.running;
        if active {
            self.idle = 0;
            if self.needs_player {
                return Phase::NeedsAttention { task: self.task.clone() };
            }
            let task = self.task.as_deref().filter(|t| !t.is_empty());
            let percent = snapshot.progress.as_ref().and_then(|p| task::percent(p.done, p.total));
            return Phase::Preparing { task: self.task.clone(), percent, skippable: task::skippable(task) };
        }
        if snapshot.running {
            self.idle = 0;
            self.ran = true;
            return Phase::Running;
        }
        if let Some((error, detail)) = &self.error {
            return Phase::Failed { steam_error: Some(error.clone()).filter(|e| !e.is_empty()), detail: detail.clone(), task: self.task.clone() };
        }
        if self.ran {
            return Phase::Ended;
        }
        // Nothing active and no game: either Steam has not begun yet, or the action is
        // over and the game's process is about to appear, or it is not coming at all.
        self.idle += 1;
        if self.idle > self.settle {
            return Phase::Failed { steam_error: None, detail: None, task: self.task.clone() };
        }
        if self.action.is_some() {
            Phase::Starting
        } else {
            Phase::Preparing { task: None, percent: None, skippable: false }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn snap(value: serde_json::Value) -> Snapshot {
        serde_json::from_value(value).unwrap()
    }

    const ALL: [&str; 6] = ["start", "task", "request", "error", "end", "lifetime"];

    #[test]
    fn events_for_another_app_or_an_older_launch_are_ignored() {
        let mut t = Tracker::new(10, 5, 2);
        let phase = t.see(&snap(json!({ "listening": ALL, "running": false, "active": [], "events": [
            { "n": 3, "kind": "start", "id": 1, "app": "10", "action": "LaunchApp" },
            { "n": 6, "kind": "start", "id": 2, "app": "99", "action": "LaunchApp" },
            { "n": 7, "kind": "error", "id": 2, "app": "99", "action": "LaunchApp", "detail": "AppError_51" } ] })));
        assert_eq!(phase, Phase::Preparing { task: None, percent: None, skippable: false });
        assert_eq!(t.action(), None);
    }

    #[test]
    fn a_question_from_steam_is_passed_on() {
        let mut t = Tracker::new(10, 0, 2);
        let phase = t.see(&snap(json!({ "listening": ALL, "running": false, "active": [{ "id": 4, "app": "10", "action": "LaunchApp", "task": "ShowEula" }], "events": [
            { "n": 1, "kind": "start", "id": 4, "app": "10", "action": "LaunchApp" },
            { "n": 2, "kind": "request", "id": 4, "app": "10", "action": "LaunchApp", "detail": "ShowEula" } ] })));
        assert_eq!(phase, Phase::NeedsAttention { task: Some("ShowEula".into()) });
        assert_eq!(phase.name(), "needs-attention");
    }

    #[test]
    fn without_events_steams_list_of_active_actions_is_enough() {
        // A Steam that offers none of the event registrations: only the list and the running apps.
        let mut t = Tracker::new(10, 0, 2);
        let preparing = snap(json!({ "listening": [], "running": true, "active": [{ "id": 8, "app": "10", "action": "LaunchApp", "task": "RunningInstallScript" }], "events": [] }));
        assert_eq!(t.see(&preparing), Phase::Preparing { task: Some("RunningInstallScript".into()), percent: None, skippable: false });
        assert_eq!(t.action(), Some(8));
        // Gone from the list, game up; then game gone.
        assert_eq!(t.see(&snap(json!({ "listening": [], "running": true, "active": [], "events": [] }))), Phase::Running);
        assert_eq!(t.see(&snap(json!({ "listening": [], "running": false, "active": [], "events": [] }))), Phase::Ended);
    }

    #[test]
    fn a_game_that_starts_and_closes_between_two_looks_still_counts_as_played() {
        let mut t = Tracker::new(10, 0, 2);
        let phase = t.see(&snap(json!({ "listening": ALL, "running": false, "active": [], "events": [
            { "n": 1, "kind": "start", "id": 4, "app": "10", "action": "LaunchApp" },
            { "n": 2, "kind": "end", "id": 4 },
            { "n": 3, "kind": "lifetime", "app": "10", "detail": "running" },
            { "n": 4, "kind": "lifetime", "app": "10", "detail": "gone" } ] })));
        assert_eq!(phase, Phase::Ended);
    }

    // The three tests below replay what `launch --wait --progress` printed on the Legion
    // Go on 2026-11-10 at 22:55 UTC for a first launch (task names and their order are
    // from that log; the event kinds are inferred from the phases it printed, and the
    // counts for the percentage are made up, since version 23 did not ask for them).

    fn first_launch_events() -> Vec<serde_json::Value> {
        vec![
            json!({ "n": 1, "kind": "start", "id": 3, "app": "1887840", "action": "LaunchApp" }),
            json!({ "n": 2, "kind": "task", "id": 3, "app": "1887840", "action": "LaunchApp", "detail": "SynchronizingCloud" }),
            json!({ "n": 3, "kind": "request", "id": 3, "app": "1887840", "action": "LaunchApp", "detail": "ProcessingShaderCache" }),
        ]
    }

    #[test]
    fn shader_processing_is_preparing_with_a_percentage_and_can_be_skipped() {
        let mut t = Tracker::new(1887840, 0, 2);
        let phase = t.see(&snap(json!({ "listening": ALL, "running": false, "active": [{ "id": 3, "app": "1887840", "action": "LaunchApp", "task": "ProcessingShaderCache" }],
            "events": first_launch_events(), "progress": { "done": 412.0, "total": 1000.0 } })));
        // Version 23 called this "Steam needs your attention", which brought Steam's window forward.
        assert_eq!(phase, Phase::Preparing { task: Some("ProcessingShaderCache".into()), percent: Some(41), skippable: true });
        assert_eq!(
            line(&phase, 1887840, "Another Crab's Treasure"),
            json!({ "appid": 1887840, "name": "Another Crab's Treasure", "phase": "preparing", "message": "Preparing the game",
                "task": "ProcessingShaderCache", "task_message": "Preparing graphics for the first run", "percent": 41, "skippable": true })
        );
    }

    #[test]
    fn a_step_steam_does_not_count_has_no_percentage_field() {
        let mut t = Tracker::new(1887840, 0, 2);
        let events = &first_launch_events()[..2];
        for progress in [json!(null), json!({ "done": 0.0, "total": 0.0 }), json!({ "done": null, "total": null })] {
            let phase = t.see(&snap(json!({ "listening": ALL, "running": false, "active": [{ "id": 3, "app": "1887840" }], "events": events, "progress": progress })));
            let printed = line(&phase, 1887840, "Another Crab's Treasure");
            assert_eq!(printed["task"], "SynchronizingCloud");
            assert_eq!(printed["task_message"], "Syncing your saved games");
            assert_eq!(printed["skippable"], false);
            assert!(printed.get("percent").is_none(), "{printed}");
        }
    }

    #[test]
    fn a_task_name_nobody_has_seen_passes_through_with_the_generic_words() {
        let mut t = Tracker::new(10, 0, 2);
        let phase = t.see(&snap(json!({ "listening": ALL, "running": false, "active": [{ "id": 4, "app": "10" }], "events": [
            { "n": 1, "kind": "start", "id": 4, "app": "10", "action": "LaunchApp" },
            { "n": 2, "kind": "task", "id": 4, "app": "10", "action": "LaunchApp", "detail": "DefragmentingTheMoon" } ] })));
        let printed = line(&phase, 10, "Game");
        assert_eq!((printed["phase"].as_str(), printed["task"].as_str(), printed["task_message"].as_str()), (Some("preparing"), Some("DefragmentingTheMoon"), Some("Preparing the game")));
        assert_eq!(printed["skippable"], false);
        // The very first line, before Steam has named a step (the log shows an empty name).
        let mut t = Tracker::new(10, 0, 2);
        let phase = t.see(&snap(json!({ "listening": ALL, "running": false, "active": [{ "id": 4, "app": "10", "task": "" }], "events": [] })));
        assert_eq!(line(&phase, 10, "Game")["task_message"], "Preparing the game");
    }

    #[test]
    fn a_real_question_still_needs_the_player_and_lines_without_a_step_have_no_step_words() {
        let mut t = Tracker::new(10, 0, 2);
        let phase = t.see(&snap(json!({ "listening": ALL, "running": false, "active": [{ "id": 4, "app": "10" }], "events": [
            { "n": 1, "kind": "start", "id": 4, "app": "10", "action": "LaunchApp" },
            { "n": 2, "kind": "request", "id": 4, "app": "10", "action": "LaunchApp", "detail": "ShowEula" } ] })));
        let printed = line(&phase, 10, "Game");
        assert_eq!((printed["phase"].as_str(), printed["message"].as_str()), (Some("needs-attention"), Some("Steam needs your attention")));
        assert_eq!(printed["task_message"], "The game has a licence agreement to accept");
        assert!(line(&Phase::Running, 10, "Game").get("task_message").is_none());
        assert_eq!(line(&Phase::Stopping, 10, "Game"), json!({ "appid": 10, "name": "Game", "phase": "stopping", "message": "Closing the game" }));
    }

    #[test]
    fn the_phase_is_printed_with_its_name() {
        assert_eq!(serde_json::to_value(Phase::Preparing { task: Some("x".into()), percent: None, skippable: false }).unwrap(), json!({ "phase": "preparing", "task": "x", "skippable": false }));
        assert_eq!(serde_json::to_value(Phase::Running).unwrap(), json!({ "phase": "running" }));
        for phase in [Phase::Preparing { task: None, percent: None, skippable: false }, Phase::NeedsAttention { task: None }, Phase::Starting, Phase::Running, Phase::Stopping, Phase::Ended] {
            assert_eq!(serde_json::to_value(&phase).unwrap()["phase"], phase.name());
            assert!(!crate::say::message(phase.name()).is_empty());
        }
        assert_eq!(Phase::Failed { steam_error: None, detail: None, task: None }.name(), "not-started");
        assert_eq!(Phase::Failed { steam_error: Some("AppError_51".into()), detail: None, task: None }.name(), "failed");
    }
}

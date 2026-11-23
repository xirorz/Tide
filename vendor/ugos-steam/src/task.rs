//! Steam's names for the steps of a launch, and the words for each.
//!
//! Steam reports the step it is on as a task name such as `ProcessingShaderCache`. The
//! screen gets a plain sentence instead. A name that is not in the table is not an
//! error: Steam adds steps over time, and such a step is simply "Preparing the game".

/// Where a task name is known from.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Known {
    /// Printed by `launch --wait --progress` on the Legion Go on 2026-11-10.
    SeenOnTheGo,
    /// Named in the Steam client's own interface code (read 2026-11-10); not seen in a launch.
    FromSteamsCode,
    /// A name Steam is believed to use; neither seen nor read. The words are a guess at
    /// what it would mean, and cost nothing if the name never comes.
    Expected,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Task {
    pub name: &'static str,
    /// For the screen.
    pub message: &'static str,
    /// Steam counts this step (done of total), so a percentage can be shown.
    pub percent: bool,
    /// The step can be skipped, as Steam's own Skip button does.
    pub skippable: bool,
    /// Steam is asking the player something in its own window.
    pub attention: bool,
    pub known: Known,
}

const fn step(name: &'static str, message: &'static str, known: Known) -> Task {
    Task { name, message, percent: false, skippable: false, attention: false, known }
}

const fn question(name: &'static str, message: &'static str, known: Known) -> Task {
    Task { name, message, percent: false, skippable: false, attention: true, known }
}

/// What is shown for a step with no name, or a name not in the table.
pub const GENERIC: &str = "Preparing the game";

/// Every task name that could be established. docs/steam-integration.md has the same table.
pub const TASKS: [Task; 12] = [
    step("SynchronizingCloud", "Syncing your saved games", Known::SeenOnTheGo),
    step("SynchronizingControllerConfig", "Setting up the controller", Known::SeenOnTheGo),
    // Steam announces this one as a request to the player, because its own window has
    // a Skip button. It needs no answer: it finishes by itself.
    Task { name: "ProcessingShaderCache", message: "Preparing graphics for the first run", percent: true, skippable: true, attention: false, known: Known::SeenOnTheGo },
    question("ShowEula", "The game has a licence agreement to accept", Known::FromSteamsCode),
    question("ShowLaunchOption", "Steam asks how to start the game", Known::FromSteamsCode),
    question("ShowDurationControl", "Steam has a notice about play time", Known::FromSteamsCode),
    Task { name: "UpdatingContent", message: "Updating the game", percent: true, skippable: false, attention: false, known: Known::Expected },
    Task { name: "VerifyingFiles", message: "Checking the game files", percent: true, skippable: false, attention: false, known: Known::Expected },
    step("RunningInstallScript", "Setting the game up for the first run", Known::Expected),
    step("UpdatingAppInfo", "Checking for updates", Known::Expected),
    step("CreatingProcess", "Starting the game", Known::Expected),
    step("WaitingGameWindow", "Starting the game", Known::Expected),
];

/// The table's entry for a task name, if it has one.
pub fn known(task: Option<&str>) -> Option<&'static Task> {
    let name = task?;
    TASKS.iter().find(|t| t.name == name)
}

/// The words for a task. Never fails: no name, or an unknown one, gives the generic words.
pub fn message(task: Option<&str>) -> &'static str {
    known(task).map(|t| t.message).unwrap_or(GENERIC)
}

/// A request from Steam is a question for the player unless the table says otherwise.
/// An unknown request is treated as a question: showing Steam's window when it was not
/// needed costs little, hiding it when it was needed leaves the launch stuck.
pub fn request_needs_player(task: Option<&str>) -> bool {
    known(task).map(|t| t.attention).unwrap_or(true)
}

pub fn skippable(task: Option<&str>) -> bool {
    known(task).is_some_and(|t| t.skippable)
}

/// Steam's own sum for its launch window: whole percent of done over total, and
/// nothing when the step is not counted.
pub fn percent(done: Option<f64>, total: Option<f64>) -> Option<u8> {
    let (done, total) = (done?, total?);
    (total > 0.0 && done >= 0.0 && done <= total).then(|| (done * 100.0 / total).floor() as u8)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_tasks_seen_on_the_go_have_their_words() {
        assert_eq!(message(Some("ProcessingShaderCache")), "Preparing graphics for the first run");
        assert_eq!(message(Some("SynchronizingCloud")), "Syncing your saved games");
        assert_eq!(message(Some("SynchronizingControllerConfig")), "Setting up the controller");
    }

    #[test]
    fn an_unknown_task_gets_the_generic_words_never_an_error() {
        assert_eq!(message(Some("SomethingValveAddsNextYear")), GENERIC);
        assert_eq!(message(Some("")), GENERIC);
        assert_eq!(message(None), "Preparing the game");
        assert!(!skippable(Some("SomethingValveAddsNextYear")));
        assert!(known(Some("SomethingValveAddsNextYear")).is_none());
    }

    #[test]
    fn only_shader_processing_can_be_skipped() {
        assert!(skippable(Some("ProcessingShaderCache")));
        assert_eq!(TASKS.iter().filter(|t| t.skippable).count(), 1);
        assert!(!skippable(None));
    }

    #[test]
    fn shader_processing_is_not_a_question_but_an_unknown_request_is() {
        assert!(!request_needs_player(Some("ProcessingShaderCache")));
        assert!(request_needs_player(Some("ShowEula")));
        assert!(request_needs_player(Some("ShowSomethingNew")));
        assert!(request_needs_player(None));
    }

    #[test]
    fn the_percentage_is_steams_own_sum() {
        assert_eq!(percent(Some(5.0), Some(8.0)), Some(62));
        assert_eq!(percent(Some(8.0), Some(8.0)), Some(100));
        assert_eq!(percent(Some(0.0), Some(8.0)), Some(0));
        // Not counted, or nonsense: no percentage rather than a wrong one.
        assert_eq!(percent(Some(0.0), Some(0.0)), None);
        assert_eq!(percent(Some(9.0), Some(8.0)), None);
        assert_eq!(percent(None, Some(8.0)), None);
        assert_eq!(percent(Some(1.0), None), None);
    }

    #[test]
    fn the_words_are_plain_and_each_name_is_listed_once() {
        let mut names: Vec<&str> = TASKS.iter().map(|t| t.name).collect();
        names.sort();
        names.dedup();
        assert_eq!(names.len(), TASKS.len());
        for t in TASKS {
            assert!(t.message.chars().all(|c| c.is_ascii_alphabetic() || c == ' '), "{}", t.name);
            assert!(t.message.len() <= 48, "{}", t.name);
        }
    }
}

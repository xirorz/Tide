//! The commands against answers recorded from the real Steam client on 2026-11-10
//! (`tests/recorded/`, made with UGOS_STEAM_RECORD; names changed, lists shortened).
//! No Steam is needed to run these. Answers marked "constructed" below could not be
//! recorded, because recording them would have meant launching a game.

use serde_json::{json, Value};
use std::cell::RefCell;
use std::collections::HashMap;
use std::sync::atomic::AtomicBool;
use std::time::Duration;
use ugos_steam::cdp::Client;
use ugos_steam::js::Script;
use ugos_steam::model::Status;
use ugos_steam::launch::Phase;
use ugos_steam::steam::{Ended, Host, Patience, Retry, Steam};
use ugos_steam::{Error, Result};

fn recorded(name: &str) -> Value {
    let path = format!("{}/tests/recorded/{name}.json", env!("CARGO_MANIFEST_DIR"));
    serde_json::from_str(&std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("{path}: {e}"))).unwrap()
}

/// A pretend Steam: per script, the answers it gives in order (the last one repeats).
struct Fake {
    pages: Option<Vec<&'static str>>,
    answers: RefCell<HashMap<&'static str, Vec<Result<Value>>>>,
    asked: RefCell<Vec<(&'static str, Value)>>,
}

impl Fake {
    fn new(pages: Option<Vec<&'static str>>) -> Fake {
        Fake { pages, answers: RefCell::default(), asked: RefCell::default() }
    }

    /// Steam signed in, as recorded.
    fn ready() -> Fake {
        Fake::new(Some(vec!["Steam", "SharedJSContext"])).with("state", recorded("state_ready")).with("accounts", recorded("accounts"))
    }

    /// Steam showing its list of saved accounts, as recorded.
    fn account_list() -> Fake {
        Fake::new(Some(vec!["Sign in to Steam", "SharedJSContext"]))
            .with("state", recorded("state_account_list"))
            .with("sign_in_page", recorded("sign_in_page_account_list"))
            .with("accounts", recorded("accounts"))
    }

    fn with(self, script: &'static str, answer: Value) -> Fake {
        self.answers.borrow_mut().entry(script).or_default().push(Ok(answer));
        self
    }

    fn failing(self, script: &'static str, error: Error) -> Fake {
        self.answers.borrow_mut().entry(script).or_default().push(Err(error));
        self
    }

    fn asked(&self, script: &str) -> usize {
        self.asked.borrow().iter().filter(|(name, _)| *name == script).count()
    }
}

fn again(e: &Error) -> Error {
    match e {
        Error::CallMissing(what) => Error::CallMissing(what.clone()),
        Error::NotRunning => Error::NotRunning,
        other => panic!("not used in these tests: {other}"),
    }
}

impl Client for Fake {
    fn pages(&self) -> Result<Vec<String>> {
        self.pages.as_ref().map(|p| p.iter().map(|s| s.to_string()).collect()).ok_or(Error::NotRunning)
    }

    fn run(&self, script: &Script) -> Result<Value> {
        self.asked.borrow_mut().push((script.name, script.arg().clone()));
        let mut answers = self.answers.borrow_mut();
        // What Steam is busy starting is asked by `status` and `running` as an extra;
        // a test that does not care says nothing is being started.
        if script.name == "activity" && !answers.contains_key("activity") {
            return Ok(json!([]));
        }
        let list = answers.get_mut(script.name).unwrap_or_else(|| panic!("the test has no answer for script \"{}\"", script.name));
        let next = if list.len() > 1 { list.remove(0) } else { list[0].as_ref().map(Value::clone).map_err(again) };
        next
    }
}

struct Machine {
    installed: bool,
    process: bool,
}

impl Host for Machine {
    fn installed(&self) -> bool {
        self.installed
    }
    fn process_running(&self) -> bool {
        self.process
    }
}

const HERE: Machine = Machine { installed: true, process: true };

fn steam<'a>(client: &'a Fake, host: &'a Machine, state: &std::path::Path) -> Steam<'a> {
    Steam { client, host, state_dir: state.to_path_buf(), steam_root: Some(state.join("no-steam-here")), now: 1_794_325_691, settle: Duration::from_secs(4) }
}

fn code<T: std::fmt::Debug>(result: Result<T>) -> &'static str {
    result.expect_err("should have failed").code()
}

#[test]
fn status_is_ready_with_the_account_when_signed_in() {
    let dir = tempfile::tempdir().unwrap();
    let fake = Fake::ready();
    let report = steam(&fake, &HERE, dir.path()).status().unwrap();
    assert_eq!(report.status, Status::Ready);
    assert_eq!(report.account.as_deref(), Some("playerone"));
    assert_eq!(report.persona.as_deref(), Some("Player"));
    // The recording is older than the settings mark, so that reads as "not loaded".
    assert_eq!(serde_json::to_value(&report).unwrap(), json!({ "status": "ready", "account": "playerone", "persona": "Player", "settings_loaded": false }));
}

#[test]
fn status_tells_the_account_list_from_the_sign_in_form() {
    let dir = tempfile::tempdir().unwrap();
    let list = Fake::account_list();
    let report = steam(&list, &HERE, dir.path()).status().unwrap();
    assert_eq!(serde_json::to_value(&report).unwrap(), json!({ "status": "needs-account-choice" }));

    // Constructed: the form for name and password has text fields. (Not recorded: seeing
    // it would have meant signing the owner's accounts out.)
    let form = Fake::new(Some(vec!["Sign in to Steam", "SharedJSContext"]))
        .with("state", recorded("state_account_list"))
        .with("sign_in_page", json!({ "inputs": 2, "password_inputs": 1, "visible": true }));
    assert_eq!(steam(&form, &HERE, dir.path()).status().unwrap().status, Status::NeedsSignIn);

    // No saved account at all: nothing to choose from, so it is a sign-in too.
    let empty = Fake::new(Some(vec!["Sign in to Steam", "SharedJSContext"]))
        .with("state", recorded("state_account_list"))
        .with("sign_in_page", recorded("sign_in_page_account_list"))
        .with("accounts", json!([]));
    assert_eq!(steam(&empty, &HERE, dir.path()).status().unwrap().status, Status::NeedsSignIn);
}

/// Steam's state as the `state` script gives it while the sign-in window is up.
fn signing_in(login_state: i64, waiting_ms: Option<u64>) -> Value {
    json!({ "login_state": login_state, "waiting_ms": waiting_ms, "account": "", "offline": false, "apps": 0, "collections": true })
}

fn one_account() -> Value {
    json!([{ "account": "playerone", "persona": "Player", "remembered": true, "last_login": 1794300000 }])
}

#[test]
fn a_single_saved_account_passes_through_the_account_list_to_ready() {
    // The Legion Go's start-up with version 23: one remembered account, Steam signs it
    // in by itself, and its account list is on screen for the first few seconds.
    // Constructed from that report and from the sign-in states recorded on the PC
    // (1 waiting, 3 and 4 signing in, 5 signed in).
    let dir = tempfile::tempdir().unwrap();
    let fake = Fake::new(Some(vec!["Sign in to Steam", "SharedJSContext"]))
        .with("sign_in_page", recorded("sign_in_page_account_list"))
        .with("accounts", one_account())
        .with("state", signing_in(1, Some(0))) // the list has just appeared
        .with("state", signing_in(1, Some(900))) // still there, automatic sign-in not begun
        .with("state", signing_in(3, None)) // signing in
        .with("state", signing_in(4, None))
        .with("state", json!({ "login_state": 5, "waiting_ms": null, "account": "playerone", "offline": false, "apps": 401, "collections": true, "settings": true }));
    let s = steam(&fake, &HERE, dir.path());
    let seen: Vec<Status> = (0..5).map(|_| s.status().unwrap().status).collect();
    assert_eq!(seen, [Status::Starting, Status::Starting, Status::Starting, Status::Starting, Status::Ready]);
    // "Choose a Steam account" was never said; the screen had "Starting Steam" throughout.
    assert_eq!(ugos_steam::say::message(ugos_steam::say::of_status(Status::Starting)), "Starting Steam");
}

#[test]
fn two_saved_accounts_stay_at_the_account_list() {
    let dir = tempfile::tempdir().unwrap();
    // Recorded account list (two accounts), with the waiting time added.
    let fake = Fake::new(Some(vec!["Sign in to Steam", "SharedJSContext"]))
        .with("sign_in_page", recorded("sign_in_page_account_list"))
        .with("accounts", recorded("accounts"))
        .with("state", signing_in(1, Some(200)))
        .with("state", signing_in(1, Some(3900)))
        .with("state", signing_in(1, Some(4000)))
        .with("state", signing_in(1, Some(60_000)));
    let s = steam(&fake, &HERE, dir.path());
    let seen: Vec<Status> = (0..4).map(|_| s.status().unwrap().status).collect();
    // Starting for the settle time (4 s here), then the choice, and it stays the choice.
    assert_eq!(seen, [Status::Starting, Status::Starting, Status::NeedsAccountChoice, Status::NeedsAccountChoice]);
    // A shorter settle time gives the answer sooner; none at all, at once.
    let mut quick = steam(&fake, &HERE, dir.path());
    quick.settle = Duration::ZERO;
    let fake2 = Fake::new(Some(vec!["Sign in to Steam", "SharedJSContext"])).with("sign_in_page", recorded("sign_in_page_account_list")).with("accounts", recorded("accounts")).with("state", signing_in(1, Some(0)));
    quick.client = &fake2;
    assert_eq!(quick.status().unwrap().status, Status::NeedsAccountChoice);
}

#[test]
fn the_account_list_is_believed_when_the_waiting_time_is_not_known() {
    // The recording from the PC predates the waiting mark: sign-in state 1, no time.
    let dir = tempfile::tempdir().unwrap();
    let list = Fake::account_list();
    assert_eq!(steam(&list, &HERE, dir.path()).status().unwrap().status, Status::NeedsAccountChoice);
}

#[test]
fn no_saved_account_goes_straight_to_needs_sign_in() {
    let dir = tempfile::tempdir().unwrap();
    // The account list page with nobody on it, just appeared: nothing can sign in by
    // itself, so there is nothing to wait for.
    let empty = Fake::new(Some(vec!["Sign in to Steam", "SharedJSContext"]))
        .with("state", signing_in(1, Some(0)))
        .with("sign_in_page", recorded("sign_in_page_account_list"))
        .with("accounts", json!([]));
    assert_eq!(steam(&empty, &HERE, dir.path()).status().unwrap().status, Status::NeedsSignIn);
    // The form for name and password, likewise.
    let form = Fake::new(Some(vec!["Sign in to Steam", "SharedJSContext"])).with("state", signing_in(1, Some(0))).with("sign_in_page", json!({ "inputs": 2, "password_inputs": 1, "visible": true }));
    let report = steam(&form, &HERE, dir.path()).status().unwrap();
    assert_eq!(report.status, Status::NeedsSignIn);
    assert_eq!(ugos_steam::say::message(ugos_steam::say::of_status(report.status)), "Steam needs your attention");
}

#[test]
fn choosing_an_account_waits_through_the_sign_in_that_follows() {
    let dir = tempfile::tempdir().unwrap();
    let fake = Fake::new(Some(vec!["Sign in to Steam", "SharedJSContext"]))
        .with("sign_in_page", recorded("sign_in_page_account_list"))
        .with("accounts", recorded("accounts"))
        .with("choose_account", json!({ "found": true }))
        .with("state", signing_in(1, Some(30_000))) // the list, waiting: the choice is allowed
        .with("state", signing_in(3, None)) // pressed: signing in
        .with("state", json!({ "login_state": 5, "waiting_ms": null, "account": "playertwo", "offline": false, "apps": 28, "collections": true, "settings": true }));
    let report = steam(&fake, &HERE, dir.path()).choose_account("playertwo", 5, Duration::ZERO).unwrap();
    assert_eq!((report.status, report.account.as_deref()), (Status::Ready, Some("playertwo")));
}

#[test]
fn status_without_an_answering_steam() {
    let dir = tempfile::tempdir().unwrap();
    let silent = Fake::new(None);
    let status = |installed, process| steam(&silent, &Machine { installed, process }, dir.path()).status().unwrap().status;
    assert_eq!(status(false, false), Status::NotInstalled);
    assert_eq!(status(true, false), Status::NotRunning);
    assert_eq!(status(true, true), Status::Starting);
    // Answering, but its shared page is not there yet; or there, but nobody signed in and no window yet.
    let early = Fake::new(Some(vec!["Steam"]));
    assert_eq!(steam(&early, &HERE, dir.path()).status().unwrap().status, Status::Starting);
    let loading = Fake::new(Some(vec!["SharedJSContext"])).with("state", recorded("state_account_list"));
    assert_eq!(steam(&loading, &HERE, dir.path()).status().unwrap().status, Status::Starting);
}

#[test]
fn a_steam_update_that_removes_a_call_is_reported_by_name() {
    let dir = tempfile::tempdir().unwrap();
    let fake = Fake::ready().failing("folders", Error::CallMissing("SteamClient.InstallFolder.GetInstallFolders".into()));
    let error = steam(&fake, &HERE, dir.path()).folders().unwrap_err();
    assert_eq!(error.code(), "steam-call-missing");
    assert!(error.to_string().contains("SteamClient.InstallFolder.GetInstallFolders"));
    // An answer in another shape is an error too, not a panic.
    let changed = Fake::ready().with("folders", json!({ "folders": "soon" }));
    assert_eq!(code(steam(&changed, &HERE, dir.path()).folders()), "unexpected-shape");
}

#[test]
fn accounts_are_listed_and_chosen_by_account_name() {
    let dir = tempfile::tempdir().unwrap();
    let fake = Fake::account_list().with("choose_account", json!({ "found": true }));
    let s = steam(&fake, &HERE, dir.path());
    let accounts = s.accounts().unwrap();
    assert_eq!(accounts.iter().map(|a| a.account.as_str()).collect::<Vec<_>>(), ["playerone", "playertwo"]);
    assert!(accounts[0].remembered);
    // Still on the list after the press, in this pretend Steam: that is what is reported.
    let report = s.choose_account("playertwo", 2, Duration::ZERO).unwrap();
    assert_eq!(report.status, Status::NeedsAccountChoice);
    assert_eq!(fake.asked.borrow().iter().find(|(n, _)| *n == "choose_account").unwrap().1, json!({ "account": "playertwo" }));
    // Both recorded accounts share one display name, so that name alone picks nobody.
    assert_eq!(code(s.choose_account("Player", 0, Duration::ZERO)), "account-not-found");
    assert_eq!(code(s.choose_account("stranger", 0, Duration::ZERO)), "account-not-found");
    assert_eq!(fake.asked("choose_account"), 1);
}

#[test]
fn choosing_an_account_needs_the_account_list() {
    let dir = tempfile::tempdir().unwrap();
    let fake = Fake::ready();
    let s = steam(&fake, &HERE, dir.path());
    // Already signed in as that account: nothing to do.
    assert_eq!(s.choose_account("playerone", 0, Duration::ZERO).unwrap().status, Status::Ready);
    assert_eq!(code(s.choose_account("playertwo", 0, Duration::ZERO)), "no-account-choice");
}

#[test]
fn the_library_is_games_only_unless_asked_and_is_kept_for_later() {
    let dir = tempfile::tempdir().unwrap();
    let fake = Fake::ready().with("library", recorded("library"));
    let s = steam(&fake, &HERE, dir.path());
    let games = s.library(false).unwrap();
    assert_eq!((games.source.as_str(), games.stale, games.fetched_at, games.account.as_str()), ("steam", false, 1_794_325_691, "playerone"));
    assert!(games.games.iter().all(|g| g.kind == "game"));
    let poe = games.games.iter().find(|g| g.appid == 238960).unwrap();
    assert_eq!((poe.name.as_str(), poe.installed, poe.size_on_disk, poe.minutes_played, poe.last_played), ("Path of Exile", true, 71627951692, 67408, 1791152617));
    assert!(poe.cover.as_deref().unwrap().starts_with("https://shared.steamstatic.com/store_item_assets/steam/apps/238960/"));
    let wake = games.games.iter().find(|g| g.appid == 108710).unwrap();
    assert_eq!((wake.installed, wake.size_on_disk, wake.minutes_played), (false, 0, 0));
    assert!(wake.icon.is_some());

    let all = s.library(true).unwrap();
    assert!(all.games.len() > games.games.len());
    assert_eq!(all.games.iter().find(|g| g.appid == 1493710).unwrap().kind, "tool");
    assert_eq!(all.games.iter().find(|g| g.appid == 365670).unwrap().kind, "application");

    // Steam gone: the same list, marked stale, with the time it was fetched.
    let silent = Fake::new(None);
    let later = steam(&silent, &Machine { installed: true, process: false }, dir.path()).library(false).unwrap();
    assert_eq!((later.source.as_str(), later.stale, later.fetched_at), ("cache", true, 1_794_325_691));
    assert_eq!(later.games, games.games);
}

#[test]
fn with_no_steam_and_nothing_kept_the_library_comes_from_steams_files() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path().join("Steam");
    std::fs::create_dir_all(root.join("steamapps")).unwrap();
    std::fs::write(
        root.join("steamapps/appmanifest_20920.acf"),
        "\"AppState\"\n{\n\t\"appid\"\t\t\"20920\"\n\t\"name\"\t\t\"The Witcher 2\"\n\t\"StateFlags\"\t\t\"4\"\n\t\"SizeOnDisk\"\t\t\"19854651406\"\n}\n",
    )
    .unwrap();
    let silent = Fake::new(None);
    let host = Machine { installed: true, process: false };
    let mut s = steam(&silent, &host, &dir.path().join("state"));
    s.steam_root = Some(root);
    let library = s.library(false).unwrap();
    assert_eq!((library.source.as_str(), library.stale, library.fetched_at), ("local-files", true, 0));
    assert_eq!(library.games.len(), 1);
    assert_eq!((library.games[0].appid, library.games[0].installed, library.games[0].size_on_disk), (20920, true, 19854651406));
}

#[test]
fn a_game_has_hours_and_achievements_installed_or_not() {
    let dir = tempfile::tempdir().unwrap();
    // Recorded for Baldur's Gate 3, which was never installed on that PC.
    let fake = Fake::ready().with("game", recorded("game"));
    let s = steam(&fake, &HERE, dir.path());
    let bg3 = s.game(1086940).unwrap();
    assert_eq!((bg3.game.name.as_str(), bg3.game.installed, bg3.hours_played), ("Baldur's Gate 3", false, 450.1));
    let list = bg3.achievements.as_ref().unwrap();
    assert_eq!((bg3.achievements_total, bg3.achievements_unlocked), (list.len(), list.iter().filter(|a| a.unlocked).count()));
    let first = &list[0];
    assert!(first.unlocked && first.unlocked_at > 1_600_000_000 && !first.name.is_empty() && !first.description.is_empty());
    assert!(first.icon.as_deref().unwrap().starts_with("https://shared.steamstatic.com/community_assets/images/apps/1086940/"));

    let installed = Fake::ready().with("game", recorded("game_installed"));
    let poe = steam(&installed, &HERE, dir.path()).game(238960).unwrap();
    assert!(poe.game.installed && poe.hours_played > 1000.0);
    assert!(poe.achievements.unwrap().iter().any(|a| !a.unlocked && a.unlocked_at == 0));

    // Kept for when Steam is not there.
    let silent = Fake::new(None);
    let host = Machine { installed: true, process: false };
    let later = steam(&silent, &host, dir.path()).game(1086940).unwrap();
    assert_eq!((later.source.as_str(), later.stale), ("cache", true));
    assert_eq!(later.achievements, bg3.achievements);
    assert_eq!(code(steam(&silent, &host, dir.path()).game(5)), "not-running");
}

#[test]
fn a_game_never_opened_is_still_known_from_the_kept_library() {
    let dir = tempfile::tempdir().unwrap();
    let fake = Fake::ready().with("library", recorded("library"));
    steam(&fake, &HERE, dir.path()).library(false).unwrap();
    let silent = Fake::new(None);
    let host = Machine { installed: true, process: false };
    let wake = steam(&silent, &host, dir.path()).game(108710).unwrap();
    assert_eq!((wake.game.name.as_str(), wake.stale, wake.achievements.is_none(), wake.achievements_total), ("Alan Wake", true, true, 0));
}

#[test]
fn a_game_that_is_not_owned_is_refused() {
    let dir = tempfile::tempdir().unwrap();
    let fake = Fake::ready().with("game", json!({ "owned": false }));
    assert_eq!(code(steam(&fake, &HERE, dir.path()).game(4242424)), "not-owned");
}

#[test]
fn folders_have_free_space_and_the_default() {
    let dir = tempfile::tempdir().unwrap();
    let fake = Fake::ready().with("folders", recorded("folders"));
    let folders = steam(&fake, &HERE, dir.path()).folders().unwrap();
    assert_eq!(folders.len(), 2);
    assert_eq!((folders[0].index, folders[0].path.as_str(), folders[0].default), (0, "/home/player/.local/share/Steam", false));
    assert_eq!((folders[1].index, folders[1].path.as_str(), folders[1].default), (1, "/mnt/Data/SteamLibrary", true));
    assert!(folders[1].free > 300_000_000_000 && folders[1].free < folders[1].capacity);
}

#[test]
fn a_dry_install_reports_the_size_without_the_install_wizard() {
    let dir = tempfile::tempdir().unwrap();
    let fake = Fake::ready().with("install_size", recorded("install_size"));
    let report = steam(&fake, &HERE, dir.path()).install(1509960, None, true, false).unwrap();
    assert_eq!((report.name.as_str(), report.bytes_needed, report.folder, report.started, report.quiet), ("PICO PARK", 80009044, 1, false, true));
    // Only the size script ran: the one that opens Steam's wizard was not touched.
    assert_eq!(fake.asked("install"), 0);
    assert_eq!(fake.asked.borrow().iter().find(|(n, _)| *n == "install_size").unwrap().1, json!({ "appid": 1509960, "folder": null }));
}

#[test]
fn an_install_goes_ahead_when_the_manager_says_complete() {
    let dir = tempfile::tempdir().unwrap();
    let fake = Fake::ready().with("install", recorded("install_started"));
    let report = steam(&fake, &HERE, dir.path()).install(1509960, Some(1), false, false).unwrap();
    assert!(report.started && report.quiet);
    assert_eq!(fake.asked.borrow().iter().find(|(n, _)| *n == "install").unwrap().1, json!({ "appid": 1509960, "folder": 1, "licences_accepted": false }));
}

#[test]
fn an_install_through_steams_visible_wizard_says_so() {
    let dir = tempfile::tempdir().unwrap();
    // Constructed: what the script answers when it cannot find Steam's game-actions store.
    let mut loud = recorded("install_started");
    loud["quiet"] = json!(false);
    let fake = Fake::ready().with("install", loud);
    let report = steam(&fake, &HERE, dir.path()).install(1509960, None, false, false).unwrap();
    assert!(report.started && !report.quiet);
}

#[test]
fn a_licence_agreement_stops_the_install_until_the_player_accepts() {
    let dir = tempfile::tempdir().unwrap();
    // Recorded for Skyrim Script Extender: stopped before anything was started.
    let fake = Fake::ready().with("install", recorded("install_licence"));
    let error = steam(&fake, &HERE, dir.path()).install(365720, None, false, false).unwrap_err();
    assert_eq!(error.code(), "licence-required");
    let Error::LicenceRequired(licences) = error else { panic!() };
    assert_eq!(licences.len(), 1);
    assert!(licences[0].url.contains("/eula/") && !licences[0].id.is_empty());

    // The player said yes: the flag goes to the script, which accepts and carries on.
    // Constructed from the recorded successful install; accepting was never done live.
    let accepted = Fake::ready().with("install", recorded("install_started"));
    assert!(steam(&accepted, &HERE, dir.path()).install(365720, None, false, true).unwrap().started);
    assert_eq!(accepted.asked.borrow().iter().find(|(n, _)| *n == "install").unwrap().1["licences_accepted"], json!(true));
    // Accepted, and Steam still stops at its licence step: that needs a person.
    let mut stuck = recorded("install_licence");
    stuck["info"]["state"] = json!(8);
    let fake = Fake::ready().with("install", stuck);
    assert_eq!(code(steam(&fake, &HERE, dir.path()).install(365720, None, false, true)), "install-needs-attention");
}

#[test]
fn installs_that_cannot_happen_say_why() {
    let dir = tempfile::tempdir().unwrap();
    let with = |answer: Value| Fake::ready().with("install", answer);
    let install = |fake: &Fake| code(steam(fake, &HERE, dir.path()).install(7, Some(3), false, false));
    assert_eq!(install(&with(json!({ "owned": false }))), "not-owned");
    assert_eq!(install(&with(json!({ "owned": true, "installed": true }))), "already-installed");
    assert_eq!(install(&with(json!({ "owned": true, "installed": false, "folder_exists": false }))), "no-such-folder");
    let mut tight = recorded("install_licence");
    tight["stopped"] = json!("no-space");
    tight["info"]["free"] = json!(1000);
    assert_eq!(install(&with(tight)), "no-space");
    let mut not_taken = recorded("install_started");
    not_taken["loaded"] = json!(false);
    assert_eq!(install(&with(not_taken)), "install-failed");
    let mut failed = recorded("install_started");
    failed["info"]["state"] = json!(15);
    assert_eq!(install(&with(failed)), "install-failed");
    let mut key = recorded("install_licence");
    key["stopped"] = json!("attention");
    key["licences"] = json!([]);
    key["info"]["state"] = json!(4);
    assert_eq!(install(&with(key)), "install-needs-attention");
    // A dry run with too little room says so too.
    let mut small = recorded("install_size");
    small["info"]["free"] = json!(1000);
    let fake = Fake::ready().with("install_size", small);
    assert_eq!(code(steam(&fake, &HERE, dir.path()).install(7, None, true, false)), "no-space");
    // Steam not signed in: nothing is even tried.
    let list = Fake::account_list();
    assert_eq!(code(steam(&list, &HERE, dir.path()).install(7, None, false, false)), "not-ready");
    assert_eq!(list.asked("install"), 0);
}

/// A library folder with finished appmanifest files for these app ids.
fn library_folder(dir: &std::path::Path, name: &str, installed: &[u32]) -> String {
    let folder = dir.join(name);
    std::fs::create_dir_all(folder.join("steamapps")).unwrap();
    for id in installed {
        std::fs::write(folder.join(format!("steamapps/appmanifest_{id}.acf")), format!("\"AppState\"\n{{\n\t\"appid\"\t\t\"{id}\"\n\t\"StateFlags\"\t\t\"4\"\n}}\n")).unwrap();
    }
    folder.display().to_string()
}

/// The recorded library with one game changed, and Steam's library folders set.
fn library_with(appid: u32, installed: bool, elsewhere: &[&str], folders: &[String]) -> Value {
    let mut library = recorded("library");
    library["folders"] = json!(folders);
    let game = library["games"].as_array_mut().unwrap().iter_mut().find(|g| g["appid"] == appid).unwrap();
    game["installed"] = json!(installed);
    game["installed_elsewhere"] = json!(elsewhere);
    library
}

#[test]
fn a_game_installed_only_on_another_computer_is_not_installed_here() {
    let dir = tempfile::tempdir().unwrap();
    // Hand-built: what the Legion Go's Steam is expected to say about Path of Exile, which
    // is installed on the PC ("station") it found on the network and not on the Go. This
    // state could not be recorded: the development PC is the one that has the games.
    // The Go's library folder is there and has no manifest for it.
    let folders = [library_folder(dir.path(), "Steam", &[])];
    let fake = Fake::ready().with("library", library_with(238960, false, &["station"], &folders));
    let library = steam(&fake, &HERE, &dir.path().join("state")).library(false).unwrap();
    let poe = library.games.iter().find(|g| g.appid == 238960).unwrap();
    assert!(!poe.installed);
    assert_eq!(poe.installed_elsewhere, ["station"]);
    assert_eq!(poe.size_on_disk, 0);
    assert_eq!(poe.minutes_played, 67408, "hours are the account's, wherever it is installed");
    // A game on no computer at all has an empty list.
    let wake = library.games.iter().find(|g| g.appid == 108710).unwrap();
    assert!(!wake.installed && wake.installed_elsewhere.is_empty());
    // Install is still offered: the install command is not refused for it.
    let installing = Fake::ready().with("install_size", recorded("install_size"));
    assert!(steam(&installing, &HERE, dir.path()).install(238960, None, true, false).is_ok());
}

#[test]
fn the_manifest_on_disk_decides_what_is_installed_here() {
    let dir = tempfile::tempdir().unwrap();
    let state = dir.path().join("state");
    // The client claims Path of Exile is installed on this machine, but no library folder
    // has its manifest: not installed. (This is the Go's case if a Steam update changes
    // how the client marks other computers.) It is on another computer too.
    let empty = [library_folder(dir.path(), "empty", &[])];
    let fake = Fake::ready().with("library", library_with(238960, true, &["station"], &empty));
    let poe = steam(&fake, &HERE, &state).library(false).unwrap().games.into_iter().find(|g| g.appid == 238960).unwrap();
    assert!(!poe.installed && poe.size_on_disk == 0 && poe.installed_elsewhere == ["station"]);

    // The other way round: the client says no, the manifest in the second folder says yes.
    let folders = [library_folder(dir.path(), "first", &[]), library_folder(dir.path(), "second", &[108710])];
    let fake = Fake::ready().with("library", library_with(108710, false, &[], &folders));
    let wake = steam(&fake, &HERE, &state).library(false).unwrap().games.into_iter().find(|g| g.appid == 108710).unwrap();
    assert!(wake.installed);

    // A library folder that cannot be read (a drive not mounted): no conclusion from the
    // disk, so the client's word for this machine stands.
    let unreadable = [library_folder(dir.path(), "third", &[]), "/nonexistent/library".to_string()];
    let fake = Fake::ready().with("library", library_with(238960, true, &[], &unreadable));
    let poe = steam(&fake, &HERE, &state).library(false).unwrap().games.into_iter().find(|g| g.appid == 238960).unwrap();
    assert!(poe.installed && poe.size_on_disk > 0);
}

#[test]
fn game_details_follow_the_same_rule() {
    let dir = tempfile::tempdir().unwrap();
    // Recorded for Path of Exile on the PC that has it, then turned into the Go's view.
    let mut details = recorded("game_installed");
    details["folders"] = json!([library_folder(dir.path(), "Steam", &[])]);
    details["overview"]["installed_elsewhere"] = json!(["station"]);
    let fake = Fake::ready().with("game", details);
    let poe = steam(&fake, &HERE, &dir.path().join("state")).game(238960).unwrap();
    assert!(!poe.game.installed);
    assert_eq!(poe.game.installed_elsewhere, ["station"]);
    assert!(poe.achievements_total > 0);
    assert_eq!(serde_json::to_value(&poe.game).unwrap()["installed_elsewhere"], json!(["station"]));
}

#[test]
fn a_library_kept_before_this_field_existed_still_reads() {
    let dir = tempfile::tempdir().unwrap();
    std::fs::write(
        dir.path().join("library.json"),
        r#"{"fetched_at":5,"account":"playerone","apps":[{"appid":10,"name":"Old","kind":"game","installed":true,"size_on_disk":1,"minutes_played":2,"last_played":3,"cover":null,"icon":null,"in_games":true}]}"#,
    )
    .unwrap();
    let silent = Fake::new(None);
    let host = Machine { installed: true, process: false };
    let library = steam(&silent, &host, dir.path()).library(false).unwrap();
    assert_eq!((library.source.as_str(), library.games.len()), ("cache", 1));
    assert!(library.games[0].installed_elsewhere.is_empty());
}

#[test]
fn uninstall_reports_what_happened() {
    let dir = tempfile::tempdir().unwrap();
    // Recorded when PICO PARK was removed in the live check.
    let fake = Fake::ready().with("uninstall", recorded("uninstall"));
    assert_eq!(steam(&fake, &HERE, dir.path()).uninstall(1509960).unwrap(), "PICO PARK");
    // As seen when asking again once it was gone.
    let gone = Fake::ready().with("uninstall", json!({ "owned": true, "installed": false }));
    assert_eq!(code(steam(&gone, &HERE, dir.path()).uninstall(1509960)), "app-not-installed");
    let stuck = Fake::ready().with("uninstall", json!({ "owned": true, "installed": true, "removed": false, "name": "X" }));
    assert_eq!(code(steam(&stuck, &HERE, dir.path()).uninstall(1)), "timeout");
}

#[test]
fn downloads_show_the_queue_idle_and_busy() {
    let dir = tempfile::tempdir().unwrap();
    let idle = Fake::ready().with("downloads", recorded("downloads"));
    let d = steam(&idle, &HERE, dir.path()).downloads().unwrap();
    assert_eq!((d.state.as_str(), d.appid, d.bytes_per_second), ("None", 0, 0));
    let scheduled = d.items.iter().find(|i| i.appid == 238960).unwrap();
    assert!(!scheduled.active && scheduled.scheduled_for > 0 && scheduled.queue_index == -1);

    // Recorded right after `install 1509960`. Steam gave no time estimate at that
    // moment, which once made this answer unreadable.
    let busy = Fake::ready().with("downloads", recorded("downloads_active"));
    let d = steam(&busy, &HERE, dir.path()).downloads().unwrap();
    assert_eq!(d.appid, 1509960);
    assert!(d.state == "Starting" && d.items.iter().any(|i| i.appid == 1509960 && i.active));
    assert_eq!(d.seconds_left, -1);
}

#[test]
fn pausing_asks_steam_and_shows_the_queue_again() {
    let dir = tempfile::tempdir().unwrap();
    let fake = Fake::ready().with("enable_downloads", json!(true)).with("downloads", recorded("downloads"));
    steam(&fake, &HERE, dir.path()).set_downloads(false).unwrap();
    assert_eq!(fake.asked.borrow().iter().find(|(n, _)| *n == "enable_downloads").unwrap().1, json!({ "on": false }));
}

#[test]
fn launch_refuses_what_cannot_run() {
    let dir = tempfile::tempdir().unwrap();
    // Constructed: a successful launch was never run on the development PC.
    let fake = Fake::ready().with("launch", json!({ "owned": true, "installed": true, "name": "Path of Exile", "since": 41, "listening": ["start", "task", "request", "error", "end", "lifetime"] }));
    let launched = steam(&fake, &HERE, dir.path()).launch(238960).unwrap();
    assert_eq!((launched.name.as_str(), launched.since), ("Path of Exile", 41));
    // Recorded: asked for a game that is not installed (nothing was started).
    let missing = Fake::ready().with("launch", json!({ "owned": true, "installed": false }));
    assert_eq!(code(steam(&missing, &HERE, dir.path()).launch(108710)), "app-not-installed");
    let stranger = Fake::ready().with("launch", json!({ "owned": false }));
    assert_eq!(code(steam(&stranger, &HERE, dir.path()).launch(1)), "not-owned");
}

// The launch tests below are built from the order of events described in the report
// from the Legion Go (first Windows game on that Steam: Proton prefix created over about
// 30 seconds, then the game), and from the callback arguments Steam's own interface code
// uses. None of these sequences was recorded from a real launch.

const EVERY_EVENT: [&str; 6] = ["start", "task", "request", "error", "end", "lifetime"];
const APP: u32 = 1509960;
const QUICK: Patience = Patience { tick: Duration::ZERO, preparing: 50, settle: 3, grace: 3 };

/// One look at Steam during a launch of APP: is it listed as running, is game action 7
/// active (with this task), and which events have happened so far.
fn look(running: bool, active_task: Option<&str>, events: &[Value]) -> Value {
    let active: Vec<Value> = active_task.iter().map(|task| json!({ "id": 7, "app": APP.to_string(), "action": "LaunchApp", "task": task })).collect();
    json!({ "listening": EVERY_EVENT, "last": events.len(), "running": running, "active": active, "events": events })
}

fn event(n: u64, kind: &str, detail: Option<&str>) -> Value {
    let app = if kind == "end" { Value::Null } else { json!(APP.to_string()) };
    json!({ "n": n, "kind": kind, "id": if kind == "lifetime" { 0 } else { 7 }, "app": app, "action": "LaunchApp", "detail": detail, "extra": null })
}

fn wait(fake: &Fake, stop: bool, patience: Patience) -> (Result<Ended>, Vec<Phase>) {
    let dir = tempfile::tempdir().unwrap();
    let mut phases = Vec::new();
    let stop = AtomicBool::new(stop);
    let result = steam(fake, &HERE, dir.path()).wait_for_exit(APP, 0, &stop, patience, &mut |p: &Phase| phases.push(p.clone()));
    (result, phases)
}

fn preparing(task: Option<&str>) -> Phase {
    Phase::Preparing { task: task.map(String::from), percent: None, skippable: false }
}

#[test]
fn the_wait_lasts_through_first_time_setup() {
    let start = event(1, "start", None);
    let setup = event(2, "task", Some("RunningInstallScript"));
    let process = event(4, "task", Some("CreatingProcess"));
    let end = event(5, "end", None);
    let fake = Fake::ready()
        // Play was pressed; Steam has not begun yet.
        .with("launch_state", look(false, None, &[]))
        // First-time setup. A setup step runs as the app: it shows as running, then not.
        .with("launch_state", look(false, Some("RunningInstallScript"), &[start.clone(), setup.clone()]))
        .with("launch_state", look(true, Some("RunningInstallScript"), &[start.clone(), setup.clone(), event(3, "lifetime", Some("running"))]))
        .with("launch_state", look(false, Some("RunningInstallScript"), &[start.clone(), setup.clone()]))
        .with("launch_state", look(false, Some("CreatingProcess"), &[start.clone(), setup.clone(), process.clone()]))
        // The action is over; the game's window is a moment away.
        .with("launch_state", look(false, None, &[start.clone(), setup.clone(), process.clone(), end.clone()]))
        // The game runs, then the player closes it.
        .with("launch_state", look(true, None, std::slice::from_ref(&end)))
        .with("launch_state", look(true, None, &[]))
        .with("launch_state", look(false, None, &[]));
    let (result, phases) = wait(&fake, false, QUICK);
    assert_eq!(result.unwrap(), Ended::Exited);
    // The setup step going away (4th look) did not end the wait: all nine looks were needed.
    assert_eq!(fake.asked("launch_state"), 9);
    assert_eq!(phases, [preparing(None), preparing(Some("RunningInstallScript")), preparing(Some("CreatingProcess")), Phase::Starting, Phase::Running, Phase::Ended]);
    // What the screen is given for them, in order.
    let words: Vec<&str> = phases.iter().map(|p| ugos_steam::say::message(p.name())).collect();
    assert_eq!(words, ["Preparing the game", "Preparing the game", "Preparing the game", "Starting the game", "The game is running", "The game was closed"]);
}

#[test]
fn a_normal_start_then_exit_is_reported_as_exited() {
    let start = event(1, "start", None);
    let end = event(2, "end", None);
    let fake = Fake::ready()
        .with("launch_state", look(false, Some("CreatingProcess"), std::slice::from_ref(&start)))
        .with("launch_state", look(true, None, &[start.clone(), end.clone()]))
        .with("launch_state", look(true, None, &[]))
        .with("launch_state", look(false, None, &[]));
    let (result, phases) = wait(&fake, false, QUICK);
    assert_eq!(result.unwrap(), Ended::Exited);
    assert_eq!(phases, [preparing(Some("CreatingProcess")), Phase::Running, Phase::Ended]);
    assert_eq!(fake.asked("cancel_launch"), 0);
}

#[test]
fn a_launch_steam_cannot_complete_is_a_failure_with_steams_error() {
    let start = event(1, "start", None);
    let error = json!({ "n": 2, "kind": "error", "id": 7, "app": APP.to_string(), "action": "LaunchApp", "detail": "AppError_51", "extra": "missing executable" });
    let fake = Fake::ready()
        .with("launch_state", look(false, Some("CreatingProcess"), std::slice::from_ref(&start)))
        .with("launch_state", look(false, None, &[start.clone(), error, event(3, "end", None)]));
    let (result, phases) = wait(&fake, false, QUICK);
    let failed = result.unwrap_err();
    assert_eq!(failed.code(), "launch-failed");
    let Error::LaunchFailed { steam_error, detail, .. } = failed else { panic!() };
    assert_eq!((steam_error.as_deref(), detail.as_deref()), (Some("AppError_51"), Some("missing executable")));
    assert!(matches!(phases.last(), Some(Phase::Failed { .. })));
}

#[test]
fn a_launch_cancelled_inside_steam_is_not_mistaken_for_a_game_that_ran() {
    // Steam asks about a licence in its own window; the player declines there. The
    // action ends, no error, and no game ever appears.
    let start = event(1, "start", None);
    let ask = event(2, "request", Some("ShowEula"));
    let fake = Fake::ready()
        .with("launch_state", look(false, Some("ShowEula"), &[start.clone(), ask.clone()]))
        .with("launch_state", look(false, None, &[start.clone(), ask.clone(), event(3, "end", None)]))
        .with("launch_state", look(false, None, &[]));
    let (result, phases) = wait(&fake, false, QUICK);
    assert_eq!(code(result), "launch-did-not-start");
    assert_eq!(phases[0], Phase::NeedsAttention { task: Some("ShowEula".into()) });
    assert_eq!(ugos_steam::say::message(phases[0].name()), "Steam needs your attention");
    // It waited the settle time (3 looks) for a game to appear before giving up.
    assert_eq!(fake.asked("launch_state"), 2 + 3);
}

#[test]
fn ending_the_wait_calls_off_a_launch_that_is_still_being_prepared() {
    let start = event(1, "start", None);
    let fake = Fake::ready()
        .with("cancel_launch", json!({ "was_running": false }))
        .with("launch_state", look(false, Some("RunningInstallScript"), std::slice::from_ref(&start)))
        .with("launch_state", look(false, None, &[start.clone(), event(2, "end", None)]))
        .with("launch_state", look(false, None, &[]));
    // First let it see the action, then ask it to stop.
    let dir = tempfile::tempdir().unwrap();
    let stop = AtomicBool::new(false);
    let s = steam(&fake, &HERE, dir.path());
    let mut looks = 0;
    let result = s.wait_for_exit(APP, 0, &stop, QUICK, &mut |_| {
        looks += 1;
        stop.store(true, std::sync::atomic::Ordering::SeqCst);
    });
    assert_eq!(result.unwrap(), Ended::Stopped);
    // The game action Steam named was cancelled by its number.
    assert_eq!(fake.asked.borrow().iter().find(|(n, _)| *n == "cancel_launch").unwrap().1, json!({ "appid": APP, "action": 7 }));
}

#[test]
fn ending_the_wait_ends_a_running_game() {
    let fake = Fake::ready().with("cancel_launch", json!({ "was_running": true })).with("launch_state", look(true, None, &[])).with("launch_state", look(false, None, &[]));
    let (result, phases) = wait(&fake, true, QUICK);
    assert_eq!(result.unwrap(), Ended::Stopped);
    assert_eq!(fake.asked("cancel_launch"), 1);
    // "Closing the game" is said before anything else, and it took two looks for the
    // game to be really gone.
    assert_eq!(phases, [Phase::Stopping]);
    assert_eq!(ugos_steam::say::message(phases[0].name()), "Closing the game");
    assert_eq!(fake.asked("launch_state"), 2);
    // A game that does not go within the grace time is reported as still there.
    let stubborn = Fake::ready().with("cancel_launch", json!({ "was_running": true })).with("launch_state", look(true, None, &[]));
    assert_eq!(wait(&stubborn, true, QUICK).0.unwrap(), Ended::StillRunning);
}

#[test]
fn the_wait_reports_shader_processing_with_its_percentage_as_it_grows() {
    // The first launch from the Legion Go's log (2026-11-10, 22:55 UTC): cloud sync, then
    // shader processing, then the game. The counts are made up; the log has none.
    let start = event(1, "start", None);
    let cloud = event(2, "task", Some("SynchronizingCloud"));
    let shaders = event(3, "request", Some("ProcessingShaderCache"));
    let so_far = [start.clone(), cloud.clone(), shaders.clone()];
    let at = |done: u32| {
        let mut l = look(false, Some("ProcessingShaderCache"), &so_far);
        l["progress"] = json!({ "done": done, "total": 200 });
        l
    };
    let fake = Fake::ready()
        .with("launch_state", look(false, Some("SynchronizingCloud"), &[start.clone(), cloud.clone()]))
        .with("launch_state", at(20))
        .with("launch_state", at(21)) // still 10 percent: no new line
        .with("launch_state", at(150))
        .with("launch_state", look(true, None, &[event(4, "end", None)]))
        .with("launch_state", look(false, None, &[]));
    let (result, phases) = wait(&fake, false, QUICK);
    assert_eq!(result.unwrap(), Ended::Exited);
    let shader = |percent| Phase::Preparing { task: Some("ProcessingShaderCache".into()), percent: Some(percent), skippable: true };
    assert_eq!(phases, [preparing(Some("SynchronizingCloud")), shader(10), shader(75), Phase::Running, Phase::Ended]);
    // Steam's window was never called for: no "needs attention" anywhere.
    assert!(!phases.iter().any(|p| matches!(p, Phase::NeedsAttention { .. })));
    let lines: Vec<Value> = phases.iter().map(|p| ugos_steam::launch::line(p, APP, "PICO PARK")).collect();
    assert_eq!(lines[1]["task_message"], "Preparing graphics for the first run");
    assert_eq!((lines[1]["percent"].as_u64(), lines[2]["percent"].as_u64()), (Some(10), Some(75)));
    assert!(lines[0].get("percent").is_none());
}

#[test]
fn skipping_asks_steam_only_while_shaders_are_being_processed() {
    let dir = tempfile::tempdir().unwrap();
    // Constructed: the script found the launch at shader processing and answered it.
    let fake = Fake::ready().with("launch_skip", json!({ "skipped": true, "task": "ProcessingShaderCache", "action": 7 }));
    assert_eq!(steam(&fake, &HERE, dir.path()).skip_launch_step(APP).unwrap(), "ProcessingShaderCache");
    // What the script is given: the step it may skip, and the answer Steam's Skip button gives.
    assert_eq!(fake.asked.borrow().iter().find(|(n, _)| *n == "launch_skip").unwrap().1, json!({ "appid": APP, "task": "ProcessingShaderCache", "answer": "SkipShaders" }));
    // At another step, or with no launch going: nothing was sent, and it says so.
    let other = Fake::ready().with("launch_skip", json!({ "skipped": false, "task": "SynchronizingCloud" }));
    let error = steam(&other, &HERE, dir.path()).skip_launch_step(APP).unwrap_err();
    assert_eq!(error.code(), "nothing-to-skip");
    assert!(error.to_string().contains("SynchronizingCloud"));
    let idle = Fake::ready().with("launch_skip", json!({ "skipped": false, "task": null }));
    assert_eq!(code(steam(&idle, &HERE, dir.path()).skip_launch_step(APP)), "nothing-to-skip");
    // The script itself sends nothing unless the step matches (the check is before the call).
    let source = ugos_steam::js::launch_skip(APP).source();
    let (check, call) = (source.find("now.task !== ARG.task").unwrap(), source.find("ContinueGameAction(now.id").unwrap());
    assert!(check < call);
}

#[test]
fn stopping_a_game_can_wait_until_it_has_really_closed() {
    let dir = tempfile::tempdir().unwrap();
    let app = json!([{ "appid": APP, "name": "PICO PARK" }]);
    // Constructed: still listed twice after being told to close, then gone.
    let fake = Fake::ready().with("stop_app", json!({ "running": true, "name": "PICO PARK" })).with("running", app.clone()).with("running", app.clone()).with("running", recorded("running"));
    let s = steam(&fake, &HERE, dir.path());
    assert!(s.stop_app(APP).unwrap());
    assert!(s.wait_until_closed(APP, Duration::ZERO, 5).unwrap());
    let stubborn = Fake::ready().with("running", app);
    assert!(!steam(&stubborn, &HERE, dir.path()).wait_until_closed(APP, Duration::ZERO, 3).unwrap());
}

#[test]
fn preparing_for_too_long_is_called_off_with_a_clear_error() {
    let fake = Fake::ready().with("cancel_launch", json!({ "was_running": false })).with("launch_state", look(false, Some("UpdatingContent"), &[event(1, "start", None)]));
    let (result, _) = wait(&fake, false, Patience { preparing: 5, ..QUICK });
    let error = result.unwrap_err();
    assert_eq!(error.code(), "launch-timeout");
    assert!(error.to_string().contains("UpdatingContent"), "{error}");
    assert_eq!(fake.asked("cancel_launch"), 1);
}

#[test]
fn a_launch_steam_never_takes_up_is_reported() {
    let fake = Fake::ready().with("launch_state", look(false, None, &[]));
    assert_eq!(code(wait(&fake, false, QUICK).0), "launch-did-not-start");
}

#[test]
fn running_and_status_also_say_what_is_being_prepared() {
    let dir = tempfile::tempdir().unwrap();
    // Constructed: the shape `activity` gives for a launch in its setup step.
    let busy = json!([{ "appid": APP, "name": "PICO PARK", "action": "LaunchApp", "task": "RunningInstallScript" }]);
    let fake = Fake::ready().with("running", recorded("running")).with("activity", busy);
    let s = steam(&fake, &HERE, dir.path());
    assert!(s.running().unwrap().is_empty());
    let preparing = s.preparing();
    assert_eq!((preparing[0].appid, preparing[0].task.as_deref()), (APP, Some("RunningInstallScript")));
    let status = serde_json::to_value(s.status().unwrap()).unwrap();
    assert_eq!(status["status"], "ready");
    assert_eq!(status["preparing"][0]["name"], "PICO PARK");
    // A Steam that cannot be asked: no extra information, and no failure.
    let quiet = Fake::ready().failing("activity", Error::CallMissing("SteamClient.Apps.GetActiveGameActions".into()));
    assert!(steam(&quiet, &HERE, dir.path()).preparing().is_empty());
    assert!(serde_json::to_value(steam(&quiet, &HERE, dir.path()).status().unwrap()).unwrap().get("preparing").is_none());
}

// The settings tests use the values traced on the development PC across a sign-in
// (research/steam-check, probe_r): before sign-in the client's settings have 86 keys and
// neither setting is among them; after it 270 keys, overlay on, "disable all toasts" off.

const FAST: Retry = Retry { rounds: 4, hold: 3, tick: Duration::ZERO };

fn setting(value: Option<bool>) -> Value {
    json!({ "loaded": value.is_some(), "value": value, "keys": if value.is_some() { 270 } else { 86 } })
}

#[test]
fn a_setting_is_read_only_once_the_client_has_it() {
    let dir = tempfile::tempdir().unwrap();
    let fake = Fake::ready().with("overlay_read", setting(Some(true))).with("toasts_read", setting(Some(false)));
    let s = steam(&fake, &HERE, dir.path());
    assert!(s.overlay().unwrap());
    assert!(s.toasts().unwrap(), "\"disable all toasts\" off means toasts are on");
    let early = Fake::ready().with("overlay_read", setting(None));
    assert_eq!(code(steam(&early, &HERE, dir.path()).overlay()), "not-ready");
}

#[test]
fn a_setting_that_takes_at_once_needs_one_send_and_is_read_back() {
    let dir = tempfile::tempdir().unwrap();
    let fake = Fake::ready().with("overlay_read", setting(Some(true))).with("overlay_read", setting(Some(false))).with("overlay_send", json!(true));
    let applied = steam(&fake, &HERE, dir.path()).set_overlay(false, FAST).unwrap();
    assert_eq!(serde_json::to_value(&applied).unwrap(), json!({ "enabled": false, "applied": true, "attempts": 1 }));
    assert_eq!(fake.asked.borrow().iter().find(|(n, _)| *n == "overlay_send").unwrap().1, json!({ "message": "oPoBAA==", "name": "enable_overlay", "value": false }));
    // One read before sending, three matching reads after.
    assert_eq!(fake.asked("overlay_read"), 4);
}

#[test]
fn a_setting_already_at_the_value_is_not_sent() {
    let dir = tempfile::tempdir().unwrap();
    let fake = Fake::ready().with("toasts_read", setting(Some(true)));
    let applied = steam(&fake, &HERE, dir.path()).set_toasts(false, FAST).unwrap();
    assert_eq!((applied.enabled, applied.applied, applied.attempts), (false, true, 0));
    assert_eq!(fake.asked("toasts_send"), 0);
}

#[test]
fn a_setting_overwritten_after_sign_in_is_sent_again() {
    let dir = tempfile::tempdir().unwrap();
    // The case from the Legion Go: toasts are turned off right after sign-in, the read
    // back agrees, and then the account's own settings arrive and turn them on again.
    let fake = Fake::ready()
        .with("toasts_read", setting(None)) // not loaded yet: wait
        .with("toasts_read", setting(Some(false))) // loaded, toasts on: send
        .with("toasts_read", setting(Some(true))) // took
        .with("toasts_read", setting(Some(false))) // overwritten: this round failed
        .with("toasts_read", setting(Some(false))) // next round: still on, send again
        .with("toasts_read", setting(Some(true)))
        .with("toasts_send", json!(true));
    let applied = steam(&fake, &HERE, dir.path()).set_toasts(false, FAST).unwrap();
    assert_eq!((applied.enabled, applied.applied, applied.attempts), (false, true, 2));
    assert_eq!(fake.asked.borrow().iter().find(|(n, _)| *n == "toasts_send").unwrap().1, json!({ "message": "gPcCAQ==", "name": "disable_all_toasts", "value": true }));
}

#[test]
fn a_setting_that_never_holds_is_reported_as_not_applied() {
    let dir = tempfile::tempdir().unwrap();
    // Steam takes the request and the value never changes.
    let deaf = Fake::ready().with("overlay_read", setting(Some(true))).with("overlay_send", json!(true));
    let error = steam(&deaf, &HERE, dir.path()).set_overlay(false, FAST).unwrap_err();
    assert_eq!(error.code(), "setting-not-applied");
    let Error::SettingNotApplied { enabled, attempts, .. } = error else { panic!() };
    assert_eq!((enabled, attempts), (Some(true), 4));
    // For toasts the value is reported in the command's sense: still on.
    let deaf = Fake::ready().with("toasts_read", setting(Some(false))).with("toasts_send", json!(true));
    let Error::SettingNotApplied { enabled, attempts, .. } = steam(&deaf, &HERE, dir.path()).set_toasts(false, FAST).unwrap_err() else { panic!() };
    assert_eq!((enabled, attempts), (Some(true), 4));
    // The settings never arrive at all: nothing is sent, and it is still "not applied".
    let never = Fake::ready().with("overlay_read", setting(None));
    let Error::SettingNotApplied { enabled, attempts, .. } = steam(&never, &HERE, dir.path()).set_overlay(false, FAST).unwrap_err() else { panic!() };
    assert_eq!((enabled, attempts), (None, 0));
    assert_eq!(never.asked("overlay_send"), 0);
}

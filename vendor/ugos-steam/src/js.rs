//! Every piece of JavaScript that touches Steam's internal interface lives here.
//!
//! VERIFIED ON: Steam client build "Oct 21 2026 21:09:51", version 1792618285,
//! interface SteamClient023, Linux (see `research/steam-check/findings.md`).
//!
//! None of this is a public interface. When a Steam update breaks a call, the command
//! that uses it fails with `steam-call-missing` (the function is gone) or
//! `unexpected-shape` (it answers differently); the name in the message is the name
//! of the script below. Fix it here and update the line above.
//!
//! A script's body runs inside an async function in Steam's shared page, with:
//!   ARG            the arguments, as a JSON value
//!   need(path)     throws `call-missing` unless that global path exists
//!   wait(p, what)  the promise's result, or throws `timeout` after 8 s (third argument: ms)
//!   sleep(ms)
//! It returns plain data. Deciding what the data means is done in Rust.

use serde_json::Value;

/// Written into every answer the CLI gives for `version`, and into the docs.
pub const VERIFIED_ON: &str = "Steam client build Oct 21 2026 (version 1792618285, SteamClient023)";

/// Which of Steam's pages a script runs in.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Page {
    /// "SharedJSContext": always there while Steam runs; holds the library and SteamClient.
    Shared,
    /// The "Sign in to Steam" window: account list, or the form for name and password.
    SignIn,
}

pub struct Script {
    pub name: &'static str,
    pub page: Page,
    /// How long the whole script may take, in seconds.
    pub seconds: u64,
    body: &'static str,
    arg: Value,
}

impl Script {
    fn new(name: &'static str, page: Page, seconds: u64, body: &'static str, arg: Value) -> Script {
        Script { name, page, seconds, body, arg }
    }

    pub fn arg(&self) -> &Value {
        &self.arg
    }

    /// The expression handed to DevTools. It always evaluates to `{ok: ...}` or
    /// `{err: code, detail: text}`, never to an exception.
    pub fn source(&self) -> String {
        format!(
            r#"(async () => {{
const ARG = {arg};
const need = (path) => {{ let o = globalThis; for (const p of path.split('.')) o = (o === undefined || o === null) ? undefined : o[p]; if (o === undefined || o === null) throw {{ code: 'call-missing', what: path }}; return o; }};
const wait = (promise, what, ms = 8000) => Promise.race([promise, new Promise((_, no) => setTimeout(() => no({{ code: 'timeout', what }}), ms))]);
const sleep = (ms) => new Promise((yes) => setTimeout(yes, ms));
try {{ return {{ ok: await (async () => {{
{body}
}})() }}; }} catch (e) {{ return {{ err: (e && e.code) ? e.code : 'script-failed', detail: String((e && (e.what || e.message)) || e) }}; }}
}})()"#,
            arg = self.arg,
            body = self.body
        )
    }
}

// `js_overview.inc`: the fields every command reports about one app, from Steam's app
// overview object. `js_install_info.inc`: what the install manager says, in our words.

/// Is anyone signed in, and is the library loaded. Works in every state of the client.
///
/// `login_state` is the client's own sign-in state. Recorded on the development PC:
/// 1 while it sits at its account list waiting for a choice, 3 and then 4 while it
/// signs in, 5 when signed in. The meaning of other numbers is not known.
pub fn state() -> Script {
    Script::new(
        "state",
        Page::Shared,
        10,
        r#"
const user = (typeof App !== 'undefined' && App.m_CurrentUser) ? App.m_CurrentUser : null;
let apps = 0; try { apps = appStore.allApps.length; } catch (e) {}
let collections = false; try { collections = collectionStore.allGamesCollection.allApps.length >= 0; } catch (e) {}
let settings = false; try { settings = typeof settingsStore.m_ClientSettings.enable_overlay === 'boolean'; } catch (e) {}
const login_state = (typeof App !== 'undefined') ? (App.m_eLoginState ?? null) : null;
// How long the client has been sitting at "waiting for the player" (login state 1), as
// seen by these looks: the mark is set at the first look that finds it there and
// dropped when it leaves. It lives in this page, so it starts over with Steam.
if (login_state === 1) { if (!window.__ugos_waiting_since) window.__ugos_waiting_since = Date.now(); } else { window.__ugos_waiting_since = 0; }
const waiting_ms = window.__ugos_waiting_since ? Date.now() - window.__ugos_waiting_since : null;
return { login_state, waiting_ms,
         account: (user && user.strAccountName) || '', offline: !!(user && user.bIsOfflineMode), apps, collections, settings };
"#,
        Value::Null,
    )
}

/// What the sign-in window is showing: the saved accounts to pick from, or a form.
pub fn sign_in_page() -> Script {
    Script::new(
        "sign_in_page",
        Page::SignIn,
        10,
        r#"
const inputs = [...document.querySelectorAll('input')].map((i) => i.type);
return { inputs: inputs.length, password_inputs: inputs.filter((t) => t === 'password').length,
         visible: document.visibilityState === 'visible' };
"#,
        Value::Null,
    )
}

/// The accounts Steam remembers on this machine. Names only: no tokens are exposed by this call.
pub fn accounts() -> Script {
    Script::new(
        "accounts",
        Page::Shared,
        10,
        r#"
need('SteamClient.User.GetLoginUsers');
const users = await wait(SteamClient.User.GetLoginUsers(), 'GetLoginUsers');
if (!Array.isArray(users)) throw { code: 'shape', what: 'GetLoginUsers did not return a list' };
return users.map((u) => ({ account: u.accountName, persona: u.personaName, remembered: !!u.rememberPassword, last_login: u.rtLastLogin || 0 }));
"#,
        Value::Null,
    )
}

/// Presses the named account in Steam's own account list, as a person would.
pub fn choose_account(account: &str) -> Script {
    Script::new(
        "choose_account",
        Page::SignIn,
        10,
        r#"
const leaf = [...document.querySelectorAll('*')].find((e) => e.children.length === 0 && e.textContent.trim() === ARG.account);
if (!leaf) return { found: false };
const tile = leaf.closest('.Focusable');
if (!tile) throw { code: 'call-missing', what: 'the account tile (.Focusable) in the sign-in window' };
tile.click();
return { found: true };
"#,
        serde_json::json!({ "account": account }),
    )
}

/// Everything the account owns. `in_games` marks what Steam itself files under games
/// (its "my-games" collection); the rest are applications, tools and the like.
pub fn library() -> Script {
    const BODY: &str = concat!(
        r#"
need('collectionStore.allGamesCollection.allApps'); need('collectionStore.allAppsCollection.allApps'); need('appStore.GetAppOverviewByAppID');
"#,
        include_str!("js_overview.inc"),
        r#"
const games = new Set(collectionStore.allGamesCollection.allApps.map((a) => a.appid));
return { account: (App.m_CurrentUser && App.m_CurrentUser.strAccountName) || '', folders: await library_paths(),
         games: collectionStore.allAppsCollection.allApps.map((a) => ({ ...overview(a), in_games: games.has(a.appid) })) };
"#
    );
    Script::new("library", Page::Shared, 30, BODY, Value::Null)
}

pub fn game(appid: u32) -> Script {
    const BODY: &str = concat!(
        r#"
need('appStore.GetAppOverviewByAppID'); need('SteamClient.Apps.GetMyAchievementsForApp');
"#,
        include_str!("js_overview.inc"),
        r#"
const a = appStore.GetAppOverviewByAppID(ARG.appid);
if (!a) return { owned: false };
const r = await wait(SteamClient.Apps.GetMyAchievementsForApp(String(ARG.appid)), 'GetMyAchievementsForApp', 20000);
const list = r && r.data && r.data.rgAchievements;
return { owned: true, overview: overview(a), folders: await library_paths(),
  achievements: Array.isArray(list) ? list.map((x) => ({ id: x.strID, name: x.strName, description: x.strDescription, icon: x.strImage || null,
    unlocked: !!x.bAchieved, unlocked_at: x.rtUnlocked || 0, global_percent: x.flAchieved || 0, hidden: !!x.bHidden })) : null };
"#
    );
    Script::new("game", Page::Shared, 30, BODY, serde_json::json!({ "appid": appid }))
}

pub fn folders() -> Script {
    Script::new(
        "folders",
        Page::Shared,
        15,
        r#"
need('SteamClient.InstallFolder.GetInstallFolders');
const folders = await wait(SteamClient.InstallFolder.GetInstallFolders(), 'GetInstallFolders');
if (!Array.isArray(folders)) throw { code: 'shape', what: 'GetInstallFolders did not return a list' };
return folders.map((f) => ({ index: f.nFolderIndex, path: f.strFolderPath, label: f.strUserLabel || '', capacity: f.nCapacity || 0,
  free: f.nFreeSpace || 0, default: !!f.bIsDefaultFolder, mounted: !!f.bIsMounted, apps: Array.isArray(f.vecApps) ? f.vecApps.length : 0 }));
"#,
        Value::Null,
    )
}


/// How much room an app needs and how much the chosen folder has, without opening
/// Steam's install wizard: the app is put on the install manager's list, read, and
/// taken off again. No window is created for this (checked with the compositor's
/// window list). Nothing can be installed from this state; see `install`.
pub fn install_size(appid: u32, folder: Option<u32>) -> Script {
    const BODY: &str = concat!(
        r#"
for (const f of ['SetAppList', 'GetInstallManagerInfo', 'SetInstallFolder', 'CancelInstall']) need('SteamClient.Installs.' + f);
need('SteamClient.InstallFolder.GetInstallFolders'); need('appStore.GetAppOverviewByAppID');
"#,
        include_str!("js_overview.inc"),
        include_str!("js_install_info.inc"),
        r#"
const a = appStore.GetAppOverviewByAppID(ARG.appid);
if (!a) return { owned: false };
if (here(a)) return { owned: true, installed: true };
const folders = await wait(SteamClient.InstallFolder.GetInstallFolders(), 'GetInstallFolders');
const wanted = (ARG.folder === null) ? (folders.find((f) => f.bIsDefaultFolder) || folders[0] || {}).nFolderIndex : ARG.folder;
if (!folders.some((f) => f.nFolderIndex === wanted)) return { owned: true, installed: false, folder_exists: false };
await SteamClient.Installs.SetAppList([ARG.appid]);
let i = await info();
for (let n = 0; n < 40 && !i.apps.includes(ARG.appid); n++) { await sleep(250); i = await info(); }
const loaded = i.apps.includes(ARG.appid);
if (loaded) { await SteamClient.Installs.SetInstallFolder(wanted); await sleep(300); i = await info(); }
SteamClient.Installs.CancelInstall();
await sleep(300);
return { owned: true, installed: false, folder_exists: true, loaded, name: a.display_name, info: i };
"#
    );
    Script::new("install_size", Page::Shared, 30, BODY, serde_json::json!({ "appid": appid, "folder": folder }))
}

/// Installs an owned app with no Steam window.
///
/// Steam only installs through its install wizard: `OpenInstallWizard([appid], "0")`
/// (the second argument is the client id; "0" is this machine) puts the install manager
/// in state 7, then `SetInstallFolder` and `ContinueInstall` hand the app to the
/// download queue. Opening the wizard also calls back into Steam's own interface (its
/// game-actions store, method OnShowInstallWizard), which then opens an "Install"
/// dialog and with it Steam's main window. Steam's interface has its own silent case in
/// that method: when the app is the one it expects and neither of its two "show
/// something first?" checks says yes, it starts the install without a dialog. This
/// script puts the store in that case for the length of the call: it names the app as
/// the expected one, answers both checks with "no", and takes over the "start" step so
/// the folder can be set first. All three are put back at the end. They are changes to
/// objects in Steam's memory, never to its files.
///
/// The store is found among Steam's loaded script modules by the name of its field
/// `m_unAppIDExpectedInstall`. If a Steam update moves it, the install still goes
/// ahead through the plain wizard and the answer says `quiet: false`: a Steam window
/// will have shown.
///
/// Licence agreements are asked for before anything is started, so Steam's own
/// agreement window never comes up either.
pub fn install(appid: u32, folder: Option<u32>, licences_accepted: bool) -> Script {
    const BODY: &str = concat!(
        r#"
for (const f of ['OpenInstallWizard', 'GetInstallManagerInfo', 'SetInstallFolder', 'ContinueInstall', 'CancelInstall']) need('SteamClient.Installs.' + f);
need('SteamClient.InstallFolder.GetInstallFolders'); need('appStore.GetAppOverviewByAppID'); need('SteamClient.Apps.LoadEula'); need('SteamClient.Apps.MarkEulaAccepted');
"#,
        include_str!("js_overview.inc"),
        include_str!("js_install_info.inc"),
        r#"
const a = appStore.GetAppOverviewByAppID(ARG.appid);
if (!a) return { owned: false };
if (here(a)) return { owned: true, installed: true };
const folders = await wait(SteamClient.InstallFolder.GetInstallFolders(), 'GetInstallFolders');
const wanted = (ARG.folder === null) ? (folders.find((f) => f.bIsDefaultFolder) || folders[0] || {}).nFolderIndex : ARG.folder;
if (!folders.some((f) => f.nFolderIndex === wanted)) return { owned: true, installed: false, folder_exists: false };
// LoadEula refuses with result 42 ("No eula for app") when there is none.
const licences = async () => { try { const l = await wait(SteamClient.Apps.LoadEula(ARG.appid), 'LoadEula');
  return Array.isArray(l) ? l.map((e) => ({ id: String(e.id), version: Number(e.version || 0), url: String(e.url || '') })) : []; } catch (e) { if (e && e.code) throw e; return []; } };
// The title Steam's own Install dialog would have, in the client's language, for the
// case that the dialog shows after all (quiet: false). "Install" in English.
let dialog_title = 'Install';
try { const t = LocalizationManager.LocalizeString('#GameAction_Install'); if (typeof t === 'string' && t) dialog_title = t; } catch (e) {}
const base = { owned: true, installed: false, folder_exists: true, name: a.display_name, dialog_title };

let store = null;
try {
  let req = null; window.webpackChunksteamui.push([[Symbol('ugos')], {}, (r) => { req = r; }]);
  for (const id of Object.keys(req.m)) {
    if (!String(req.m[id]).includes('m_unAppIDExpectedInstall=')) continue;
    // Already loaded (the store exists from start-up), so asking for it runs nothing.
    const exports = req(id);
    for (const k of Object.keys(exports)) { const v = exports[k];
      if (v && typeof v === 'object' && 'm_unAppIDExpectedInstall' in v && typeof v.BShowDiskSettingsForInstall === 'function' && typeof v.StartRequestedInstall === 'function') store = v; }
  }
} catch (e) { store = null; }
const quiet = !!store;
const taken_over = ['BShowDeckCompatForInstall', 'BShowDiskSettingsForInstall', 'StartRequestedInstall'];
if (store) {
  store.BShowDeckCompatForInstall = () => false;
  store.BShowDiskSettingsForInstall = () => false;
  store.StartRequestedInstall = () => {};
  store.m_unAppIDExpectedInstall = ARG.appid;
}
try {
  SteamClient.Installs.OpenInstallWizard([ARG.appid], '0');
  let i = await info();
  for (let n = 0; n < 60 && !(i.apps.includes(ARG.appid) && i.state === 7); n++) { await sleep(250); i = await info(); }
  if (!i.apps.includes(ARG.appid) || i.state !== 7) { SteamClient.Installs.CancelInstall(); await sleep(400); return { ...base, loaded: false, quiet, info: i }; }
  await SteamClient.Installs.SetInstallFolder(wanted);
  await sleep(400);
  i = await info();
  if (i.needed > i.free) { SteamClient.Installs.CancelInstall(); await sleep(400); return { ...base, loaded: true, quiet, stopped: 'no-space', info: i }; }
  const wanted_licences = await licences();
  if (wanted_licences.length && !ARG.licences_accepted) { SteamClient.Installs.CancelInstall(); await sleep(400); return { ...base, loaded: true, quiet, stopped: 'licence', licences: wanted_licences, info: i }; }
  for (const l of wanted_licences) await SteamClient.Apps.MarkEulaAccepted(ARG.appid, l.id, l.version);
  await SteamClient.Installs.ContinueInstall();
  const seen = [];
  for (let n = 0; n < 80; n++) {
    await sleep(250); i = await info();
    if (seen[seen.length - 1] !== i.state) seen.push(i.state);
    // 14 complete, 15 failed, 16 cancelled; 0 with no apps: the manager is done and empty again.
    if (i.state >= 14 || (i.state === 0 && i.apps.length === 0)) break;
    // 4 product key, 6 password, 8 licence text, 11 change disc, 13 sign-up: a person is needed.
    if ([4, 6, 8, 11, 13].includes(i.state) && n > 3) break;
  }
  if ([4, 6, 8, 11, 13].includes(i.state)) {
    const still = i.state === 8 ? await licences() : [];
    SteamClient.Installs.CancelInstall(); await sleep(400);
    return { ...base, loaded: true, quiet, stopped: i.state === 8 ? 'licence' : 'attention', licences: still, states: seen, info: i };
  }
  return { ...base, loaded: true, quiet, started: true, states: seen, info: i };
} finally {
  if (store) { for (const k of taken_over) delete store[k]; store.m_unAppIDExpectedInstall = 0; }
}
"#
    );
    Script::new("install", Page::Shared, 60, BODY, serde_json::json!({ "appid": appid, "folder": folder, "licences_accepted": licences_accepted }))
}

/// Removes an installed app without Steam's confirmation window: the arguments are the
/// app ids, the client id ("0" is this machine) and "already confirmed".
pub fn uninstall(appid: u32) -> Script {
    Script::new(
        "uninstall",
        Page::Shared,
        60,
        concat!(
            r#"
need('SteamClient.Installs.OpenUninstallWizard'); need('appStore.GetAppOverviewByAppID');
"#,
            include_str!("js_overview.inc"),
            r#"
const a = appStore.GetAppOverviewByAppID(ARG.appid);
if (!a) return { owned: false };
if (!here(a)) return { owned: true, installed: false };
SteamClient.Installs.OpenUninstallWizard([ARG.appid], '0', true);
let gone = false;
for (let n = 0; n < 200 && !gone; n++) { await sleep(250); const now = appStore.GetAppOverviewByAppID(ARG.appid); gone = !now || !here(now); }
return { owned: true, installed: true, removed: gone, name: a.display_name };
"#
        ),
        serde_json::json!({ "appid": appid }),
    )
}

/// The download queue. Both registrations call back at once with the current state.
pub fn downloads() -> Script {
    Script::new(
        "downloads",
        Page::Shared,
        15,
        r#"
need('SteamClient.Downloads.RegisterForDownloadOverview'); need('SteamClient.Downloads.RegisterForDownloadItems');
const once = (register, what) => wait(new Promise((yes) => { let h; h = register((...a) => { try { h && h.unregister(); } catch (e) {} yes(a); }); }), what);
const [o] = await once((f) => SteamClient.Downloads.RegisterForDownloadOverview(f), 'RegisterForDownloadOverview');
const [, lists] = await once((f) => SteamClient.Downloads.RegisterForDownloadItems(f), 'RegisterForDownloadItems');
const local = (Array.isArray(lists) ? lists : []).find((l) => String(l.remote_client_id) === '0') || { item_data: [] };
const name = (id) => { try { return appStore.GetAppOverviewByAppID(id).display_name; } catch (e) { return ''; } };
const sum = (item, key) => (item.update_type_info || []).reduce((n, t) => n + (t.progress || []).reduce((m, p) => m + Number(p[key] || 0), 0), 0);
return {
  state: String(o.update_state || 'None'), paused: !!o.paused, appid: Number(o.update_appid || 0),
  bytes_per_second: Math.round(Number(o.update_network_bytes_per_second || 0)), percent: Number(o.overall_percent_complete || 0),
  seconds_left: Math.round(Number(o.overall_estimated_time_remaining_sec ?? -1)), installing: !!o.update_is_install,
  items: (local.item_data || []).map((x) => ({ appid: Number(x.appid), name: String(name(x.appid) || ''), active: !!x.active, paused: !!x.paused, completed: !!x.completed,
    queue_index: Number(x.queue_index ?? -1), scheduled_for: Number(x.deferred_time || 0), bytes_done: sum(x, 'bytes_in_progress'), bytes_total: sum(x, 'bytes_total'),
    error: x.update_error || '' })) };
"#,
        Value::Null,
    )
}

/// Pauses or resumes all downloads, like the button on Steam's downloads page.
pub fn enable_downloads(on: bool) -> Script {
    Script::new(
        "enable_downloads",
        Page::Shared,
        10,
        r#"
need('SteamClient.Downloads.EnableAllDownloads');
SteamClient.Downloads.EnableAllDownloads(ARG.on);
await sleep(500);
return true;
"#,
        serde_json::json!({ "on": on }),
    )
}

// `js_actions.inc`: keeps Steam's own launch events for the commands to read.

/// Starts an app installed on this machine the way Steam's Play button does: game id,
/// no extra launch options, launch option -1 (Steam's choice), launch source 100.
///
/// Before pressing Play it starts listening to Steam's game-action events (see
/// `js_actions.inc`) and answers with the number of the last event so far, so the
/// caller can tell this launch's events from older ones.
pub fn launch(appid: u32) -> Script {
    Script::new(
        "launch",
        Page::Shared,
        15,
        concat!(
            r#"
need('SteamClient.Apps.RunGame'); need('appStore.GetAppOverviewByAppID');
"#,
            include_str!("js_overview.inc"),
            include_str!("js_actions.inc"),
            r#"
const a = appStore.GetAppOverviewByAppID(ARG.appid);
if (!a) return { owned: false };
// Installed on another computer only: Play would stream it from there. Not what was asked.
if (!here(a)) return { owned: true, installed: false };
const log = listen();
const since = log.seq;
SteamClient.Apps.RunGame(String(a.GetGameID ? a.GetGameID() : ARG.appid), '', -1, 100);
return { owned: true, installed: true, name: a.display_name, since, listening: log.listening };
"#
        ),
        serde_json::json!({ "appid": appid }),
    )
}

/// Where a launch stands, from Steam's own signals: the game-action events since
/// `since`, the game actions Steam lists as active now, and whether the app is among
/// the running ones. Deciding what they mean is done in Rust (`launch::Tracker`).
pub fn launch_state(appid: u32, since: u64) -> Script {
    Script::new(
        "launch_state",
        Page::Shared,
        10,
        concat!(
            include_str!("js_actions.inc"),
            r#"
const log = listen();
const mine = String(ARG.appid);
let running = false; try { running = SteamUIStore.RunningApps.some((x) => x.appid === ARG.appid); } catch (e) {}
const now = await current(ARG.appid);
return { listening: log.listening, last: log.seq, running, active: await active(), progress: await progress(now.id),
         events: log.events.filter((e) => e.n > ARG.since && (e.app === null || e.app === mine)) };
"#
        ),
        serde_json::json!({ "appid": appid, "since": since }),
    )
}

/// Skips shader processing the way the Skip button in Steam's launch window does.
///
/// Steam announces shader processing as a request to the player, and a request is
/// answered with `ContinueGameAction(action id, answer)`; Steam's own code answers a
/// licence request with the request's name. For shaders the answer is "SkipShaders".
/// That word is from memory of the client's interface, not from anything recorded:
/// to be confirmed on a device. Nothing is sent unless the launch is at that step.
pub fn launch_skip(appid: u32) -> Script {
    Script::new(
        "launch_skip",
        Page::Shared,
        10,
        concat!(
            include_str!("js_actions.inc"),
            r#"
need('SteamClient.Apps.ContinueGameAction');
const now = await current(ARG.appid);
if (now.id === null || now.task !== ARG.task) return { skipped: false, task: now.task };
SteamClient.Apps.ContinueGameAction(now.id, ARG.answer);
return { skipped: true, task: now.task, action: now.id };
"#
        ),
        serde_json::json!({ "appid": appid, "task": "ProcessingShaderCache", "answer": "SkipShaders" }),
    )
}

/// What Steam is busy starting right now, for `running` and `status`.
pub fn activity() -> Script {
    Script::new(
        "activity",
        Page::Shared,
        10,
        concat!(
            include_str!("js_actions.inc"),
            r#"
const name = (id) => { try { return appStore.GetAppOverviewByAppID(Number(id)).display_name; } catch (e) { return ''; } };
const list = await active();
return (list || []).filter((x) => x.app !== null).map((x) => ({ appid: Number(x.app), name: String(name(x.app) || ''), action: x.action, task: x.task }));
"#
        ),
        Value::Null,
    )
}

/// Calls a launch off: cancels the game action when its number is known, and ends the
/// app's process if it has one.
pub fn cancel_launch(appid: u32, action: Option<i64>) -> Script {
    Script::new(
        "cancel_launch",
        Page::Shared,
        10,
        r#"
if (ARG.action !== null) { try { need('SteamClient.Apps.CancelGameAction'); SteamClient.Apps.CancelGameAction(ARG.action); } catch (e) { if (e && e.code) throw e; } }
let was_running = false;
try { const a = SteamUIStore.RunningApps.find((x) => x.appid === ARG.appid);
  if (a) { was_running = true; SteamClient.Apps.TerminateApp(String(a.GetGameID ? a.GetGameID() : ARG.appid), false); } } catch (e) {}
return { was_running };
"#,
        serde_json::json!({ "appid": appid, "action": action }),
    )
}

pub fn running() -> Script {
    Script::new(
        "running",
        Page::Shared,
        10,
        r#"
need('SteamUIStore.RunningApps');
return SteamUIStore.RunningApps.map((a) => ({ appid: a.appid, name: a.display_name }));
"#,
        Value::Null,
    )
}

/// Ends a running app like Steam's Stop button (second argument: do not force).
/// For a launch that is still being prepared, see `cancel_launch`.
pub fn stop_app(appid: u32) -> Script {
    Script::new(
        "stop_app",
        Page::Shared,
        10,
        r#"
need('SteamClient.Apps.TerminateApp'); need('SteamUIStore.RunningApps');
const a = SteamUIStore.RunningApps.find((x) => x.appid === ARG.appid);
if (!a) return { running: false };
SteamClient.Apps.TerminateApp(String(a.GetGameID ? a.GetGameID() : ARG.appid), false);
return { running: true, name: a.display_name };
"#,
        serde_json::json!({ "appid": appid }),
    )
}

/// One of the Steam client's yes/no settings: its name in the client's settings object,
/// and its field number in the settings message (both from the client's own script).
pub struct BoolSetting {
    pub name: &'static str,
    pub field: u32,
    read: &'static str,
    write: &'static str,
}

/// "Enable the Steam Overlay while in-game".
pub const OVERLAY: BoolSetting = BoolSetting { name: "enable_overlay", field: 4004, read: "overlay_read", write: "overlay_send" };
/// "Disable all toasts": Steam's small pop-up windows (download finished, friend
/// online, achievement). Under a kiosk compositor each of them is a window on top of
/// everything. Steam still shows the few it marks critical.
///
/// Unlike the overlay switch, which Steam keeps per computer (localconfig.vdf), this
/// one is kept in the account's synced settings (sharedconfig.vdf, DisableAllToasts):
/// changing it on one computer changes it on every computer of the account at their
/// next sync, and a value sent before the synced settings have arrived after sign-in
/// can be overwritten by them.
pub const NO_TOASTS: BoolSetting = BoolSetting { name: "disable_all_toasts", field: 6000, read: "toasts_read", write: "toasts_send" };

/// A setting's value, and whether the client has it at all yet. The settings arrive in
/// pieces after start-up: before anyone is signed in the settings object holds about a
/// third of its keys and neither of the two settings used here is among them; they come
/// with the account's settings during sign-in. There is no "loaded" flag in the store,
/// so "the key is there and is a yes or no" is the signal.
pub fn setting_read(setting: &BoolSetting) -> Script {
    Script::new(
        setting.read,
        Page::Shared,
        10,
        r#"
const all = need('settingsStore.m_ClientSettings');
const v = all[ARG.name];
return { loaded: typeof v === 'boolean', value: typeof v === 'boolean' ? v : null, keys: Object.keys(all).length };
"#,
        serde_json::json!({ "name": setting.name }),
    )
}

/// The bytes of a settings message holding one boolean field: the field's tag (number
/// times 8, as a varint) and then 0 or 1.
fn bool_field(field: u32, value: bool) -> Vec<u8> {
    let mut bytes = Vec::new();
    let mut tag = (field as u64) << 3;
    while tag >= 0x80 {
        bytes.push((tag & 0x7f) as u8 | 0x80);
        tag >>= 7;
    }
    bytes.push(tag as u8);
    bytes.push(value as u8);
    bytes
}

/// Changes a setting the way Steam's settings pages do: `SteamClient.Settings.SetSetting`
/// takes a serialised settings message holding just the changed field. It only sends;
/// whether the value took, and stays, is read back by the caller.
pub fn setting_send(setting: &BoolSetting, value: bool) -> Script {
    Script::new(
        setting.write,
        Page::Shared,
        10,
        r#"
need('SteamClient.Settings.SetSetting');
await SteamClient.Settings.SetSetting(ARG.message);
return true;
"#,
        serde_json::json!({ "message": crate::ws::base64(&bool_field(setting.field, value)), "name": setting.name, "value": value }),
    )
}

/// The client's own version, for `ugos-steam version`.
pub fn client_version() -> Script {
    Script::new(
        "client_version",
        Page::Shared,
        10,
        r#"
need('SteamClient.System.GetSystemInfo');
const i = await wait(SteamClient.System.GetSystemInfo(), 'GetSystemInfo');
return { version: i.nSteamVersion || 0, built: i.sSteamBuildDate || '', interface: i.sSteamAPI || '' };
"#,
        Value::Null,
    )
}

/// The helpers the two friends scripts share: `at(o, path)` follows a dotted path,
/// `first(o, key)` the first of `F[key]`'s paths that has a value, and `who(p)` the
/// object a person's fields are on (its persona when it has one).
macro_rules! friends_helpers {
    () => {
        r#"
const F = ARG.fields;
const at = (o, path) => { for (const p of path.split('.')) { if (o === undefined || o === null) return undefined; try { o = o[p]; } catch (e) { return undefined; } } return o; };
const found = (o, key) => { for (const path of F[key]) { const v = at(o, path); if (v !== undefined && v !== null) return { path, v }; } return null; };
const first = (o, key) => { const f = found(o, key); return f ? f.v : null; };
const who = (p) => first(p, 'persona') || p;
const list = (store) => { const l = first(store, 'list'); return Array.isArray(l) ? l : (l && typeof l.values === 'function') ? [...l.values()] : null; };
"#
    };
}

/// The signed-in player and their friends: name, picture id, persona state, the game's
/// app id and name. Where each is read from is `friends::fields()`.
pub fn friends(fields: Value) -> Script {
    Script::new(
        "friends",
        Page::Shared,
        10,
        concat!(friends_helpers!(), r#"
const store = first(globalThis, 'store');
if (!store) throw { code: 'call-missing', what: 'the friends list' };
const all = list(store);
if (!all) throw { code: 'unexpected-shape', what: 'the friends list' };
const one = (p) => { const o = who(p); const n = (k) => { const v = first(o, k); return typeof v === 'number' ? v : (typeof v === 'string' && /^\d+$/.test(v)) ? Number(v) : null; };
  const s = (k) => { const v = first(o, k); return typeof v === 'string' ? v : null; };
  return { name: s('name'), avatar: s('avatar'), state: n('state'), appid: n('appid'), game: s('game') }; };
const me = first(store, 'me');
return { me: me ? one(me) : null, friends: all.map(one) };
"#),
        serde_json::json!({ "fields": fields }),
    )
}

/// What `friends` would find, with no person in it: which of the names in
/// `friends::fields()` were there, the names Steam's person objects have, and counts.
pub fn friends_check(fields: Value) -> Script {
    Script::new(
        "friends_check",
        Page::Shared,
        10,
        concat!(friends_helpers!(), r#"
const names = (o) => { if (!o || typeof o !== 'object') return []; const out = new Set(Object.keys(o));
  let p = Object.getPrototypeOf(o); while (p && p !== Object.prototype) { for (const [k, d] of Object.entries(Object.getOwnPropertyDescriptors(p))) if (d.get) out.add(k); p = Object.getPrototypeOf(p); }
  return [...out].filter((k) => /^[A-Za-z_$][\w$]*$/.test(k)).sort().slice(0, 120); };
const globals = Object.keys(globalThis).filter((k) => /friend/i.test(k)).sort();
const s = found(globalThis, 'store');
const R = { globals, store: s ? s.path : null };
if (!s) return R;
const store = s.v;
R.store_names = names(store);
const lf = found(store, 'list');
R.list = lf ? lf.path : null;
const all = list(store);
R.friends = all ? all.length : null;
const mf = found(store, 'me');
R.me = mf ? mf.path : null;
if (all && all.length) { R.person_names = names(all[0]); const pf = found(all[0], 'persona'); R.persona = pf ? pf.path : null; if (pf) R.persona_names = names(pf.v); }
const people = (all || []).map(who);
R.fields = {};
for (const k of ['name', 'avatar', 'state', 'appid', 'game']) {
  const paths = {}; let filled = 0;
  for (const o of people) { const f = found(o, k); if (f) { paths[f.path] = (paths[f.path] || 0) + 1; if (f.v !== '' && f.v !== 0 && f.v !== '0') filled++; } }
  R.fields[k] = { found_as: paths, filled, type: (() => { for (const o of people) { const v = first(o, k); if (v !== null) return typeof v; } return null; })() };
}
R.avatar_hex40 = people.filter((o) => { const v = first(o, 'avatar'); return typeof v === 'string' && /^[0-9a-f]{40}$/i.test(v); }).length;
const states = {}; for (const o of people) { const v = first(o, 'state'); states[String(v)] = (states[String(v)] || 0) + 1; }
R.states = states;
if (mf) { const m = who(mf.v); R.me_fields = Object.fromEntries(['name', 'avatar', 'state', 'appid', 'game'].map((k) => [k, first(m, k) !== null])); }
// Chat, for finding out whether text messages could go through here: the names of the
// friends app's parts and of its chat store's fields and functions. Nothing is called.
const fns = (o) => { const out = new Set(); let p = o && Object.getPrototypeOf(o); while (p && p !== Object.prototype) { for (const [k, d] of Object.entries(Object.getOwnPropertyDescriptors(p))) if (typeof d.value === 'function' && k !== 'constructor') out.add(k); p = Object.getPrototypeOf(p); } return [...out].sort().slice(0, 200); };
const app = globalThis.g_FriendsUIApp;
if (app) {
  const cs = app.ChatStore || app.m_ChatStore || null;
  R.chat = { app_names: names(app), store: cs ? (app.ChatStore ? 'ChatStore' : 'm_ChatStore') : null,
             store_names: cs ? names(cs) : [], store_functions: cs ? fns(cs).filter((k) => /chat|message|msg|send|friend/i.test(k)) : [] };
  // The friend chats' store, and one chat with a friend that Steam already has loaded
  // (the first of one of its lists or Map fields; a Map's keys are not looked at).
  const fcs = cs && (cs.FriendChatStore || cs.m_FriendChatStore);
  if (fcs) {
    R.chat.friend_chat_store_names = names(fcs);
    R.chat.friend_chat_store_functions = fns(fcs);
    for (const k of Object.keys(fcs)) {
      const v = fcs[k];
      if ((v instanceof Map && v.size) || (Array.isArray(v) && v.length)) {
        const one = Array.isArray(v) ? v[0] : v.values().next().value;
        if (one && typeof one === 'object') { R.chat.friend_chat_from = k; R.chat.friend_chat_names = names(one); R.chat.friend_chat_functions = fns(one); break; }
      }
    }
    if (!R.chat.friend_chat_from) R.chat.friend_chat_from = null;
  }
}
return R;
"#),
        serde_json::json!({ "fields": fields }),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn arguments_are_passed_as_data_never_as_code() {
        let script = choose_account("x'); alert(1); ('");
        let source = script.source();
        assert!(source.contains(r#"const ARG = {"account":"x'); alert(1); ('"};"#));
        assert!(!script.body.contains("alert"));
    }

    #[test]
    fn a_setting_message_holds_the_field_tag_and_the_value() {
        assert_eq!(bool_field(4004, false), [0xA0, 0xFA, 0x01, 0x00]);
        assert_eq!(setting_send(&OVERLAY, false).arg()["message"], "oPoBAA==");
        assert_eq!(setting_send(&OVERLAY, true).arg()["message"], "oPoBAQ==");
        // Field 6000: tag 48000 = 0x80 0xF7 0x02 as a varint. A small field fits one byte.
        assert_eq!(bool_field(6000, true), [0x80, 0xF7, 0x02, 0x01]);
        assert_eq!(bool_field(1, true), [0x08, 0x01]);
    }

    #[test]
    fn every_script_is_wrapped_so_it_cannot_throw() {
        for s in [state(), sign_in_page(), accounts(), library(), game(1), folders(), install_size(1, None), install(1, None, false), uninstall(1), downloads(), enable_downloads(true), launch(1), running(), stop_app(1), setting_read(&OVERLAY), setting_send(&NO_TOASTS, true), launch_state(1, 0), launch_skip(1), activity(), cancel_launch(1, Some(2)), client_version(), friends(crate::friends::fields()), friends_check(crate::friends::fields())]
        {
            let source = s.source();
            assert!(source.starts_with("(async () => {"), "{}", s.name);
            assert!(source.contains("catch (e) { return { err:"), "{}", s.name);
            assert!(s.seconds >= 10);
        }
    }
}

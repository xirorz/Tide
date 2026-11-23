// Steam announces each step of starting a game as a "game action" (the action is
// "LaunchApp"): it starts, moves from task to task (updating, first-time setup,
// creating the process, ...), may ask the player something, may report an error, and
// ends. These are the events Steam's own launch dialog is drawn from. A command lasts
// one script, so the events are kept in the page between commands, in one object on
// `window`, the last 300 of them. Nothing else of ours stays in Steam's memory.
//
// Argument order of the callbacks, as Steam's interface code uses them:
//   start    (action id, app id, action name, launch source)
//   task     (action id, app id, action name, task name, detail)
//   request  (action id, app id, action name, what is asked, detail)
//   error    (action id, app id, action name, error text such as "AppError_51", detail)
//   end      (action id)
//   lifetime ({ unAppID, nInstanceID, bRunning }): the game's process came or went
const listen = () => {
  if (window.__ugos_actions) return window.__ugos_actions;
  const log = { seq: 0, events: [], listening: [] };
  const text = (v) => (v === undefined || v === null) ? null : String(v);
  const add = (e) => { e.n = ++log.seq; log.events.push(e); if (log.events.length > 300) log.events.shift(); };
  const on = (kind, register) => { try { register((...a) => add({ kind, id: Number(a[0]), app: text(a[1]), action: text(a[2]), detail: text(a[3]), extra: text(a[4]) })); log.listening.push(kind); } catch (e) {} };
  on('start', (f) => SteamClient.Apps.RegisterForGameActionStart(f));
  on('task', (f) => SteamClient.Apps.RegisterForGameActionTaskChange(f));
  on('request', (f) => SteamClient.Apps.RegisterForGameActionUserRequest(f));
  on('error', (f) => SteamClient.Apps.RegisterForGameActionShowError(f));
  on('end', (f) => SteamClient.Apps.RegisterForGameActionEnd(f));
  try { SteamClient.GameSessions.RegisterForAppLifetimeNotifications((n) => add({ kind: 'lifetime', id: 0, app: text(n && n.unAppID), action: null, detail: (n && n.bRunning) ? 'running' : 'gone', extra: null })); log.listening.push('lifetime'); } catch (e) {}
  window.__ugos_actions = log;
  return log;
};
// The game actions Steam itself lists as active. null when the call is not there.
const active = async () => {
  try {
    const list = await wait(SteamClient.Apps.GetActiveGameActions(), 'GetActiveGameActions', 4000);
    if (!Array.isArray(list)) return null;
    const app = (x) => { for (const k of ['unAppID', 'nAppID', 'appid', 'strGameID', 'gameid', 'strAppID']) if (x[k] !== undefined && x[k] !== null) return String(x[k]); return null; };
    return list.map((x) => ({ id: Number(x.nGameActionID), app: app(x), action: x.strActionName === undefined ? null : String(x.strActionName), task: x.strTaskName === undefined ? null : String(x.strTaskName) }));
  } catch (e) { return null; }
};
// The game action of a launch of this app that is still going: from the events (a start
// with no end after it), else from Steam's list. With the step it is on, when known.
const current = async (appid) => {
  const mine = String(appid);
  const log = listen();
  let id = null, task = null;
  for (const e of log.events) {
    if (e.kind === 'start' && e.app === mine) { id = e.id; task = null; }
    else if (id !== null && e.id === id && (e.kind === 'task' || e.kind === 'request')) task = e.detail;
    else if (id !== null && e.id === id && e.kind === 'end') { id = null; task = null; }
  }
  const list = await active();
  const listed = (list || []).find((x) => x.app === mine || (id !== null && x.id === id));
  if (id === null && listed) id = listed.id;
  if (!task && listed && listed.task) task = listed.task;
  if (id !== null && list !== null && !listed && !log.listening.includes('end')) id = null;
  return { id, task };
};
// Steam's count for the step an action is on. Its own launch window asks the same call
// about once a second and draws its bar from "done" of "total".
const progress = async (id) => {
  if (id === null) return null;
  try {
    const d = await wait(new Promise((yes) => SteamClient.Apps.GetGameActionDetails(id, yes)), 'GetGameActionDetails', 2000);
    const n = (v) => { const x = parseInt(v); return Number.isFinite(x) ? x : null; };
    return d ? { done: n(d.strNumDone), total: n(d.strNumTotal) } : null;
  } catch (e) { return null; }
};

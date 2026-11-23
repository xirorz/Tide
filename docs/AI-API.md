# Tide AI API — version 1 (draft)

Tide's AI panel, island and launcher can talk to any assistant. A backend connects in
one of two ways:

| Way | What you build | What Tide shows |
| --- | --- | --- |
| **OpenAI-compatible** | Nothing. LM Studio, Ollama, llama.cpp server, vLLM and Jan already serve `/v1/chat/completions`. | Chat only. Tide keeps the chat list itself. |
| **Tide AI API** (this document) | A small HTTP API at one base URL. | Whatever your manifest says you support: chat history, approvals, live activity, voice, apps. |

Tide never needs to know anything else about your system. Everything comes from one
base URL, such as `http://127.0.0.1:3000/ai/v1`.

Status: draft. Sections marked *(draft)* will be settled while Eve's implementation is built.

---

## Giving this to your coding agent

Copy this whole file to your coding agent with a message like:

> Add a Tide AI API (version 1) to my assistant, following this spec. Serve it under
> `/ai/v1` on my existing server, bound to 127.0.0.1. Start with the required parts
> (manifest and reply), then add each optional capability my assistant already has.
> List in the manifest only what you actually implemented.

What the agent must do:

1. Serve `GET {base}` (the manifest) and `POST {base}/chats/{id}/reply` (a streamed reply). That is enough for Tide to chat.
2. For each capability your assistant has, add its routes and list it in `capabilities`.
3. Map your own data to the shapes below. Do not invent features: an empty list is fine, a made-up one is not.
4. Check it: `python3 ~/.config/Tide/modes/dev/shell/scripts/ai-api-check.py {base}` *(coming with the first build step)* calls every route the manifest claims and reports what does not match.

Then in Tide: **Settings → AI → Add backend**, type "Tide AI API", paste the base URL.

---

## Conventions

- JSON in and out, UTF-8. Times are milliseconds since the epoch (`createdAt`).
- Errors: an HTTP status of 400 or more and `{"ok": false, "error": "what went wrong, in plain words"}`.
- Auth: none on 127.0.0.1. If the API is reachable from other machines, require
  `Authorization: Bearer <token>`; Tide reads the token from a file the user picks.
  Tide sends no `Origin` header.
- Streams are server-sent events: each event is one line `data: {json}` followed by a blank
  line; the stream ends with `data: [DONE]`. Lines starting with `:` are keep-alives.
- Ids are strings you choose (letters, digits, `_`, `-`, `.`; up to 96 characters).

---

## Manifest — required

`GET {base}`

```json
{
  "api": "tide-ai",
  "version": 1,
  "name": "Eve",
  "capabilities": ["chat", "history", "cancel", "thinking", "attachments", "approvals",
                   "mode", "power", "live", "voice.dictation", "voice.speech", "voice.call", "apps"],
  "apps": [
    { "id": "briefing", "name": "Daily briefing", "icon": "clock" },
    { "id": "finance",  "name": "Finance",        "icon": "chart" }
  ]
}
```

- `name` is what Tide calls the assistant everywhere ("Message Eve", "Eve is on").
- Tide hides every control whose capability is missing. `chat` is the only required one.
- `icon` is one of Tide's icon names: `clock`, `mic`, `book`, `download`, `chart`,
  `calendar`, `server`, `mail`, `grid`, `folder`, `heart`, `star` *(draft list)*.

## Health — optional, recommended

`GET {base}/health` → `{"ok": true, "ready": true, "detail": "Model loaded"}`

`ready: false` with a `detail` shows as a grey status dot and that text. Tide checks it
every 30 seconds while the panel is open.

---

## Chat — `chat` (required)

`POST {base}/chats/{chatId}/reply`

```json
{
  "text": "Is the barbershop site up?",
  "think": false,
  "attachments": [ { "name": "error.png", "path": "/home/me/error.png", "mime": "image/png" } ],
  "history": [ { "role": "user", "text": "…" }, { "role": "assistant", "text": "…" } ]
}
```

- `chatId` is new or existing. If you support `history`, create the chat when the id is
  new, save the user's message and your reply, and ignore the `history` field.
  Without `history`, Tide sends the earlier messages in `history`.
- `think` only when you list `thinking`; `attachments` only when you list `attachments`
  (paths are on this computer).
- If the assistant is busy with another reply, answer `409` with an error.
- Send `GET {base}/chats` ids back unchanged; Tide makes new ids as `tide-` plus a random hex string.

The response is a stream of these events:

| Event | Meaning |
| --- | --- |
| `{"type":"delta","text":"The site "}` | More answer text. |
| `{"type":"step","op":"add","step":{"id":"s1","text":"Checking containers","icon":"containers","status":"running"}}` | A working step began. `icon`: `terminal`, `browser`, `containers`, `log`, `thought`, `tool`. |
| `{"type":"step","op":"update","id":"s1","delta":"…"}` | More text for a step (for example its reasoning). Instead of `delta` it may carry `text` (replaces the step's text) and `icon`. |
| `{"type":"step","op":"done","id":"s1","status":"ok"}` | A step finished: `ok` or `error`. |
| `{"type":"activity","text":"Reading the logs"}` | A one-line status. |
| `{"type":"terminal","line":"$ docker ps","kind":"cmd"}` | A terminal line for the island. `kind`: `cmd`, `out`, `ok`. |
| `{"type":"approval","approval":{…}}` | A decision is needed before going on (see Approvals). |
| `{"type":"image","url":"…"}` | A picture to show in the reply (an http URL or a local path). |
| `{"type":"done","text":"The site is up.","telemetry":{"ttftMs":420,"tokensPerSecond":41,"totalMs":8400}}` | The reply finished. `text` is the whole answer. `telemetry` and `images` (paths or URLs) are optional. |
| `{"type":"error","error":"…"}` | The reply failed. |
| `{"type":"cancelled"}` | The reply was stopped. |

Only `delta` and `done` are required. Unknown event types are ignored, so you can add your own.

## Cancel — `cancel`

`POST {base}/chats/{chatId}/cancel` → `{"ok": true, "cancelled": true}`. The open stream
then ends with `cancelled`.

## Chat history — `history`

| Route | Body / answer |
| --- | --- |
| `GET {base}/chats` | `{"chats":[{"id","title","pinned","updatedAt","project"?}]}`, newest first |
| `PATCH {base}/chats/{id}` | `{"title"?, "pinned"?}` |
| `DELETE {base}/chats/{id}` | — |
| `GET {base}/chats/{id}/messages` | `{"messages":[{"id","role":"user"\|"assistant","text","createdAt","files"?,"images"?,"steps"?,"telemetry"?}]}`, oldest first |

`project` *(optional)* is `{"id","name"}`; Tide groups such chats under Projects.

`title` is `""` while a chat has no name yet. If your assistant names chats itself, it may do so a few seconds after the first reply; Tide re-reads the list for a little while after each reply, so the name appears on its own.

## Approvals — `approvals`

`GET {base}/approvals?chat={chatId}` (without `chat`: all waiting) →

```json
{ "approvals": [ {
    "id": "a1", "chatId": "c1", "title": "Run a command on the host",
    "command": "docker restart barbershop-web", "reason": "Why it needs your OK",
    "risk": "high", "scopes": ["once", "task", "all"], "createdAt": 1795372888426 } ] }
```

`POST {base}/approvals/{id}` with `{"decision":"approve"|"deny","scope":"once"|"task"|"all","reason"?}`.
`scopes` lists only the scopes you support; `once` is always allowed.

## Access mode — `mode`

`GET {base}/mode` → `{"mode":"ask"}`; `PUT {base}/mode` with `{"mode":"ask"|"full"}`.
`ask`: the assistant asks before acting. `full`: it acts without asking.

## Power — `power`

`GET {base}/power` → `{"on":true,"state":"ready"}`; `PUT {base}/power` with `{"on":false}`.
For backends that can load and unload their model. `state`: `ready`, `starting`, `stopping`, `off`.

## Live activity — `live`

`GET {base}/live` — a stream of `{"type":"live","busy":true,"request","chatId","activity","steps":[{"id","title","detail","kind","status"}],"terminal":[lines]}`,
sent whenever something changes. `title` says the step in words ("Searching the web", "Reading a page", "Running a
command", "Using her browser"), `detail` is what it was given (the search, the page, the command), `kind` is `web`,
`browser`, `terminal`, `containers` or `tool`, `status` is `running`, `done` or `error`. Tide shows it in the island
while a call is working: the titles under "Working", the details as lines in the island's terminal.

## Appearance — `appearance`

`PUT {base}/appearance` with `{"accent","accent2","background","surface","text","muted"}` (`#rrggbb`) and `"font"`,
`"mono"` (font names). Tide sends its current look (accent from the wallpaper) when it connects and when the wallpaper
changes, so the assistant's own windows (Eve's browser) match the desktop. `GET {base}/appearance` returns it.

## Voice *(draft)*

- `voice.dictation`: live dictation. `POST {base}/voice/dictation` → `{"id"}`. Then `POST …/{id}/audio` with raw
  16 kHz mono 16-bit PCM (about a quarter second per request) → `{"text","settled","tentative"}`: `text` is everything
  so far, `settled` won't change much any more, `tentative` is the words since the last pause. `POST …/{id}/finish`
  (optionally with the last audio) → `{"text"}`, the final text; `POST …/{id}/cancel` drops it.
  Tide shows `text` in the message box as the person speaks, so return clean text: no "..." for pauses, and
  sentences punctuated as a whole (re-recognize the paragraph, not each piece between pauses).
- `voice.speech`: `POST {base}/voice/speech` with `{"text"}` answers with the voice itself: raw 16-bit PCM, with
  `X-Audio-Sample-Rate` and `X-Audio-Channels` headers, streamed as it is made; Tide plays it as it arrives.
  Closing the stream or `POST {base}/voice/speech/stop` stops it. Tide's Listen button (on a `hero` block's `speak`)
  uses it.
- `voice.call`: a hands-free conversation in which the assistant listens while it talks (you can talk over it).
  `POST {base}/voice/call` → `{"id","rate","speechRate"}`. Stream the microphone as 16 kHz mono 16-bit PCM every
  ~100 ms to `POST …/{id}/audio` (an optional `X-Voice-Activity: 0-1` header is your VAD's speech chance), play
  `GET …/{id}/speech` (raw PCM at `speechRate`) as it arrives, read `GET …/{id}/events`, and `POST …/{id}/close` to
  hang up. Events: `{"type":"stage","stage":"listening"|"working"|"speaking"}`,
  `{"type":"caption","who":"user","text","append":true}` (new words as they are heard),
  `{"type":"caption","who":"assistant","text","final"?,"progress"?}`, `{"type":"step","text"}`, `{"type":"talking"}`
  (speech heard, no words yet), `{"type":"approval"}`, `{"type":"hold","on"}` (it cut in: mute the mic until it has
  said it), `{"type":"stop"}` (it stopped: drop any of its voice still buffered), `{"type":"error","error"}`.
  Tide draws the call in the island.

## Apps — `apps`

Apps open inside Tide's AI panel: the panel's header shows the app's name, and the body shows its content. Apps
show information; there is no message box. Tide draws the content from blocks, so you write no UI code, and every
app looks like the rest of the panel.

List them in the manifest (`"apps": [{"id","name","icon"}]`) and serve each one:

`GET {base}/apps/{id}` →

```json
{
  "title": "Finance", "subtitle": "November", "updatedAt": 1795372888426,
  "blocks": [
    { "type": "stat", "label": "Spent in November", "value": "$1,240", "sub": "Income $2,577 · net $1,337" },
    { "type": "progress", "label": "By category", "icon": "chart",
      "items": [ { "label": "Groceries", "value": 410, "max": 380, "text": "$410", "tone": "critical" } ] },
    { "type": "list", "label": "Recurring", "icon": "clock",
      "items": [ { "title": "Rent", "sub": "3 months · steady", "trailing": "$1,449" } ] }
  ]
}
```

Every block is drawn as its own rounded card. Any block may carry `label` (a small grey title at the top of the
card) and `icon` (one of the icon names under Manifest).

| Block | Fields | Looks like |
| --- | --- | --- |
| `hero` | `eyebrow`, `title`, `text`, `footnote`, `speak` (text read aloud by Listen; needs `voice.speech`) | The large summary card at the top of a briefing |
| `cards` | `items`: `{icon, label, value?, unit?, title?, sub?, tone?}` | Small cards two across: a big `value` ("58°" with `unit` "Clear") or a bold `title` |
| `stat` | `value`, `sub?`, `bar?`: `{value, max}` | One big number, with an optional bar; past `max` the goal is marked and the extra shows in a second wallpaper color |
| `progress` | `items`: `{label, value, max, text?, sub?, tone?}` | Labelled bars |
| `rows` | `items`: `{when, text, chat?}` | Times in a mono column beside text |
| `list` | `lead?`, `items`: `{title, sub?, detail?, trailing?, badge?: {text, tone}, code?, live?, tone?, chat?}` | Rows with a right-hand value; `badge` is a small status pill, `detail` up to 3 lines under the row, `code` a mono line, `live` a pulsing dot |
| `checklist` | `items`: `{id, text, done}` | Tick boxes (ticking calls `POST {base}/apps/{id}/check` with `{"item","done"}`) |
| `table` | `columns` (strings), `rows` (arrays of strings) | A small table |
| `metrics` | `items`: `{label, value}` | A grid of figures |
| `tiles` | `items`: `{name, meta?, kind?, image?, url?}` | A grid of file cards; `image` is a preview URL. A picture opens full size (with Save to Downloads); another file opens `url` |
| `calendar` | `month` (`YYYY-MM`), `today`, `events`: `{date, time?, text}` | A month grid; picking a day lists its events |
| `tabs` | `tabs`: `{name, blocks}` | Tabs, each with its own blocks |
| `text` | `markdown` | A paragraph |

A block's `tone` of `warning` or `critical` tints its card. An app page may also carry `views` (`[{id, name}]`, oldest
first) and `view` (the one shown): Tide shows arrows to step through them and asks `GET {base}/apps/{id}?view=<id>`.
Finance uses this for months.

Chats that only exist to feed an app (a briefing, a mail log) should be left out of `GET {base}/chats`.

`chat` on an item opens that chat when clicked. `tone`: `normal`, `good`, `warning`, `critical`. Unknown block types
are skipped, so an older Tide still shows the rest. Tide reloads an open app every 30 seconds.

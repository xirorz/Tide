# Connecting an assistant to Tide

This file tells a coding agent how to connect **your** assistant to Tide, the desktop shell. Tide doesn't need to
know anything about how your assistant works inside: it only talks to it at one address.

There are two ways in:

| Way | What you build | What Tide does with it |
| --- | --- | --- |
| **OpenAI-compatible** | Nothing, if your app already serves `/v1/models` and `/v1/chat/completions` (LM Studio, Ollama, llama.cpp server, vLLM, Jan) | Chat in the AI panel. Tide keeps the chat list itself. |
| **Tide AI API** (the rest of this file) | A small HTTP API at one base URL, such as `http://127.0.0.1:8000/ai/v1` | Chat, plus whichever optional features you add below. Tide shows only the ones you list. |

To connect it: **Settings → AI → Add an assistant**, paste the address, press Connect. Tide works out which of the
two your assistant speaks.

## Instructions for the coding agent

1. Serve the **manifest** (`GET {base}`) and a **streamed reply** (`POST {base}/chats/{id}/reply`). That's enough for
   Tide to chat with the assistant.
2. Then add only the optional features the assistant can really do, and list each in the manifest's `capabilities`.
   Leave out anything it can't do: Tide hides what isn't listed.
3. Map the assistant's own data to the shapes below; don't invent data.
4. Bind to 127.0.0.1, or require a bearer token if the API is reachable from other machines.

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
  "name": "Nova",
  "capabilities": ["chat", "history", "cancel"],
  "apps": []
}
```

- `name` is what Tide calls the assistant everywhere ("Message Nova").
- `chat` is the only required capability. The optional ones are: `history`, `cancel`, `thinking`, `attachments`,
  `approvals`, `mode`, `power`, `live`, `voice.dictation`, `voice.speech`, `voice.call`, `apps`, `appearance`, each
  described below. Tide hides every control whose capability is missing.
- `icon` (for apps) is one of: `clock`, `mic`, `book`, `download`, `chart`, `calendar`, `server`, `mail`, `grid`,
  `folder`, `heart`, `star`.

## Health — optional, recommended

`GET {base}/health` → `{"ok": true, "ready": true, "detail": "Model loaded"}`

`ready: false` with a `detail` shows as a grey status dot and that text. Tide checks it
every 30 seconds while the panel is open.

---

## Chat — `chat` (required)

`POST {base}/chats/{chatId}/reply`

```json
{
  "text": "Is my website up?",
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
| `{"type":"step","op":"add","step":{"id":"s1","text":"Checking the server","icon":"terminal","status":"running"}}` | A working step began. `icon`: `terminal`, `browser`, `containers`, `log`, `thought`, `tool`. |
| `{"type":"step","op":"update","id":"s1","delta":"…"}` | More text for a step (for example its reasoning). Instead of `delta` it may carry `text` (replaces the step's text) and `icon`. |
| `{"type":"step","op":"done","id":"s1","status":"ok"}` | A step finished: `ok` or `error`. |
| `{"type":"activity","text":"Reading the logs"}` | A one-line status. |
| `{"type":"terminal","line":"$ uptime","kind":"cmd"}` | A terminal line. `kind`: `cmd`, `out`, `ok`. |
| `{"type":"approval","approval":{…}}` | A decision is needed before going on (see Approvals). |
| `{"type":"image","url":"…"}` | A picture to show in the reply (an http URL or a local path). |
| `{"type":"done","text":"It's up.","telemetry":{"ttftMs":420,"tokensPerSecond":41,"totalMs":8400}}` | The reply finished. `text` is the whole answer. `telemetry` and `images` (paths or URLs) are optional. |
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
    "command": "systemctl restart my-app", "reason": "Why it needs your OK",
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
sent whenever something changes. `title` says the step in words ("Searching the web", "Running a command"), `detail`
is what it was given (the search, the command), `kind` is `web`, `browser`, `terminal`, `containers` or `tool`,
`status` is `running`, `done` or `error`. During a call Tide shows the titles; only `terminal` steps open the
island's terminal view (their `detail` as `$ command`, then `terminal` lines).

## Appearance — `appearance`

`PUT {base}/appearance` with `{"accent","accent2","background","surface","text","muted"}` (`#rrggbb`) and `"font"`,
`"mono"` (font names). Tide sends its current look (accent from the wallpaper) when it connects and when the wallpaper
changes, so any windows the assistant opens can match the desktop. `GET {base}/appearance` returns it.

## Voice

- `voice.dictation`: live dictation. `POST {base}/voice/dictation` → `{"id"}`. Then `POST …/{id}/audio` with raw
  16 kHz mono 16-bit PCM (about a quarter second per request) → `{"text","settled","tentative"}`: `text` is everything
  so far, `settled` won't change much any more, `tentative` is the words since the last pause. `POST …/{id}/finish`
  (optionally with the last audio) → `{"text"}`, the final text; `POST …/{id}/cancel` drops it.
  Tide shows `text` in the message box as the person speaks, so return clean text: no "..." for pauses, and
  sentences punctuated as a whole (re-recognize the paragraph, not each piece between pauses).
- `voice.speech`: `POST {base}/voice/speech` with `{"text"}` answers with the voice itself: raw 16-bit PCM, with
  `X-Audio-Sample-Rate` and `X-Audio-Channels` headers, streamed as it is made; Tide plays it as it arrives.
  Closing the stream or `POST {base}/voice/speech/stop` stops it. Used by the play button under replies.
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
  "title": "Status", "subtitle": "Today", "updatedAt": 1795372888426,
  "blocks": [
    { "type": "stat", "label": "Requests today", "value": "1,240", "sub": "12 failed" },
    { "type": "list", "label": "Recent", "icon": "clock",
      "items": [ { "title": "Backup finished", "sub": "nightly job", "trailing": "2 h ago" } ] }
  ]
}
```

Every block is drawn as its own rounded card. Any block may carry `label` (a small grey title at the top of the
card) and `icon` (one of the icon names under Manifest).

| Block | Fields | Looks like |
| --- | --- | --- |
| `hero` | `eyebrow`, `title`, `text`, `footnote`, `speak` (text a Listen button reads aloud; needs `voice.speech`) | A large summary card |
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
first) and `view` (the one shown): Tide shows arrows to step through them (months, for example) and asks
`GET {base}/apps/{id}?view=<id>`.

Chats that only exist to feed an app (a daily report, a log) should be left out of `GET {base}/chats`.

`chat` on an item opens that chat when clicked. `tone`: `normal`, `good`, `warning`, `critical`. Unknown block types
are skipped, so an older Tide still shows the rest. Tide reloads an open app every 30 seconds.

//! Running a script in one of Steam's pages through its DevTools port.

use crate::error::{Error, Result};
use crate::js::{Page, Script};
use crate::ws::{http_get, WebSocket};
use serde_json::{json, Value};
use std::time::{Duration, Instant};

/// What the commands need from Steam. The real one is [`DevTools`]; tests use recorded answers.
pub trait Client {
    /// Titles of the pages Steam has open. `NotRunning` when the port does not answer.
    fn pages(&self) -> Result<Vec<String>>;
    /// The script's result.
    fn run(&self, script: &Script) -> Result<Value>;
}

pub const SHARED_PAGE: &str = "SharedJSContext";

/// The sign-in window is recognised by its title, so Steam must run in English (the OS sets that).
pub fn is_sign_in(title: &str) -> bool {
    title.to_ascii_lowercase().starts_with("sign in")
}

pub struct DevTools {
    pub port: u16,
}

struct Target {
    title: String,
    socket_path: String,
}

impl DevTools {
    fn targets(&self) -> Result<Vec<Target>> {
        let body = http_get(self.port, "/json", Duration::from_secs(5)).map_err(|e| match e.kind() {
            std::io::ErrorKind::ConnectionRefused => Error::NotRunning,
            _ => Error::Connection { port: self.port, detail: e.to_string() },
        })?;
        let list: Vec<Value> = serde_json::from_str(&body).map_err(|e| Error::Connection { port: self.port, detail: format!("target list: {e}") })?;
        Ok(list
            .iter()
            .filter(|t| t["type"] == "page")
            .filter_map(|t| {
                let url = t["webSocketDebuggerUrl"].as_str()?;
                // ws://127.0.0.1:PORT/devtools/page/ID: only the path is used, the address never.
                let path = url.find("/devtools/").map(|i| &url[i..])?;
                Some(Target { title: t["title"].as_str().unwrap_or_default().to_string(), socket_path: path.to_string() })
            })
            .collect())
    }
}

impl Client for DevTools {
    fn pages(&self) -> Result<Vec<String>> {
        Ok(self.targets()?.into_iter().map(|t| t.title).collect())
    }

    fn run(&self, script: &Script) -> Result<Value> {
        let targets = self.targets()?;
        let target = match script.page {
            Page::Shared => targets.iter().find(|t| t.title == SHARED_PAGE).ok_or_else(|| Error::NotReady("it is still starting".into()))?,
            Page::SignIn => targets.iter().find(|t| is_sign_in(&t.title)).ok_or(Error::NoAccountChoice)?,
        };
        let failed = |e: std::io::Error| match e.kind() {
            std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut => Error::Timeout(script.name.into()),
            _ => Error::Connection { port: self.port, detail: e.to_string() },
        };
        let mut socket = WebSocket::connect(self.port, &target.socket_path).map_err(failed)?;
        let request = json!({ "id": 1, "method": "Runtime.evaluate",
            "params": { "expression": script.source(), "awaitPromise": true, "returnByValue": true } });
        socket.send_text(&request.to_string()).map_err(failed)?;
        let deadline = Instant::now() + Duration::from_secs(script.seconds);
        loop {
            let left = deadline.checked_duration_since(Instant::now()).filter(|d| !d.is_zero()).ok_or_else(|| Error::Timeout(script.name.into()))?;
            socket.set_timeout(left).map_err(failed)?;
            let message: Value =
                serde_json::from_str(&socket.read_text().map_err(failed)?).map_err(|e| Error::Connection { port: self.port, detail: e.to_string() })?;
            if message["id"] == 1 {
                let value = answer(script.name, &message)?;
                record(script.name, &value);
                return Ok(value);
            }
        }
    }
}

/// Turns DevTools' reply to one evaluation into the script's result or an error.
pub fn answer(name: &'static str, message: &Value) -> Result<Value> {
    if let Some(e) = message.get("error") {
        return Err(Error::Script { call: name, detail: e["message"].as_str().unwrap_or("DevTools refused the request").to_string() });
    }
    let result = &message["result"];
    if let Some(e) = result.get("exceptionDetails") {
        let detail = e["exception"]["description"].as_str().or(e["text"].as_str()).unwrap_or("exception").to_string();
        return Err(Error::Script { call: name, detail });
    }
    let value = &result["result"]["value"];
    if let Some(ok) = value.get("ok") {
        return Ok(ok.clone());
    }
    let detail = value["detail"].as_str().unwrap_or_default().to_string();
    Err(match value["err"].as_str() {
        Some("call-missing") => Error::CallMissing(detail),
        Some("timeout") => Error::Timeout(detail),
        Some("shape") => Error::UnexpectedShape { call: name, detail },
        Some(_) => Error::Script { call: name, detail },
        // A script that returned `undefined` has no `ok` at all.
        None => Error::UnexpectedShape { call: name, detail: "the script returned nothing".into() },
    })
}

/// With UGOS_STEAM_RECORD set to a folder, every result is also written there, one file
/// per script. That is how the recorded answers the unit tests use were made.
fn record(name: &str, value: &Value) {
    // Friends' names and pictures are never kept.
    if name == "friends" {
        return;
    }
    if let Some(dir) = std::env::var_os("UGOS_STEAM_RECORD").filter(|d| !d.is_empty()) {
        let dir = std::path::PathBuf::from(dir);
        let _ = std::fs::create_dir_all(&dir);
        let _ = std::fs::write(dir.join(format!("{name}.json")), serde_json::to_string_pretty(value).unwrap_or_default());
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn reply(value: Value) -> Value {
        json!({ "id": 1, "result": { "result": { "type": "object", "value": value } } })
    }

    #[test]
    fn a_result_is_unwrapped() {
        assert_eq!(answer("x", &reply(json!({ "ok": [1, 2] }))).unwrap(), json!([1, 2]));
        assert_eq!(answer("x", &reply(json!({ "ok": null }))).unwrap(), Value::Null);
    }

    #[test]
    fn failures_keep_their_code() {
        let code = |v: Value| answer("x", &v).unwrap_err().code();
        assert_eq!(code(reply(json!({ "err": "call-missing", "detail": "SteamClient.Apps.RunGame" }))), "steam-call-missing");
        assert_eq!(code(reply(json!({ "err": "timeout", "detail": "GetLoginUsers" }))), "timeout");
        assert_eq!(code(reply(json!({ "err": "shape", "detail": "not a list" }))), "unexpected-shape");
        assert_eq!(code(reply(json!({ "err": "script-failed", "detail": "x is not a function" }))), "script-failed");
        assert_eq!(code(json!({ "id": 1, "result": { "result": { "type": "undefined" } } })), "unexpected-shape");
        assert_eq!(code(json!({ "id": 1, "result": { "exceptionDetails": { "text": "Uncaught" } } })), "script-failed");
        assert_eq!(code(json!({ "id": 1, "error": { "message": "Cannot find context" } })), "script-failed");
    }

    #[test]
    fn the_sign_in_window_is_found_by_title() {
        assert!(is_sign_in("Sign in to Steam"));
        assert!(!is_sign_in("Steam"));
        assert!(!is_sign_in(SHARED_PAGE));
    }
}

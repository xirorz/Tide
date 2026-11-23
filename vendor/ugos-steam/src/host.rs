//! This machine's side of Steam: is it installed, is it running, starting it hidden
//! with the debugging port on this machine only, and shutting it down.

use crate::cdp::Client;
use crate::error::{Error, Result};
use crate::steam::Host;
use std::fs;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

pub struct RealHost {
    /// The Steam command, possibly with arguments of its own ("steam", or a wrapper script).
    pub command: String,
}

fn find_in_path(program: &str) -> Option<PathBuf> {
    if program.contains('/') {
        return Path::new(program).is_file().then(|| PathBuf::from(program));
    }
    std::env::split_paths(&std::env::var_os("PATH")?).map(|dir| dir.join(program)).find(|p| p.is_file())
}

impl RealHost {
    fn program(&self) -> &str {
        self.command.split_whitespace().next().unwrap_or("steam")
    }

    fn base(&self) -> Command {
        let mut words = self.command.split_whitespace();
        let mut command = Command::new(words.next().unwrap_or("steam"));
        command.args(words);
        command
    }
}

impl Host for RealHost {
    fn installed(&self) -> bool {
        find_in_path(self.program()).is_some()
    }

    fn process_running(&self) -> bool {
        // This player's own Steam only (real accounts: another's is never ours).
        use std::os::unix::fs::MetadataExt;
        // The real uid from status: this program is setgid, so /proc/self belongs to root.
        let me = fs::read_to_string("/proc/self/status").ok().and_then(|s| s.lines().find_map(|l| l.strip_prefix("Uid:")).and_then(|v| v.split_whitespace().next()).and_then(|v| v.parse::<u32>().ok()));
        let Ok(entries) = fs::read_dir("/proc") else { return false };
        entries.flatten().any(|e| {
            e.file_name().to_string_lossy().bytes().all(|b| b.is_ascii_digit())
                && fs::metadata(e.path()).map(|m| Some(m.uid()) == me).unwrap_or(false)
                && fs::read_to_string(e.path().join("comm")).map(|c| c.trim() == "steam").unwrap_or(false)
        })
    }
}

/// True when something listens on `port` on an address other machines can reach.
/// `tcp` and `tcp6` are the texts of /proc/net/tcp and /proc/net/tcp6.
pub fn exposed(tcp: &str, tcp6: &str, port: u16) -> bool {
    let suffix = format!(":{port:04X}");
    let listening_elsewhere = |text: &str, loopback: &[&str]| {
        text.lines().skip(1).any(|line| {
            let mut fields = line.split_whitespace();
            let (Some(local), Some(state)) = (fields.nth(1), fields.nth(1)) else { return false };
            state == "0A" && local.ends_with(&suffix) && !loopback.contains(&&local[..local.len() - suffix.len()])
        })
    };
    listening_elsewhere(tcp, &["0100007F"]) || listening_elsewhere(tcp6, &["00000000000000000000000001000000", "0000000000000000FFFF00000100007F"])
}

fn port_exposed(port: u16) -> bool {
    exposed(&fs::read_to_string("/proc/net/tcp").unwrap_or_default(), &fs::read_to_string("/proc/net/tcp6").unwrap_or_default(), port)
}

/// Starts Steam with no window of its own and its debugging port on `port`. Steam
/// binds that port to 127.0.0.1; this is checked, and Steam is stopped again if the
/// port turns out to be reachable from outside. Returns once the port answers or
/// `patience` has passed (a first start downloads the client and takes much longer).
pub fn start(host: &RealHost, client: &dyn Client, port: u16, patience: Duration) -> Result<()> {
    if !host.installed() {
        return Err(Error::NotInstalled(host.program().into()));
    }
    if client.pages().is_err() && !host.process_running() {
        let mut command = host.base();
        command.args(["-silent", "-cef-enable-debugging", "-devtools-port", &port.to_string()]);
        command.stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null());
        // Its own session: Steam must outlive this command and whoever ran it.
        unsafe {
            command.pre_exec(|| {
                libc::setsid();
                Ok(())
            });
        }
        command.spawn().map_err(|source| Error::Spawn { program: host.program().into(), source })?;
    }
    let until = Instant::now() + patience;
    while client.pages().is_err() && Instant::now() < until {
        std::thread::sleep(Duration::from_millis(500));
    }
    if port_exposed(port) {
        let _ = stop(host, client, Duration::from_secs(30));
        return Err(Error::PortExposed(port));
    }
    Ok(())
}

/// Asks Steam to shut down the way its own Exit does, and waits for it to be gone.
pub fn stop(host: &RealHost, client: &dyn Client, patience: Duration) -> Result<()> {
    if !host.process_running() && client.pages().is_err() {
        return Ok(());
    }
    let mut command = host.base();
    command.arg("-shutdown").stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null());
    command.status().map_err(|source| Error::Spawn { program: host.program().into(), source })?;
    let until = Instant::now() + patience;
    while host.process_running() || client.pages().is_ok() {
        if Instant::now() >= until {
            return Err(Error::Timeout("Steam to shut down".into()));
        }
        std::thread::sleep(Duration::from_millis(500));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    const HEAD: &str = "  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode\n";

    #[test]
    fn a_port_on_this_machine_only_is_not_exposed() {
        // As seen on the development PC: steamwebhelper on 127.0.0.1:8080.
        let tcp = format!("{HEAD}   0: 0100007F:1F90 00000000:0000 0A 00000000:00000000 00:00000000 00000000  1000        0 1 1\n   1: 00000000:0016 00000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 2 1\n");
        assert!(!exposed(&tcp, "", 8080));
        assert!(exposed(&tcp, "", 22));
    }

    #[test]
    fn a_port_on_every_address_is_exposed() {
        let tcp = format!("{HEAD}   0: 00000000:1F90 00000000:0000 0A 00000000:00000000 00:00000000 00000000  1000        0 1 1\n");
        assert!(exposed(&tcp, "", 8080));
        let lan = format!("{HEAD}   0: B500000A:1F90 00000000:0000 0A 00000000:00000000 00:00000000 00000000  1000        0 1 1\n");
        assert!(exposed(&lan, "", 8080));
        let v6 = format!("{HEAD}   0: 00000000000000000000000000000000:1F90 00000000000000000000000000000000:0000 0A 0 0 0 0 0 0 0\n");
        assert!(exposed("", &v6, 8080));
        let v6_local = format!("{HEAD}   0: 00000000000000000000000001000000:1F90 00000000000000000000000000000000:0000 0A 0 0 0 0 0 0 0\n");
        assert!(!exposed("", &v6_local, 8080));
    }

    #[test]
    fn a_connection_from_the_port_is_not_a_listener() {
        let tcp = format!("{HEAD}   0: 00000000:1F90 0100007F:C350 01 00000000:00000000 00:00000000 00000000  1000        0 1 1\n");
        assert!(!exposed(&tcp, "", 8080));
    }

    #[test]
    fn a_missing_command_is_not_installed() {
        assert!(!RealHost { command: "/nonexistent/steam -x".into() }.installed());
        assert!(RealHost { command: "sh".into() }.installed());
    }
}

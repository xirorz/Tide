//! The library as far as Steam's own files on disk tell it: what is installed, and
//! hours for what was played. Used only when Steam is not ready and nothing is cached.
//! Never reads `config.vdf`, `loginusers.vdf` or anything else that holds sign-in data.

use crate::model::Game;
use crate::vdf::{self, Vdf};
use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};

/// Steam's folder: the one given, else the usual places under the home folder.
pub fn steam_root(given: Option<&Path>) -> Option<PathBuf> {
    if let Some(p) = given {
        return p.join("steamapps").is_dir().then(|| p.to_path_buf());
    }
    let home = PathBuf::from(std::env::var_os("HOME")?);
    [".local/share/Steam", ".steam/steam"].iter().map(|p| home.join(p)).find(|p| p.join("steamapps").is_dir())
}

fn read(path: &Path) -> Option<Vdf> {
    Some(vdf::parse(&String::from_utf8_lossy(&fs::read(path).ok()?)))
}

/// The manifests carry no app type, so Steam's own runtime pieces are told by name.
fn looks_like_a_tool(name: &str) -> bool {
    ["Proton ", "Steam Linux Runtime", "Steamworks Common", "Steam Controller Configs", "SteamVR"].iter().any(|p| name.starts_with(p))
}

/// Minutes and last-played per app from the account whose settings were written last.
fn playtimes(root: &Path) -> Option<Vdf> {
    let newest = fs::read_dir(root.join("userdata"))
        .ok()?
        .flatten()
        .map(|e| e.path().join("config/localconfig.vdf"))
        .filter_map(|p| Some((fs::metadata(&p).ok()?.modified().ok()?, p)))
        .max_by_key(|(when, _)| *when)?
        .1;
    read(&newest)?.path(&["UserLocalConfigStore", "Software", "Valve", "Steam", "apps"]).cloned()
}

/// The app ids fully installed in these library folders, by their appmanifest files:
/// the ground truth for "installed on this device". None when a folder cannot be
/// looked at (not mounted, not readable), because then nothing can be concluded.
pub fn installed_ids(libraries: &[String]) -> Option<HashSet<u32>> {
    if libraries.is_empty() {
        return None;
    }
    let mut ids = HashSet::new();
    for library in libraries {
        for entry in fs::read_dir(Path::new(library).join("steamapps")).ok()?.flatten() {
            let name = entry.file_name().to_string_lossy().into_owned();
            let Some(id) = name.strip_prefix("appmanifest_").and_then(|n| n.strip_suffix(".acf")).and_then(|n| n.parse::<u32>().ok()) else { continue };
            // Bit 4: fully installed. A download in progress is not installed yet.
            if read(&entry.path()).and_then(|m| m.get("AppState").map(|a| a.number("StateFlags") & 4 != 0)).unwrap_or(false) {
                ids.insert(id);
            }
        }
    }
    Some(ids)
}

pub fn installed_games(root: &Path, include_tools: bool) -> Vec<Game> {
    let folders = read(&root.join("steamapps/libraryfolders.vdf"));
    let mut libraries: Vec<PathBuf> = folders
        .as_ref()
        .and_then(|f| f.get("libraryfolders"))
        .map(|f| f.entries().filter_map(|(_, v)| v.text("path").map(PathBuf::from)).collect())
        .unwrap_or_default();
    if !libraries.iter().any(|l| l == root) {
        libraries.push(root.to_path_buf());
    }
    let played = playtimes(root);
    let mut games = Vec::new();
    for library in libraries {
        let Ok(entries) = fs::read_dir(library.join("steamapps")) else { continue };
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().into_owned();
            if !(name.starts_with("appmanifest_") && name.ends_with(".acf")) {
                continue;
            }
            let Some(manifest) = read(&entry.path()) else { continue };
            let Some(app) = manifest.get("AppState") else { continue };
            let appid = app.number("appid") as u32;
            let title = app.text("name").unwrap_or_default().to_string();
            // Bit 4: fully installed. A download that never finished is not a game yet.
            if appid == 0 || app.number("StateFlags") & 4 == 0 {
                continue;
            }
            let tool = looks_like_a_tool(&title);
            if tool && !include_tools {
                continue;
            }
            let times = played.as_ref().and_then(|p| p.get(&appid.to_string()));
            let cover = root.join(format!("appcache/librarycache/{appid}/library_600x900.jpg"));
            games.push(Game {
                appid,
                name: title,
                kind: if tool { "tool" } else { "game" }.into(),
                installed: true,
                installed_elsewhere: Vec::new(),
                size_on_disk: app.number("SizeOnDisk"),
                minutes_played: times.map(|t| t.number("Playtime")).unwrap_or(0),
                last_played: times.map(|t| t.number("LastPlayed")).unwrap_or(0).max(app.number("LastPlayed")),
                cover: cover.is_file().then(|| cover.to_string_lossy().into_owned()),
                icon: None,
            });
        }
    }
    games.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()).then(a.appid.cmp(&b.appid)));
    games.dedup_by_key(|g| g.appid);
    games
}

#[cfg(test)]
mod tests {
    use super::*;

    fn write(path: &Path, text: &str) {
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, text).unwrap();
    }

    /// The layout found on the development PC (see research/steam-check/findings.md):
    /// two library folders, tools next to games, and "Apps" spelled with a capital.
    fn pretend_steam(root: &Path, second: &Path) {
        write(
            &root.join("steamapps/libraryfolders.vdf"),
            &format!("\"libraryfolders\"\n{{\n\t\"0\"\n\t{{\n\t\t\"path\"\t\t\"{}\"\n\t}}\n\t\"1\"\n\t{{\n\t\t\"path\"\t\t\"{}\"\n\t}}\n}}\n", root.display(), second.display()),
        );
        let manifest = |id: u32, name: &str, flags: u32, size: u64| {
            format!("\"AppState\"\n{{\n\t\"appid\"\t\t\"{id}\"\n\t\"name\"\t\t\"{name}\"\n\t\"StateFlags\"\t\t\"{flags}\"\n\t\"LastPlayed\"\t\t\"0\"\n\t\"SizeOnDisk\"\t\t\"{size}\"\n}}\n")
        };
        write(&root.join("steamapps/appmanifest_1493710.acf"), &manifest(1493710, "Proton Experimental", 6, 1537142909));
        write(&root.join("steamapps/appmanifest_292030.acf"), &manifest(292030, "The Witcher 3: Wild Hunt", 4, 69795378546));
        write(&second.join("steamapps/appmanifest_238960.acf"), &manifest(238960, "Path of Exile", 4, 71627951692));
        write(&second.join("steamapps/appmanifest_99.acf"), &manifest(99, "Half Downloaded", 1026, 5));
        write(
            &root.join("userdata/7/config/localconfig.vdf"),
            "\"UserLocalConfigStore\" { \"Software\" { \"Valve\" { \"Steam\" { \"Apps\" { \"238960\" { \"Playtime\" \"65752\" \"LastPlayed\" \"1791152617\" } \"230410\" { \"Playtime\" \"103501\" } } } } } }",
        );
        write(&root.join("appcache/librarycache/238960/library_600x900.jpg"), "jpg");
    }

    #[test]
    fn installed_games_come_from_the_manifests_with_hours_from_localconfig() {
        let dir = tempfile::tempdir().unwrap();
        let (root, second) = (dir.path().join("Steam"), dir.path().join("SteamLibrary"));
        pretend_steam(&root, &second);
        let games = installed_games(&root, false);
        assert_eq!(games.iter().map(|g| g.appid).collect::<Vec<_>>(), [238960, 292030]);
        let poe = &games[0];
        assert_eq!((poe.minutes_played, poe.last_played, poe.size_on_disk), (65752, 1791152617, 71627951692));
        assert!(poe.cover.as_deref().unwrap().ends_with("238960/library_600x900.jpg"));
        assert_eq!(games[1].minutes_played, 0);
        // Tools only on request; the unfinished download never.
        let all = installed_games(&root, true);
        assert_eq!(all.len(), 3);
        assert_eq!(all.iter().find(|g| g.appid == 1493710).unwrap().kind, "tool");
    }

    #[test]
    fn installed_ids_are_the_finished_manifests_in_the_given_folders() {
        let dir = tempfile::tempdir().unwrap();
        let (root, second) = (dir.path().join("Steam"), dir.path().join("SteamLibrary"));
        pretend_steam(&root, &second);
        let folders = [root.display().to_string(), second.display().to_string()];
        let ids = installed_ids(&folders).unwrap();
        // 99 is half downloaded; Proton has flags 6 (installed, update wanted).
        assert_eq!(ids, HashSet::from([1493710, 292030, 238960]));
        // A folder that cannot be read: no conclusion, rather than "nothing is installed".
        assert!(installed_ids(&[root.display().to_string(), "/nonexistent/library".into()]).is_none());
        assert!(installed_ids(&[]).is_none());
    }

    #[test]
    fn no_steam_folder_gives_an_empty_list() {
        let dir = tempfile::tempdir().unwrap();
        assert!(installed_games(dir.path(), true).is_empty());
        assert!(steam_root(Some(dir.path())).is_none());
    }
}

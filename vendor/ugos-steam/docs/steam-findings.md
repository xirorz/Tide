# Steam client check on the development PC

Date: 2026-11-10. Read-only look at what the installed Steam client exposes.
Account ids are shortened. No tokens, cookies or passwords were read.

Status: **Parts 1 and 2 complete, and the service built from them (`ugos-steam`) checked against the real client (last section). Steam is shut down again, as it was before the check.**

## Setup

- **Steam root: confirmed** `~/.local/share/Steam`. `~/.steam/steam` and `~/.steam/root` are symlinks to it. No Flatpak install (`~/.var/app/com.valvesoftware.Steam` absent).
- **Install method: confirmed** native Arch/CachyOS package `steam 1.0.0.87-3` (`pacman -Qs`), launcher `/usr/bin/steam` (shell script).
- Also installed: package `slssteam` ("Steamclient Mod"), which adds a second launcher that starts Steam with `LD_AUDIT` injection. All checks here use the plain `/usr/bin/steam`, without it.
- Two accounts have data under `userdata/`: `72…98` (most recently used, the large library) and `10…39`.
- Steam was **not running** when the check began.

Helper scripts: `part1_files.py` (output in `part1_output.txt`), `part1_librarycache_shape.py`, `cdp.mjs`, `cdp_page.mjs`, and the probes `probe_a_library.js`, `probe_b_methods.js`, `probe_h_overlay.js`, `probe_e_install_dry.js`, `probe_e2_install_variants.js`. Raw probe results are in the `out_*.json` files (not committed: they list the owner's whole library).

## Part 1: local files

### a) `steamapps/libraryfolders.vdf` — confirmed

Text VDF. Top key `libraryfolders`, then one numbered entry per library folder. Two folders here:

| index | path | totalsize | apps |
|---|---|---|---|
| 0 | `~/.local/share/Steam` | 0 | 9 |
| 1 | `/mnt/Data/SteamLibrary` | 983334674432 | 6 |

Keys per entry: `path`, `label` (empty on both), `contentid`, `totalsize`, `update_clean_bytes_tally`, `time_last_update_verified`, `apps`. `apps` maps app id to size on disk in bytes. `totalsize` is 0 for the default folder, so it is not a reliable disk size.

### b) `steamapps/appmanifest_<appid>.acf` — confirmed

One per installed app, in the `steamapps` folder of the library that holds it. 15 in total (9 + 6). Keys under `AppState`:
`appid`, `universe`, `name`, `StateFlags`, `installdir`, `LastUpdated`, `LastPlayed`, `SizeOnDisk`, `StagingSize`, `buildid`, `LastOwner`, `DownloadType`, `UpdateResult`, `BytesToDownload`, `BytesDownloaded`, `BytesToStage`, `BytesStaged`, `TargetBuildID`, `AutoUpdateBehavior`, `AllowOtherDownloadsWhileRunning`, `ScheduledAutoUpdate`, `InstalledDepots`, `UserConfig`, `MountedConfig`.

`StateFlags` is a bit field. Values seen:

- `4` = FullyInstalled (12 apps)
- `6` = FullyInstalled + UpdateRequired (Proton Experimental, Path of Exile 2)
- `1542` = FullyInstalled + UpdateRequired + UpdatePaused (512) + UpdateStarted (1024) (Steam Linux Runtime 1.0)

Other bits, from the public EAppState list, not seen here: 1 Uninstalled, 8 UpdateQueued, 256 UpdateRunning, 2048 Uninstalling, 1048576 Reconfiguring, 2097152 Validating, 16777216 Downloading, 33554432 Staging, 67108864 Committing. Download progress can be read from `BytesDownloaded` / `BytesToDownload`.

Of the 15 manifests only 6 are things a user would call a game or app (Witcher 2, Witcher 3, Path of Exile, Path of Exile 2, Blender, Lossless Scaling). The rest are Proton versions, Linux runtimes and redistributables, so a library view must filter by app type, which the manifest does not carry.

### c) `userdata/<account>/config/localconfig.vdf` — confirmed

- Exact key path: `UserLocalConfigStore/Software/Valve/Steam/apps/<appid>/Playtime` and `…/LastPlayed`. The `apps` key is spelled `apps` for one account and `Apps` for the other, so it must be matched without regard to case.
- `Playtime` is in minutes, `LastPlayed` is a Unix time. Other per-app keys: `Playtime2wks`, `PlaytimeDisconnected`, `LaunchOptions`, `cloud`, `autocloud`, `BadgeData`, EULA markers.
- Account `72…98`: 260 apps listed, 238 with `Playtime`, 244 with `LastPlayed`. 250 of the 260 are **not installed**. Examples: app 230410 `Playtime=103501`, app 38830 `Playtime=101863`, app 238960 `Playtime=65752` (installed).
- Account `10…39`: 28 apps listed, 10 with `Playtime`, 20 with `LastPlayed`, 22 not installed.
- So this file does include owned games that are not installed, but only ones that have been played or touched. It is not the full owned list (see g).
- Overlay-related keys found here: `system/InGameOverlayShowFPSCorner` and per-game `WebStorage/OverlaySavedDataV2_<appid>_windows`. Neither is the global overlay switch (see Part 2 h).

### d) `userdata/<account>/config/librarycache/` — confirmed

- Exists for both accounts. 66 files for `72…98` (65 per-app `<appid>.json` plus `achievement_progress.json`), 30 for `10…39` (no `achievement_progress.json`). Sizes range from 126 bytes (empty) to about 14 KB.
- 50 of the 65 per-app files are for games that are not installed. Files appear only for games whose page has been opened in the Steam library, so coverage is partial.
- Per-app file: a JSON array of `[section name, {version, data}]` pairs. Sections: `achievements`, `achievementmap`, `badge`, `usernews`, `gameactivity`, `associations`, `descriptions`.
  - `achievements.data`: `nTotal`, `nAchieved`, `vecHighlight[]`, `vecUnachieved[]`, `vecAchievedHidden[]`. Each achievement: `strID`, `strName`, `strDescription`, `bAchieved`, `rtUnlocked` (Unix time), `strImage` (full https URL on `shared.steamstatic.com/community…`), `bHidden`, `flAchieved` (global percentage), `flMinProgress`, `flCurrentProgress`, `flMaxProgress`. Example: `{"strID":"KillAllBreachlords","strName":"Breachlord","bAchieved":true,"rtUnlocked":1789307624,…}`.
  - `achievementmap.data`: a JSON string holding every achievement for the app.
  - `associations.data`: `rgDevelopers[]`, `rgPublishers[]`, `rgFranchises[]` (`strName`, `strURL`).
  - `descriptions.data`: `strFullDescription`, `strSnippet`.
- `achievement_progress.json`: keys `nVersion`, `mapCache`. `mapCache` is a list of `[appid, {appid, unlocked, total, percentage, all_unlocked, cache_time, vetted}]`. Only 2 entries here. Example: `[238960, {"unlocked":103,"total":127,"percentage":81.1,"all_unlocked":false,…}]`.

### e) `appcache/librarycache/<appid>/` — confirmed

757 per-app folders. Example, app 20920: `header.jpg`, `library_600x900.jpg` (portrait cover), `library_hero.jpg`, `library_hero_blur.jpg`, `logo.png`, and one file named by a SHA-1 hash (the small icon). Across all apps: `header.jpg` 621, hash-named icon 369, `library_hero.jpg` 281, `library_600x900.jpg` 251, `logo.png` 230, `library_hero_blur.jpg` 229, `library_header.jpg` 77, `library_capsule.jpg` 41. Artwork is cached only once Steam has displayed the app, so the portrait cover is missing for about two thirds of the folders.

### f) `appcache/stats/` — confirmed

Both kinds exist: `UserGameStatsSchema_<appid>.bin` for 32 apps, `UserGameStats_<account>_<appid>.bin` for 31 apps (`72…98`) and 1 app (`10…39`). Binary VDF. Present only for games that have been run or whose achievements were viewed.

### g) Complete owned list from local files — not available as plain text

| source | count | what it is |
|---|---|---|
| appmanifests | 15 | installed only, includes tools |
| `localconfig.vdf` apps (`72…98`) | 260 | played or touched, installed or not |
| `librarycache/*.json` (`72…98`) | 65 | game pages opened in Steam |
| `appcache/librarycache` folders | 757 | artwork Steam has shown, includes store items not owned |
| `appcache/stats` schemas | 32 | games run |

No readable local file lists every owned game. The ownership data is in `userdata/<account>/config/licensecache` (binary, 17 KB, not read) combined with `appcache/packageinfo.vdf` and `appcache/appinfo.vdf` (binary). Parsing those is possible but fragile, and they are only current after Steam has run. The live client is the dependable source: it reports 243 owned games (401 owned apps of all kinds), against 260 entries in `localconfig.vdf` (which mixes in tools, demos and removed items) and 4 installed games.

## Part 2: the internal interface

### Starting Steam with the debugging port — confirmed

- Steam was not running, so it was started as `/usr/bin/steam -silent -cef-enable-debugging`.
- The port answered after 4 seconds. `ss -ltnp` shows `127.0.0.1:8080` owned by `steamwebhelper`. Requests to the LAN address and the Tailscale address on port 8080 were refused, so it is local only.
- `http://127.0.0.1:8080/json` lists the targets; `SharedJSContext` is present and `cdp.mjs` can evaluate JavaScript in it.
- Download state read from `SteamClient.Downloads.RegisterForDownloadOverview`: the callback fires at once without any download, with `update_state: "None"`, `paused: true`, `update_appid: 0`. No download is active and no game is running.

### Sign-in — confirmed, with a catch

Steam did not sign in by itself. It opened its account picker ("Sign in to Steam": the two saved accounts and Add Account). The library stayed empty (`appStore.allApps` had 0 entries, `collectionStore.allAppsCollection` threw) until an account was chosen. With the owner's go-ahead the owner's entry was clicked through the picker's own page; 401 apps were loaded 3 seconds later. No credentials were typed or read.

For the design: with more than one saved account a hidden background Steam waits at this picker and shows nothing. `SteamClient.User.GetStartupUserChooserState`, `GetLoginUsers` and `RegisterForLoginStateChange` exist to detect and drive this.

### a) Full owned library — confirmed

| call | result |
|---|---|
| `collectionStore.allGamesCollection.allApps` | works, **243 owned games** (collection id `my-games`) |
| `collectionStore.allAppsCollection.allApps` | works, 401 owned apps of every type |
| `appStore.allApps` | works, same 401 |
| `collectionStore.localGamesCollection.allApps` | works, **4 installed games** |
| `SteamClient.Apps.GetLibraryBootstrapData` | not available, the method no longer exists in this client |

`app_type` counts across the 401: `1` game 240, `2` application 6, `4` tool 152, `8` demo 2, `65536` one other. So the type filter that the manifests lack is available here.

Fields per app overview (all present for games that are not installed too): `appid`, `display_name`, `app_type`, `installed`, `size_on_disk` (installed only, a string of bytes), `minutes_playtime_forever`, `minutes_playtime_last_two_weeks`, `rt_last_time_played`, `rt_purchased_time`, `rt_original_release_date`, `metacritic_score`, `review_percentage`, `icon_hash`, `header_filename`, `library_capsule_filename`, `per_client_data[]` (`installed`, `display_status`, `status_percentage`, `is_available_on_current_platform`), store tags and categories, and helper methods such as `BIsSteamDeckVerified`, `BIsDemo`, `BIsShortcut`.

170 of the 243 games have playtime. Example, not installed: `{"appid":202750,"display_name":"Alan Wake's American Nightmare","installed":false,"minutes_playtime_forever":24,"rt_last_time_played":1420859621}`.

Changes can be followed live with `SteamClient.Apps.RegisterForAppOverviewChanges`.

Artwork for any owned game, installed or not: `appStore.GetVerticalCapsuleURLForApp(overview)` returns `https://shared.steamstatic.com/store_item_assets/steam/apps/<appid>/library_600x900.jpg?t=…`, and `appStore.GetIconURLForApp(overview)` returns the icon URL. So covers do not depend on the partial local cache from Part 1 e).

### b) Hours — confirmed

- `SteamClient.Apps.GetPlaytime(238960)` returns `{"nPlaytimeLastTwoWeeks":0,"nPlaytimeForever":67408,"rtLastTimePlayed":1791152617}` (minutes, Unix time).
- The app overview objects already carry `minutes_playtime_forever` and `rt_last_time_played`, so one pass over the library gives hours for every game without a call per game.

### c) Achievements — confirmed, including games that are not installed

`SteamClient.Apps.GetMyAchievementsForApp("<appid>")` (app id as a string) returns `{result, data: {rgAchievements: [...]}}`.

- Fields per achievement: `strID`, `strName`, `strDescription`, `bAchieved`, `rtUnlocked` (Unix time), `strImage`, `bHidden`, `flMinProgress`, `flCurrentProgress`, `flMaxProgress`, `flAchieved`.
- Icon URL form: `https://shared.steamstatic.com/community_assets/images/apps/<appid>/<hash>.jpg`.
- Installed game 238960: 127 achievements, 103 unlocked.
- Not installed: Baldur's Gate 3 (1086940) 54 of 54, Blacklight: Retribution (209870) 17 of 25, Black Desert (582660) an empty list. The call does not need the game installed or its page opened.
- Related: `RegisterForAchievementChanges`, `GetAchievementsInTimeRange`, `GameSessions.RegisterForAchievementNotification`.

### d) Install folders — confirmed

`SteamClient.InstallFolder.GetInstallFolders()` returns one entry per library folder: `nFolderIndex`, `strFolderPath`, `strUserLabel`, `strDriveName`, `nCapacity`, `nFreeSpace`, `nUsedSize`, `nAppSize`, `nDLCSize`, `nWorkshopSize`, `nStagedSize`, `nShaderSize`, `bIsDefaultFolder`, `bIsMounted`, `bIsFixed`, `vecApps[]` (`nAppID`, `strAppName`, `strSortAs`, `rtLastPlayed`, `nUsedSize`, …).

Here: index 0 `~/.local/share/Steam` (104 GB free, not default) and index 1 `/mnt/Data/SteamLibrary` (376 GB free, **default**). Unlike `libraryfolders.vdf` this gives real capacity and free space.

Adding a folder: `AddInstallFolder` exists, with `GetPotentialFolders`, `SetDefaultInstallFolder`, `SetFolderLabel`, `RemoveInstallFolder`, `MoveInstallFolderForApp`, `RegisterForInstallFolderChanges`. None were called.

### e) Install flow, dry — confirmed, with no Steam window

Methods on `SteamClient.Installs`: `CancelInstall`, `ContinueInstall`, `GetInstallManagerInfo`, `OpenInstallBackup`, `OpenInstallWizard`, `OpenUninstallWizard`, `RegisterForShowConfirmUninstall`, `RegisterForShowFailedUninstall`, `RegisterForShowInstallWizard`, `RegisterForShowRegisterCDKey`, `SetAppList`, `SetCreateShortcuts`, `SetInstallFolder`.

Tested with Alan Wake (108710), owned and not installed. `ContinueInstall` was never called.

- `OpenInstallWizard([108710])` alone: the `RegisterForShowInstallWizard` callback fired once, but `GetInstallManagerInfo` stayed empty (`rgApps: []`). Same with a bare number. On its own it does not load the app.
- `SetAppList([108710])` followed by `OpenInstallWizard([108710])`: `GetInstallManagerInfo` returned `{"rgApps":[{"nAppID":108710,"lDiskSpaceRequiredBytes":21617394233}],"eInstallState":0,"nDiskSpaceRequired":21617394233,"nDiskSpaceAvailable":103710179328,"bCanChangeInstallFolder":true,"iInstallFolder":0,"currentAppID":0,"eAppError":0,"bSystemMenuShortcut":false,"bDesktopShortcut":false,…}`. This gives the required size before anything is downloaded.
- `SetInstallFolder(1)` (the default folder's index): `iInstallFolder` became 1 and `nDiskSpaceAvailable` changed to that drive's free space. So choosing the drive from the OS works.
- `CancelInstall()`: the info went back to empty. The game is still not installed and the manifest count is still 15.
- **No visible window appeared.** The list of DevTools targets gained no dialog, and Steam's existing windows reported `document.visibilityState: "hidden"` throughout (started with `-silent`). The OS can show its own install dialog from this data.
- Not tested: `ContinueInstall`, which is the step that starts the download. Whether it also needs a EULA step (`Apps.LoadEula`, `MarkEulaAccepted`) for some games is open.

### f) Download progress — confirmed

`SteamClient.Downloads` methods: `EnableAllDownloads`, `MoveAppUpdateDown`, `MoveAppUpdateUp`, `PauseAppUpdate`, `QueueAppUpdate`, `RegisterForDownloadItems`, `RegisterForDownloadOverview`, `RegisterForRemoteClientsConnected`, `RemoveFromDownloadList`, `ResumeAppUpdate`, `SetLaunchOnUpdateComplete`, `SetQueueIndex`, `SuspendDownloadThrottling`, `SuspendLanPeerContent`.

- `RegisterForDownloadOverview` fires immediately without starting a download. Shape: `update_state` (`"None"`, `"Updating"`), `update_appid`, `update_network_bytes_per_second`, `update_disc_bytes_per_second`, `progress[]` (`bytes_in_progress`, `bytes_total`, `estimated_time_remaining_sec`), `overall_percent_complete`, `overall_estimated_time_remaining_sec`, `update_is_install`, `update_is_shader`, `paused`, `download_throttle_rate`, `history[]`.
- `RegisterForDownloadItems` also fires immediately, with the queue. Each item: `appid`, `active`, `paused`, `completed`, `deferred_time`, `queue_index`, `update_result`, `update_error`, `completed_time`, `buildid`, `target_buildid`, `launch_on_completion`, `update_type_info[]` (`has_update`, `completed`, `progress[]`, `overall_percent_complete`).
- Seen live during the check (see "What went wrong"): `update_state: "Updating"`, `update_appid: 2694490`, about 79 MB/s.

### g) Launch and running state — methods listed, nothing launched

- Launch and stop: `SteamClient.Apps.RunGame`, `TerminateApp`, `CancelLaunch`, `CancelGameAction`, `ContinueGameAction`, `RaiseWindowForGame`, `LaunchNonSteamApp`, `VerifyApp`.
- Launch progress: `RegisterForGameActionStart`, `RegisterForGameActionTaskChange`, `RegisterForGameActionShowUI`, `RegisterForGameActionShowError`, `RegisterForGameActionUserRequest`, `RegisterForGameActionEnd`, `GetActiveGameActions`, `GetGameActionDetails`.
- Running state: `SteamClient.GameSessions.RegisterForAppLifetimeNotifications`; in the page, `SteamUIStore.RunningApps` (0 during the check).
- Launch options and compatibility: `GetLaunchOptionsForApp`, `SetAppLaunchOptions`, `SpecifyCompatTool`, `ClearProton`.
- Shutdown from inside: `SteamClient.User.StartShutdown`, `StartRestart`.

### h) Turning the overlay off globally — setting found, not changed

- The global switch is the client setting **`enable_overlay`** (currently `true`), read from `settingsStore.m_ClientSettings.enable_overlay`. It is the "Enable the Steam Overlay while in-game" checkbox and is written through `SteamClient.Settings.SetSetting`. The exact argument form of `SetSetting` was not exercised.
- Per game: `SteamClient.Apps.ToggleEnableSteamOverlayForApp`.
- It is not in `localconfig.vdf` here (only `system/InGameOverlayShowFPSCorner` is). Which file stores it once turned off was not checked, since `config.vdf` is off limits for this check.
- Related settings seen, useful for the background design: `run_at_startup: false`, `start_in_big_picture_mode: false`, `start_page: "store"`, `always_use_gamepadui_overlay: false`. 270 client settings in total.

## What went wrong, and the state Steam was left in

- **Steam auto-updated two things once it was signed in.** None of the probes asked for it; it is Steam's normal behaviour at sign-in. Proton Experimental finished updating (`StateFlags` 6 to 4). The Path of Exile 2 update downloaded 11.72 of 11.74 GB before shutdown; its manifest is now `StateFlags=1030` (FullyInstalled + UpdateRequired + UpdateStarted) where it was 6. Steam will finish it the next time it runs. The first download-state reading, taken at the account picker, had said `paused: true`, which was only true while signed out.
- For the design this matters: a background Steam will start game updates by itself at sign-in. `Downloads.EnableAllDownloads` and the auto-update restriction settings are the levers.
- The first run of `probe_e_install_dry.js` stopped on a mistake in the script (a `fetch` that the page blocks) after opening the wizard and before cancelling. `CancelInstall` was called right after and the state was empty; the line was removed and the test rerun.
- **Restored state:** Steam was shut down with `steam -shutdown` and exited after 6 seconds. No Steam process is left and `127.0.0.1:8080` no longer answers. Steam was not running before the check, so it was left not running. No game was installed, uninstalled or launched, no setting was changed, and no Steam file was edited by hand.

## Service check: `ugos-steam` against the real client (2026-11-10, later the same day)

`crates/ugos-steam` was built from the findings above and run against the same Steam
(client build Oct 21 2026 21:09:51, version 1792618285, SteamClient023), signed in to the
owner's main account. Commands and their output format: `docs/steam-integration.md`.
Corrections to the sections above that this turned up:

- **Port: confirmed configurable.** `steam -silent -cef-enable-debugging -devtools-port 8089`
  listened on `127.0.0.1:8089`. Without the flag it is 8080.
- **Account list: confirmed.** `SteamClient.User.GetLoginUsers()` returns `accountName`,
  `personaName`, `rememberPassword`, `avatarUrl`, `rtLastLogin`, `hasPin` per saved
  account. Both saved accounts have the same display name, so the list has to be
  chosen from by account name. At the list `App.m_eLoginState` is 1 and
  `App.m_CurrentUser.strAccountName` is empty; signed in it is 5 with the name set. The
  account list window is visible on screen even with `-silent`.
- **Install, corrected.** `OpenInstallWizard([appid], "0")` (second argument: the client
  id, "0" for this machine) loads the app by itself and puts the install manager in
  state 7 (`k_EInstallMgrStateShowConfig`). The `SetAppList` detour in e) above is not
  needed. `SetInstallFolder(index)` then `ContinueInstall()` moved it to state 14
  (complete) within a quarter of a second and the app appeared in the download queue.
  Install manager states, from the client's script: 0 none, 1 setup, 2 wait licence,
  3 free licence, 4 CD key, 5 wait app info, 6 password, 7 show config, 8 show EULAs,
  9 create apps, 10 read from media, 11 change media, 12 wait legacy CD keys,
  13 sign-up, 14 complete, 15 failed, 16 cancelled.
- **Full install: confirmed.** PICO PARK (1509960, 80 MB) installed to the default
  folder: download state `Starting`, `Downloading`, `Finalizing`; its appmanifest went
  `StateFlags` 2, 1026, 4 in about ten seconds; the library entry turned
  `installed: true`. No Steam window.
- **Licence agreements.** For Skyrim Script Extender (365720, 1.4 MB, free) and Warface:
  Clutch (291480, 130 MB, free) `ContinueInstall()` stopped at state 8.
  `SteamClient.Apps.LoadEula(appid)` returns `[{id, url, version}]`; Steam's own window
  calls `SteamClient.Apps.MarkEulaAccepted(appid, id, version)` for each and then
  `ContinueInstall()` again. Neither agreement was accepted; both installs were
  cancelled and nothing was installed.
- **Uninstall: confirmed.** `SteamClient.Installs.OpenUninstallWizard([appid], "0", true)`
  removed PICO PARK with no window; its manifest and folder were gone.
- **Launch and stop, from the client's script only (not run):**
  `SteamClient.Apps.RunGame(gameid, "", -1, <launch source>)` and
  `SteamClient.Apps.TerminateApp(gameid, false)`.
- **Overlay: how it is written.** `SteamClient.Settings.SetSetting(base64)` takes a
  serialised settings message holding the changed field; `enable_overlay` is field 4004
  (boolean), so "off" is the bytes `A0 FA 01 00`. Sending "on" while it was on was
  accepted and left it on. "Off" was not sent.
- **Downloads.** With a download being set up, `overall_estimated_time_remaining_sec` is
  absent from the overview. `EnableAllDownloads(false)` with an empty queue did not
  change the overview's `paused` flag.
- **Reaching the port from a web page.** A websocket request with an `Origin` header
  got no answer; without one it was accepted (101). `/json` answers a request with an
  `Origin` but sends no cross-origin permission header. A foreign `Host` header got 500.
- **Sizes.** A dry run over all 236 uninstalled games gave a required size for 234 of
  them, in about a third of a second each.

Changes this made to Steam on the PC: Path of Exile 2's pending update finished by
itself after sign-in. PICO PARK was installed and removed again. Nothing else: no
setting changed, no agreement accepted, no game started. Steam was shut down at the
end and no debugging port is left open.

## Follow-up after the first test on the Legion Go (2026-11-10, evening)

Scripts: `watch_windows.py` (window and page listing around a command), `probe_k` to
`probe_p`. Same client build as above.

- **The window during the size query: confirmed and removed.** `OpenInstallWizard([appid], "0")`
  makes Steam's interface open an "Install" dialog (X11 window "Install", 540x480) and
  map Steam's main window ("Steam") with it, 0.75 s after the call on this PC. The
  earlier "no visible window" finding was wrong: it only looked at whether the existing
  pages reported themselves hidden, not at the compositor.
- **Size without the wizard: confirmed.** `SetAppList([appid])`, `GetInstallManagerInfo()`,
  `SetInstallFolder(index)`, `CancelInstall()` gives the required size and the folder's
  free space, with no window or new page in 16 s. `ContinueInstall()` from that state
  does nothing (state stays 0), so it cannot start an install.
- **Install without the dialog: confirmed.** The dialog is opened by the interface's
  game-actions store (webpack module 65691 in this build, export `I`, found by the field
  name `m_unAppIDExpectedInstall`), method `OnShowInstallWizard`. For state 7 it starts
  the install with no dialog when `!BShowDeckCompatForInstall(expected, …) &&
  !BShowDiskSettingsForInstall(info)`, by calling `StartRequestedInstall()`. Setting
  `m_unAppIDExpectedInstall`, answering both checks with false and replacing
  `StartRequestedInstall` for the length of the call (own properties on the instance,
  deleted afterwards) gives an install with no window. PICO PARK installed and was
  removed again this way.
- **Licences.** `SteamClient.Apps.LoadEula(appid)` rejects with `{result: 42, message:
  "No eula for app"}` when there is none. Asking it before `ContinueInstall` avoids
  state 8 and Steam's own agreement window.
- **Toast window.** About 23 s after the install started Steam mapped
  "notificationtoasts_3_desktop" (283x70) for "download complete"; it went away by
  itself. Client setting `disable_all_toasts` is field 6000 (boolean) of the settings
  message; `disable_toasts_in_game` is 6001. Steam's code skips a toast when
  `disable_all_toasts` is set unless the toast is marked critical.
- **Installed here or on another computer.** The app overview's `installed` is
  `most_available_per_client_data.installed`; `local_per_client_data` is the entry of
  `per_client_data` with `clientid == "0"`; an entry is local when it has no client id
  or "0" (`BIsPerClientDataLocal`). Entries carry `clientid`, `client_name`, `installed`,
  `display_status`, `status_percentage`. On this PC every app had exactly one entry
  ("0", "This machine"), so a remote entry was not seen.
- **Worldwide achievement percentages.** `GetMyAchievementsForApp` returns `flAchieved`
  0 for all 127 Path of Exile achievements. The interface gets the figures from a
  separate service request (`CPlayer_GetGlobalAchievementPercentages`) through its
  achievements store. A `fetch` of the public web address from the shared page failed.
  Left as it is.
- **Changes to Steam on the PC during this follow-up:** its main window was shown once
  by the reproduction and hidden again; PICO PARK was installed and removed once more;
  no setting was changed. Steam was
  already running when the work started and was left running.

## Settings timing, and the end of live checks on this PC (2026-11-10, late)

- **Settings arrive during sign-in.** Traced with `probe_r_settings_timeline.js` across a
  fresh start: at the account list (`m_eLoginState` 1) `settingsStore.m_ClientSettings`
  has 86 keys, without `enable_overlay` or `disable_all_toasts`; 1.7 s after the account
  was chosen (login state 3) it has 270, with both. `ugos-steam`'s "ready" (account
  name set, library loaded) came at login state 4; state 5 followed 1.4 s later. The
  store has no "loaded" flag; settings come as messages through
  `RegisterForSettingsArrayChanges`.
- **A setting sent at the ready moment stuck on this PC** (`disable_all_toasts` sent at
  3.36 s, read back true from 3.48 s to the end of the 25 s trace, and after).
- **`disable_all_toasts` belongs to the account, `enable_overlay` to the computer.**
  `DisableAllToasts` is in `userdata/<account>/7/remote/sharedconfig.vdf` (the "roaming
  config store" Steam's log reports loading and saving at sign-in); `EnableGameOverlay`
  is in `userdata/<account>/config/localconfig.vdf`. After the Legion Go had turned
  toasts off, this PC's Steam read toasts off at its next start before anything was
  sent here.
- **One unexplained shutdown.** About 12 s after both settings were sent immediately
  after a sign-in, Steam logged a clean "Shutdown". It did not happen again in three
  further starts, with or without settings being sent, and another session was working
  with Steam on this PC at the time, so the cause is not known.
- **Live use stopped.** On the owner's word no further command was run against Steam
  on this PC from 17:26 local time. Steam was already shut down then (by another
  session). State left behind: overlay on, as before; toasts **off**
  (`DisableAllToasts "1"`), where they had been on in the running client when this
  work began; PICO PARK not installed. Everything later in `ugos-steam` (settings
  retry, launch phases, messages) is unit tested only.

## From the Legion Go's log, version 23 (2026-11-10, 22:53 to 22:55 UTC, read only)

`/var/lib/ugos/logs/steam-day-20767.log`, the owner's own launches of Another Crab's
Treasure (1887840). Nothing was run on the device for this.

- **First launch, 22:55:08:** `preparing` task "" → `preparing` task `SynchronizingCloud`
  → `needs-attention` task `ProcessingShaderCache` → `running` → `stopping` → `ended`
  (`"ended": "stopped"`).
- **Second launch, 22:55:24:** `preparing` task "" → `preparing` task
  `SynchronizingControllerConfig` → `running` → `stopping` → `ended`.
- So the task name is the fourth argument of the task-change and user-request
  callbacks, as assumed, and `ProcessingShaderCache` arrives through
  `RegisterForGameActionUserRequest` (that is what made it "needs attention").
- `start --wait 120` answered `needs-account-choice` first and Steam was ready by
  itself seconds later, with one saved account.
- `overlay off`: `{ "applied": true, "attempts": 0, "enabled": false }`.
- `game 1887840` at 22:53:41 had `global_percent` 0.0 on every achievement; at 22:55:08
  it had real values (23.4 for the first). Steam fetches them after the first request.
- Steam's library folder on the device: `/var/lib/ugos/steam/dot-steam/debian-installation`.

Game-action calls in the recorded method list of `SteamClient.Apps` (probe b):
`CancelGameAction`, `ContinueGameAction`, `GetActiveGameActions`,
`GetGameActionDetails`, `GetGameActionForApp`, and the six `RegisterForGameAction…`
registrations. No call with "Skip" or "Shader" in its name.

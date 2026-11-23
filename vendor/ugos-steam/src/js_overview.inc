const url = (f, a) => { try { const u = appStore[f](a); return (typeof u === 'string' && u) ? u : null; } catch (e) { return null; } };
// Steam keeps one entry per computer that has the app: client id "0" (or none) is this
// machine, any other is a computer of the same account found on the network (Remote
// Play). The overview's own `installed` follows the "most available" computer, so it is
// true for a game that is only installed on another PC. It is not used here.
const here = (a) => { const c = (a.per_client_data || []).find((c) => !c.clientid || String(c.clientid) === '0'); return !!(c && c.installed); };
const elsewhere = (a) => (a.per_client_data || []).filter((c) => c.clientid && String(c.clientid) !== '0' && c.installed).map((c) => String(c.client_name || ''));
const overview = (a) => ({
  appid: a.appid, name: a.display_name, type: a.app_type, installed: here(a), installed_elsewhere: elsewhere(a),
  size_on_disk: here(a) ? Number(a.size_on_disk || 0) : 0,
  minutes_played: a.minutes_playtime_forever || 0, last_played: a.rt_last_time_played || 0,
  cover: url('GetVerticalCapsuleURLForApp', a), icon: url('GetIconURLForApp', a) });
// The library folders as Steam itself lists them, for checking installs against the
// appmanifest files on disk.
const library_paths = async () => { try { const f = await wait(SteamClient.InstallFolder.GetInstallFolders(), 'GetInstallFolders'); return f.filter((x) => x.bIsMounted !== false).map((x) => String(x.strFolderPath)); } catch (e) { return []; } };

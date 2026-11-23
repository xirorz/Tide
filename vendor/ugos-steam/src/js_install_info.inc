const info = async () => { const i = await wait(SteamClient.Installs.GetInstallManagerInfo(), 'GetInstallManagerInfo');
  return { apps: (i.rgApps || []).map((x) => x.nAppID), state: i.eInstallState, needed: Number(i.nDiskSpaceRequired || 0), free: Number(i.nDiskSpaceAvailable || 0),
           folder: i.iInstallFolder, error: i.eAppError || 0, error_detail: i.errorDetail || '' }; };

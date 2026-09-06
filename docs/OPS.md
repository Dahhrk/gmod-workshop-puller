# Workshop Puller ops

## Need on the host

- [SteamCMD](https://developer.valvesoftware.com/wiki/SteamCMD)
- `gmad` from a Garry's Mod client install (`bin/gmad.exe` or `bin/win64/gmad.exe`)
- Write access to the server `garrysmod/addons` folder
- A public Workshop collection, or a text file of numeric IDs

Optional: `STEAM_WEB_API_KEY` for titles. Collection children resolve without a key on public collections.

## First pull

```powershell
powershell -File puller/workshop-puller.ps1 `
  -CollectionId 123456789 `
  -Dest "C:\path\to\garrysmod\addons"
```

Or:

```powershell
powershell -File puller/workshop-puller.ps1 `
  -IdsFile .\local\ids.txt `
  -Dest "C:\path\to\garrysmod\addons"
```

`-SteamCmd` and `-Gmad` override discovery. `-CacheDir` defaults to `cache/` in this repo. `-DryRun` lists IDs only.

## After a timeout

Re-run the same command. `already` means `addons/ws_<id>/` exists. Failed IDs stay `timeout` or `missing`. SteamCMD still fails on some items ([Physgun, Dec 2025](https://physgun.com/help/game-hosting/gmod/how-to-fix-workshop-download-failed-timed-out/)). This script names them. It does not invent a second Steam.

## Do not

- Drop a `.gma` in `addons/` root
- FastDL files that are already Workshop IDs (downloadables table is 4096)
- Commit `local/`, `cache/`, or `.env`
- Point `-Dest` at this repo

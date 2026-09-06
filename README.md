# Workshop Puller

A **host script** for Garry's Mod dedicated-server owners. SteamCMD times out. This names the Workshop IDs that failed, downloads the ones that can, and extracts them into `addons/ws_<id>/`.

It is not an addon. It does not run inside the game. Players never see it.

## Who it is for

Owners whose boot log says `Download Failed! Timed Out` or `Staging library folder not found`.

Staff who are about to spend an hour in Crowbar.

## Install

Clone this folder onto the box that can write `garrysmod/addons`. Install [SteamCMD](https://developer.valvesoftware.com/wiki/SteamCMD). Keep a Garry's Mod client nearby so `gmad` exists.

```powershell
powershell -File puller/workshop-puller.ps1 -CollectionId YOUR_COLLECTION_ID -Dest "C:\srcds\garrysmod\addons"
```

See [docs/OPS.md](docs/OPS.md).

## What you get

| Status | Meaning |
|---|---|
| `ok` | Downloaded and extracted to `addons/ws_<id>/` |
| `already` | That folder was already there |
| `timeout` | SteamCMD did not finish |
| `missing` | SteamCMD exited, no GMA on disk |
| `extract_fail` | GMA landed, `gmad` failed |
| `skipped` | Dry run, or the ID was not numeric |

## Limits

- The engine downloadables table is **4096**. FastDL plus `AddWorkshop` share it. This script does not raise that cap.
- Loose `.gma` files in `addons/` are ignored. We extract to a unique folder.
- Linux Workshop RAM still wants a `srcds` restart after a big pull.
- Join Clinic is a different repo. This is boot. That is the player join.

## Factory

On the author machine: `pstack` + `cursor-team-kit` via `.cursor/settings.json`. Project skills only `workshop-puller` and `verify-workshop-puller`. Do not vendor the home skill library.

```powershell
powershell -File tools/control-workshoppuller.ps1 doctor
powershell -File tools/control-workshoppuller.ps1 fail-smoke
```

`pull-proof` needs a real SteamCMD run and `local/PULL_PROOF.md`.

## License

MIT. See [LICENSE](LICENSE).

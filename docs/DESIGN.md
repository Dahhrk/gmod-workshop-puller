# Workshop Puller design

## Caller

A dedicated server boots. SteamCMD times out on half the collection. Physgun tells the owner to Crowbar each ID by hand. They need one report: which Workshop IDs landed in `addons/`, and which still failed.

This is a host script. It is not a GMod addon. It does not run inside `srcds`.

## Domain

One report per pull. Not a live stream.

```
CollectionItem
  id: string          -- Workshop file ID
  title: string|nil

PullResult
  item: CollectionItem
  status: "ok" | "already" | "timeout" | "missing" | "extract_fail" | "skipped"
  detail: string
  dest: string|nil    -- folder under addons/

PullReport
  collection: string|nil
  dest: string
  started: string     -- UTC
  finished: string
  results: PullResult[]
  counts: { ok: number, bad: number, already: number }
```

`PullReport` is the only persisted shape. Written to `local/last-pull.json` (gitignored). Older pulls are discarded.

Unknown `status` is an error. Do not swallow it.

## Shapes compared

**SteamCMD plus gmad (chosen).** `+workshop_download_item 4000 <id>`, then `gmad extract` into `addons/ws_<id>/`. Unique folder names. Loose `.gma` in `addons/` root is ignored by the engine ([issue 6644](https://github.com/Facepunch/garrysmod-issues/issues/6644)).

**HTTP CDN scrape (rejected).** Breaks when Steam changes the workshop job path. No hash check you can trust. Not what `srcds` already uses.

## Surfaces

```
powershell -File puller/workshop-puller.ps1 -CollectionId <id> -Dest <garrysmod/addons>
powershell -File puller/workshop-puller.ps1 -IdsFile ids.txt -Dest <garrysmod/addons>
```

Prints ticket text. Writes `local/last-pull.json`.

## Out of scope

Join Clinic. Box clinic. Error clinic. A Lua addon. A content CDN. Raising the 4096 downloadables table.

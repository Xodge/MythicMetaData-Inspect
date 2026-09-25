# Mythic Meta Data - Inspect

A companion addon to [Mythic Meta Data](https://www.curseforge.com/wow/addons/mythic-meta-data) that captures Mythic+ history when you inspect a group or raid member, and merges it into a single window alongside MMD's guild-tracked data.

## Requirements

- **Mythic Meta Data** must be installed (required dependency)
- Every member you inspect must be in your current party or raid — Blizzard's inspect action requires proximity or group membership

## What it does

- Captures a player's season score and per-dungeon completed levels the moment you inspect them
- Merges inspected data with MMD's guild-tracked data in a single window — tracked entries always take priority over inspected ones
- Labels inspected entries clearly so the two data sources are never confused
- Lets you hold entries you want to keep, or purge stale ones on demand

## Commands

| Command | Effect |
|---|---|
| `/mmdi show` | Open / close the merged window |
| `/mmdi scan` | Capture all current group/raid members at once |
| `/mmdi review` | Open the purge review window (hold entries to keep) |
| `/mmdi purge` | Remove all entries eligible for purge (older than 4 hours, not held) |
| `/mmdi test` | Capture your own character to verify the pipeline works |
| `/mmdi dump [unit]` | Print the raw API response for a unit (default: target) |

## Notes

- Data is local only — never synced, never written into MMD's guild data
- Inspected entries are eligible for purge 4 hours after capture; a hold via `/mmdi review` extends that by 24 hours
- Everything shuts down immediately on combat start — this tool is for between pulls, never mid-fight

## Installation

Drop the `MythicMetaData-Inspect` folder into `World of Warcraft\_retail_\Interface\AddOns\`. Mythic Meta Data must also be installed.

## License

MIT License

## Thanks

Seronja-Azgalor — testing

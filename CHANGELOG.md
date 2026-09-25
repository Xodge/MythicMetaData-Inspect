# Changelog

## 1.0.0
- Initial release
- Passive capture via Inspect hook (fires the moment you inspect a group/raid member)
- Active capture via /mmdi scan (loops all current party/raid members)
- Merges inspected data with MMD's guild-tracked data in a single window; tracked entries always take priority
- Context labeling: Group, M+, or Raid — inferred at capture, automatically relabeled as the group situation changes
- Purge review window (/mmdi review) with per-entry hold checkboxes
- Hard combat lockout on all UI and capture paths
- Thanks to Seronja-Azgalor for testing assistance

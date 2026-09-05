# Changelog

## Unreleased

- Added the initial portable project structure.
- Added safe inspection mode and method comparison.
- Added shared JSON settings with RU/EN interface selection.
- Added separate package, backup, log, manifest, and documentation directories.
- Implemented read-only game inspection with PE architecture detection, DLSS/proxy hints, and timestamped JSON manifests.
- Implemented local package inventory with SHA-256 hashes.
- Implemented verified ZIP installation, per-file hash checks, point backups, restore, and optional elevation.
- Added Bootstrap preparation from locked sources, including automatic 7zr extraction of multipart DLSS5-AIO archives.
- Renamed the Bootstrap menu item to Automatic installation.
- Restore now lets the user choose the game and installation manifest to revert.
- Documented custom package and alternate-version installation through local manifests.
- Added universal 0 cancellation at interactive prompts; cancelled operations return to the main menu without installing files.
- Added menu item 8 for a clean exit and a standard Windows folder picker for game paths.
- Added Simple and Advanced interface modes for inspection output; menu item 9 now exits the utility.

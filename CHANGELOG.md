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

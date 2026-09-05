# DLSS5 Universal Installer guide

This document covers the portable tool itself. The root [README](../README.md) is the short project overview; the linked guides below contain the detailed rules and procedures.

## Start here

Run `DLSS5-Universal.cmd` and choose **Automatic installation**. The wizard asks for a game folder, filters common technical executables, lets you select the real game EXE, compares the three methods, downloads pinned sources, verifies SHA-256, creates a point backup, and installs the selected package.

Use `0` at any interactive prompt to cancel the current operation and return to the main menu. Use **Settings** to change language, interface mode, automatic-download policy, or the elevation warning. Use **Exit** to close the utility.

## Read-only inspection

`Check` does not download, replace, or delete files. It reports executable candidates, PE architecture, API hints, native DLSS filenames, and common proxy DLLs. Simple mode shows a compact summary; Advanced mode prints the complete JSON inspection report.

## Command-line actions

```powershell
src\installer.ps1 -Action Check -GamePath "C:\Games\MyGame"
src\installer.ps1 -Action Packages
src\installer.ps1 -Action Download -SourceId "optiscaler"
src\installer.ps1 -Action Bootstrap
src\installer.ps1 -Action Install -GamePath "C:\Games\MyGame" -PackageManifest "packages\method.manifest.json"
src\installer.ps1 -Action Restore
```

`Download` retrieves one locked source. GitHub URLs are generated from the pinned repository, tag, and asset filename in `config/sources.lock.json`; other sources keep a fixed `downloadUrl`. `Bootstrap` performs the complete automatic flow. `Install` works with a package manifest, including a custom version. `Restore` lists previous installation manifests and lets you choose which game to revert.

## Profiles

- **Native/Bridge** — for games with native DLSS;
- **OptiScaler** — for a supported upscaler proxy path;
- **ReShade + Feeder** — for games without native DLSS when depth and motion data are available.

The methods are alternatives. Restore the selected installation before switching methods.

## Custom packages

Place a custom archive in `packages/` and create a manifest with its exact source, archive SHA-256, and SHA-256 for each destination file. The installer will verify the manifest and create a point backup before copying files. It does not download arbitrary URLs automatically or remove files absent from the manifest.

## Settings and local data

Tracked defaults are stored in `config/settings.json`. Personal changes are written to the ignored `config/settings.local.json`; delete that file to return to the repository defaults.

Runtime downloads, staging files, backups, generated manifests, logs, and personal test plans are ignored by Git. The installer never creates a full game backup.

## Public guides

- [In-game verification](IN-GAME-VERIFICATION.md) — repeatable visual, FPS, stability, and rollback checks;
- [Components and sources](COMPONENTS.md) — pinned versions, official upstream releases, and file groups;
- [Compatibility matrix](COMPATIBILITY.md) — supported APIs, methods, and current boundaries;
- [Troubleshooting](TROUBLESHOOTING.md) — recovery steps and diagnostic collection;
- [Package manifest](PACKAGE-MANIFEST.md) — manifest format for custom packages;
- [Safety](SAFETY.md) — download, backup, elevation, and anti-cheat boundaries;
- [Testing](TESTING.md) — generic validation procedure;
- [Implementation plan](PLAN.md) — current project scope and completed work;
- [Project TODO](TODO.md) — global backlog and explicit non-goals.

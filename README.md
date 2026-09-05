# DLSS5 Universal Installer

A portable Windows utility for installing and switching community DLSS5 integration methods in supported games.

It is designed for a simple workflow: choose a game, inspect the executable candidates, select a method, download pinned upstream releases, verify SHA-256 hashes, install only the declared files, and keep a point backup for restore.

> This project is an installer and verification layer. It does not claim that every game, renderer, or DLSS5 method is compatible.

## What it supports

- Windows 10/11 x64;
- DirectX 11 and DirectX 12 targets;
- games with native DLSS through **Native/Bridge**;
- games that need an upscaler interception layer through **OptiScaler**;
- games without native DLSS through **ReShade + Feeder**;
- automatic downloads from pinned HTTPS release assets;
- SHA-256 verification for downloaded archives and staged files;
- point backups and manifest-based restore;
- English and Russian interactive UI;
- Simple and Advanced inspection output.

The first release targets 64-bit games. 32-bit support depends on a method providing a compatible x86 or host component and is not assumed automatically.

## Quick start

1. Download or clone the repository.
2. Run `DLSS5-Universal.cmd`.
3. Select **Automatic installation**.
4. Enter the game path or type `1` to open the Windows folder picker.
5. Review the executable candidates and select the real game executable.
6. Choose Native/Bridge, OptiScaler, or ReShade + Feeder.
7. Review the package and confirm installation.
8. Launch the game and verify image quality, stability, and performance.

The default repository profile is English with the Simple interface. Personal preferences are stored in the ignored `config/settings.local.json` file.

At any interactive prompt, enter `0` to cancel the current operation and return to the main menu. Choose **Exit** to close the utility.

## Installation methods

| Method | Use when | Trade-off |
|---|---|---|
| Native/Bridge | The game already contains native DLSS | Usually the lowest overhead; requires a working native DLSS path |
| OptiScaler | Native/Bridge is unavailable or unsuitable | Broad compatibility; proxy DLL conflicts are possible |
| ReShade + Feeder | The game has no native DLSS path | Most universal route; depends on depth/motion vectors and usually costs more FPS |

The installer does not treat these methods as compatible at the same time. Restore the selected installation before switching methods.

## Automatic installation

The Bootstrap flow uses the locked entries in `config/sources.lock.json`. It can download the required release assets, verify their SHA-256 values, prepare multipart DLSS5-AIO archives, install ReShade when required, and install the selected package manifest.

Automatic downloads are enabled by default for these pinned sources. The installer rejects non-HTTPS sources and entries without a 64-character SHA-256. A hash confirms file identity; it does not prove that third-party code is safe.

## Custom packages and versions

To install a different version or a package that is not part of Bootstrap:

1. Place the archive in `packages/`.
2. Create a package manifest with the exact source, archive SHA-256, and SHA-256 for every destination file.
3. Choose **Install a custom local package**, or run `-Action Install` with that manifest.

The tool does not download arbitrary URLs automatically and does not delete files that are absent from a package manifest.

## Restore

Choose **Restore a selected installation** to see the recorded game paths, package versions, and installation manifests. Select the entry to revert. Only files recorded by that installation are restored or removed; the utility never creates a full game backup.

## Command-line actions

```powershell
src\installer.ps1 -Action Check -GamePath "C:\Games\MyGame"
src\installer.ps1 -Action Packages
src\installer.ps1 -Action Download -SourceId "optiscaler"
src\installer.ps1 -Action Bootstrap
src\installer.ps1 -Action Install -GamePath "C:\Games\MyGame" -PackageManifest "packages\method.manifest.json"
src\installer.ps1 -Action Restore
```

`Check` is read-only. It reports executable candidates, architecture, API hints, native DLSS files, and possible proxy files. `Advanced` mode prints the complete JSON inspection report.

## Safety and scope

- Point backups are created before replacing existing files.
- Unknown existing DLLs are not removed automatically.
- Administrator elevation shows a warning first.
- Online games with anti-cheat are outside the intended scope.
- ReShade is the only third-party installer launched automatically, and only from the pinned source used by Bootstrap.
- Packages and sources should come from the project author or official upstream releases.

## Repository layout

- `src/` — PowerShell implementation;
- `DLSS5-Universal.cmd` — Windows launcher;
- `config/` — tracked defaults and source policy;
- `config/settings.local.json` — ignored personal overrides;
- `packages/` — package archives and manifests;
- `downloads/` — downloaded source assets, ignored by Git;
- `staging/` — temporary extraction area, ignored by Git;
- `backups/` — point backups, ignored by Git;
- `manifests/` — generated inspection and installation records, ignored by Git;
- `local-tests/` — personal game test plans and results, ignored by Git;
- `docs/` — public operating and safety documentation.

See [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md), [docs/README.md](docs/README.md), and [LICENSE](LICENSE).







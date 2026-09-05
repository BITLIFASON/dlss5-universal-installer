# DLSS5 Universal Installer

Portable utility for Windows 10/11 x64. The first release targets DX11 and DX12 games. 32-bit games are supported only when the selected method provides a separate x86 or host component.

Run `DLSS5-Universal.cmd`.

The `Check` mode is read-only: it does not download, replace, or delete files. Before installation it reports the detected API, native DLSS files, and possible conflicts.

Available command-line actions:

- `src\installer.ps1 -Action Check -GamePath "C:\\Games\\MyGame"` — inspect the game and write a JSON manifest;
- `src\installer.ps1 -Action Packages` — list local archives/DLLs and their SHA-256 values;
- `src\installer.ps1 -Action Download -SourceId "optiscaler"` — download only a locked HTTPS release after `allowAutomaticDownloads` is enabled and SHA-256 is verified;
- `src\installer.ps1 -Action Bootstrap` — choose a game and method, download locked sources, verify SHA-256, prepare AIO assets, install ReShade when required, and install the selected package;
- `src\installer.ps1 -Action Install -GamePath "C:\\Games\\MyGame" -PackageManifest "packages\\method.manifest.json"` — verify, back up, and install the listed files;
- `src\installer.ps1 -Action Restore` — restore the latest installation from its manifest.

Sources are pinned in `config/sources.lock.json`. `latest` URLs, search links, and entries without SHA-256 are rejected.

Profiles:

- Native/Bridge — for games with native DLSS;
- OptiScaler — a separate upscaler interceptor;
- ReShade + Feeder — a route for games without native DLSS.

Only the specific files being changed are backed up. A full game copy is never created.

Shared settings are in `config/settings.json`: language, supported APIs, mandatory method comparison, elevation warning, local package preference, and the rule against deleting unknown files.

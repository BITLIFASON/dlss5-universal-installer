# DLSS5 Universal Installer

Portable utility for Windows 10/11 x64. The first release targets DX11 and DX12 games. 32-bit games are supported only when the selected method provides a separate x86 or host component.

Run `DLSS5-Universal.cmd`.

The `Check` mode is read-only: it does not download, replace, or delete files. Before installation it reports the detected API, native DLSS files, and possible conflicts.

Available command-line actions:

- `src\installer.ps1 -Action Check -GamePath "C:\\Games\\MyGame"` — inspect the game and write a JSON manifest;
- `src\installer.ps1 -Action Packages` — list local archives/DLLs and their SHA-256 values;
- `src\installer.ps1 -Action Download -SourceId "optiscaler"` — download only a locked HTTPS release with SHA-256 verification; the setting is enabled by default for locked sources;
- `src\installer.ps1 -Action Bootstrap` — choose a game and method, download locked sources, verify SHA-256, prepare AIO assets, install ReShade when required, and install the selected package;
- `src\installer.ps1 -Action Install -GamePath "C:\\Games\\MyGame" -PackageManifest "packages\\method.manifest.json"` — verify, back up, and install the listed files;
- `src\installer.ps1 -Action Restore` — choose an installation manifest and restore that game;

Sources are pinned in `config/sources.lock.json`. `latest` URLs, search links, and entries without SHA-256 are rejected.

Profiles:

- Native/Bridge — for games with native DLSS;
- OptiScaler — a separate upscaler interceptor;
- ReShade + Feeder — a route for games without native DLSS.

Only the specific files being changed are backed up. A full game copy is never created.

### Custom versions and packages

The automatic Bootstrap flow uses only the pinned versions in `config/sources.lock.json`. To install another version or an unlisted package, place the archive in `packages/` and create a package manifest that records its exact source, archive SHA-256, and every destination file SHA-256. Then choose **Install a custom local package** in the menu or run `-Action Install` with that manifest. The installer verifies the manifest and creates a point backup before changing the game; it does not download arbitrary URLs automatically.

Shared settings are in `config/settings.json`: language, supported APIs, mandatory method comparison, elevation warning, local package preference, and the rule against deleting unknown files.

At any interactive prompt, enter 0 to cancel the current operation and return to the main menu. The command-line actions remain non-interactive when all required parameters are supplied.



In the menu, choose **8 — Exit** to close the utility. For any game-folder prompt, enter 1 to open the standard Windows folder picker, or enter the path manually.

The interface mode can be changed from menu item 8. Simple mode shows a compact inspection summary; Advanced mode prints the complete JSON inspection report. Menu item 9 exits the utility.

Before installation, the tool scores executable candidates and filters common Unreal/Unity technical processes such as editor, crash reporter, shader compiler, subprocess, and server binaries. It still asks you to choose the target EXE when multiple candidates remain.

The main menu keeps user preferences under **Settings**. This submenu contains language, interface mode, automatic-download policy, and the elevation warning toggle. The main menu has a separate **Exit** item.


Personal preferences are stored in the ignored `config/settings.local.json` file. The tracked `config/settings.json` remains the English default template, so changing options from the Settings menu does not create a Git diff. Delete the local file to return to repository defaults.

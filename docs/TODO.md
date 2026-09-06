# Project TODO

This is the global backlog for the portable installer. Completed work belongs in `CHANGELOG.md`; current scope and milestones belong in `PLAN.md`.

## High priority

- [ ] Improve game-folder selection with configurable roots: keep a list of user-defined library roots (for example `C:\Games`, Steam, Epic, and GOG), let the user choose one default root in **Settings**, and add a selection mode that either asks for a game-folder name relative to that root (with Tab completion where the console supports it) or always opens Explorer. Show the saved roots and recent game profiles before manual browsing, validate the resulting folder before inspection, and keep Explorer as a fallback.
- [ ] Add 32-bit package variants and architecture-aware ReShade/add-on selection for legacy games; the current Feeder manifest is x64-only.
- [ ] Implement the no-DLSS synthetic Bridge route as an explicit opt-in: set `synth=1`, require the runtime DLL beside the executable, and show the expected quality/performance warning.
- [ ] Add a preflight GPU check and warning for DLSS5 Neural Rendering's RTX 40/50 requirement.
- [ ] Add per-game method profiles with clear warnings for failed combinations and tested recovery paths.

- [ ] Replace raw EXE string matching with a layered PE scan: normal imports, delay-load imports, API entry-point markers, and matching engine DLLs.
- [ ] Limit game inspection to relevant executable/DLL files, cap scan depth, and skip asset, cache, backup, redist, and tool directories.
- [ ] Detect ReShade hooks by file version/signature and report whether add-on support is present before installing another runtime.
- [ ] Show the active installation state during inspection: method, package version, target executable, and installed-file hash status.
- [ ] Improve Restore record selection: sort by recorded installation time (newest first), display a readable local timestamp, group records by game path, and clearly mark the latest active candidate and synthetic/local test records.
- [ ] Add a safe dry-run command that never asks for elevation and writes no game files.
- [ ] Add a dedicated `Restore`/uninstall summary showing every file that will be restored or removed before confirmation.
- [ ] Add automated Windows PowerShell parser and JSON validation checks for pull requests.
- [ ] Validate the ReShade headless command line against the pinned installer version on a disposable test game.
- [ ] Add a clean synthetic test for first install, repeated install, failed install rollback, and restore conflict handling.

## Medium priority

- [ ] Detect more upscaler variants and engine-specific paths without treating filename matches as proof of compatibility.
- [ ] Add optional Steam, Epic, and GOG library discovery while keeping manual folder selection available.
- [ ] Add per-game compatibility notes and known workarounds as separate, reviewable profiles.
- [ ] Add package-level file indexes and a human-readable SHA-256 report.
- [ ] Add an optional post-install launch command for games that require a launcher instead of starting the EXE directly.
- [ ] Improve progress reporting with download speed, elapsed time, and retry status.

## Compatibility backlog

- [ ] Define and test a supported x86 Feeder workflow.
- [ ] Investigate Vulkan support and document the required ReShade/API path before exposing it in the menu.
- [ ] Investigate DirectX 9 support only after a confirmed bridge or host process is available.
- [ ] Add GPU and driver diagnostics as advisory checks, never as unsupported hard blocks without evidence.
- [ ] Add conflict detection for other injectors, including multiple proxy DLLs and NVIDIA Smooth Motion.
- [ ] Detect renderer choices exposed by separate game executables and offer the matching API as an explicit selection.

## UX backlog (GUI remains optional)

- [ ] Handle invalid interactive input consistently: show a short error, keep the user on the current prompt, and retry until a valid option, `0`, `Esc`, or `q` is entered; apply this to yes/no prompts and localized keyboard-layout mistakes as well.
- [ ] Add a searchable advanced report view if a GUI is introduced later.
- [ ] Add a language-neutral event log so translations do not change diagnostic meaning.
- [ ] Add a clear `Back` action to multi-step flows where returning to the menu is not enough.

## Release and maintenance

- [ ] Add a documented release checklist with source URL, exact tag, asset name, SHA-256, license, and compatibility notes.
- [ ] Add a dependency update procedure that never replaces a pinned component without review.
- [ ] Add repository branch protection and required validation checks to the contribution guide.
- [ ] Review package licenses and redistribution permissions before publishing release artifacts.
- [ ] Add a file-version and architecture report for every detected DLSS, Streamline, ReShade, and add-on binary.

## Explicit non-goals for now

- Full game backups.
- Bundling proprietary NVIDIA binaries in Git.
- Automatic installation into online games with anti-cheat.
- Silent removal of files that are not recorded in an installation manifest.
- GUI work before the command-line workflow is stable and repeatably tested.
# Method routing

- [ ] Add an explicit opt-in for the no-DLSS synthetic Bridge route (`synth=1`) with a clear quality and compatibility warning.
- [ ] Add a read-only post-install log check that confirms the expected add-on was loaded and warns when the selected game exposes a different rendering path.

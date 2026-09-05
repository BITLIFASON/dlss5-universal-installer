# Project TODO

This is the global backlog for the portable installer. Completed work belongs in `CHANGELOG.md`; current scope and milestones belong in `PLAN.md`.

## High priority

- [ ] Add a safe dry-run command that never asks for elevation and writes no game files.
- [ ] Add explicit install-state reporting: package, version, selected executable, and whether files match the recorded hashes.
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

## UX backlog (GUI remains optional)

- [ ] Add a searchable advanced report view if a GUI is introduced later.
- [ ] Add a language-neutral event log so translations do not change diagnostic meaning.
- [ ] Add a clear `Back` action to multi-step flows where returning to the menu is not enough.

## Release and maintenance

- [ ] Add a documented release checklist with source URL, exact tag, asset name, SHA-256, license, and compatibility notes.
- [ ] Add a dependency update procedure that never replaces a pinned component without review.
- [ ] Add repository branch protection and required validation checks to the contribution guide.
- [ ] Review package licenses and redistribution permissions before publishing release artifacts.

## Explicit non-goals for now

- Full game backups.
- Bundling proprietary NVIDIA binaries in Git.
- Automatic installation into online games with anti-cheat.
- Silent removal of files that are not recorded in an installation manifest.
- GUI work before the command-line workflow is stable and repeatably tested.

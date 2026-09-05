# DLSS5 Universal Installer

Unofficial portable installer framework for community DLSS 5 integrations on Windows games.

The first release targets Windows 10/11 x64 and DX11/DX12 games. It compares Native/Bridge, OptiScaler, and ReShade + Feeder routes before installation, uses local packages first, and keeps point backups with manifests.

This project does not distribute proprietary NVIDIA binaries. Place independently obtained, verified packages in `packages/` and review `config/sources.json` before use.

Run `DLSS5-Universal.cmd` to start the tool.

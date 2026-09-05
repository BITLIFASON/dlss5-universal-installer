# Components and sources

This index lists the components used by the installer and the exact upstream release selected for the current lockfile. Downloaded binaries are not committed to Git; the installer stores them in `downloads/` and verifies their SHA-256 before use.

| Component | Installed or prepared files | Version | Official source |
|---|---|---:|---|
| ReShade Add-on Support | ReShade runtime installed for the selected game executable | 6.8.0 | [ReShade](https://reshade.me/) · [pinned asset](https://reshade.me/downloads/ReShade_Setup_6.8.0_Addon.exe) |
| DLSS5 Bridge | `dlss5-bridge.addon64` | 1.4.12 | [NIGos/dlss5-bridge release](https://github.com/NIGos/dlss5-bridge/releases/tag/v1.4.12) |
| OptiScaler | `dxgi.dll`, `OptiScaler.ini`, proxy/runtime DLLs declared in the manifest | 0.9.4 | [OptiScaler release](https://github.com/optiscaler/OptiScaler/releases/tag/v0.9.4) |
| DLSS5 Feeder | `dlss5-feed.addon64`, `DLSS5_Feed.fx`, `renodx-dlss5.addon64`, `nvngx_dlssnr.dll`, `nvngx_dlss.dll`, and the declared ReShade shader assets | 1.2.5 | [ShugokiFable/dlss5-aio release](https://github.com/ShugokiFable/dlss5-aio/releases/tag/v1.2.5) |
| 7-Zip command-line extractor | `7zr.exe` used to prepare multipart AIO archives | 26.03 | [7-Zip upstream release](https://github.com/ip7z/7zip/releases/tag/26.03) |

## Package manifests

The installable file lists and per-file hashes are kept in the repository:

- [`packages/dlss5-bridge.manifest.json`](../packages/dlss5-bridge.manifest.json) — Native/Bridge;
- [`packages/optiscaler.manifest.json`](../packages/optiscaler.manifest.json) — OptiScaler;
- [`packages/dlss5-feeder.manifest.json`](../packages/dlss5-feeder.manifest.json) — ReShade + Feeder.

The locked download metadata, versions, licenses, and archive SHA-256 values are recorded in [`config/sources.lock.json`](../config/sources.lock.json). GitHub assets use an exact repository, tag, and filename; the installer derives the release download URL from those fields. A matching hash confirms that the downloaded bytes equal the locked asset; it is not a safety certification.

The installer does not ship proprietary NVIDIA binaries or redistribute the downloaded archives through Git. It retrieves the pinned upstream assets when the selected flow requires them.

# Local packages

Installation is allowed only for a package already present in `packages` and described by a verifiable manifest. Minimal example:

```json
{
  "id": "example-method",
  "version": "1.0.0",
  "method": "OptiBridge",
  "archive": "example-method.zip",
  "installRelativeTo": "primaryExecutableDirectory",
  "sha256": "<archive sha256>",
  "source": "https://official-source/release",
  "files": [
    { "path": "version.dll", "sourcePath": "OptiScaler\\OptiScaler.dll", "sha256": "<extracted file sha256>" },
    { "path": "nvngx_dlssnr.dll", "sourcePath": "DLSS5-AIO\\02-DLSS5-Neural-Rendering\\nvngx_dlssnr.dll", "sha256": "<extracted file sha256>" },
    { "path": "renodx-dlss5.addon64", "sourcePath": "DLSS5-AIO\\02-DLSS5-Neural-Rendering\\renodx-dlss5.addon64", "sha256": "<extracted file sha256>" }
  ]
}
```

`path` is the destination path inside the game folder. Optional `sourcePath` is the file path inside the prepared source; this makes an explicit mapping such as `OptiScaler.dll` to `version.dll` auditable.

Optional `installWhenApi` limits an entry to the selected renderer (`dxgi`, `d3d11`, `d3d12`, or `vulkan`). Use this when a native DX12 path must not receive a DX11/Vulkan bridge. `sourceFromGame` marks a file that is selected from the game's own files; the installer still verifies the staged bytes and records the point backup before copying it beside the executable.

`source` records provenance for auditing. A public archive alone is not proof of safety. Until a manifest exists, the tool can only inventory and hash a package; it cannot install it.

Automatic downloads use the separate `config/sources.lock.json` file. A GitHub source contains an exact repository, tag, asset filename, and expected SHA-256; non-GitHub sources use a fixed HTTPS `downloadUrl`. `allowAutomaticDownloads` is enabled for the pinned sources by default, while every download still requires HTTPS and a matching SHA-256.

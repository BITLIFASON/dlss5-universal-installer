# Local packages

Installation is allowed only for a package already present in `packages` and described by a verifiable manifest. Minimal example:

```json
{
  "id": "example-method",
  "version": "1.0.0",
  "method": "OptiScaler",
  "archive": "example-method.zip",
  "installRelativeTo": "primaryExecutableDirectory",
  "sha256": "<archive sha256>",
  "source": "https://official-source/release",
  "files": [
    { "path": "dxgi.dll", "sourcePath": "OptiScaler.dll", "sha256": "<extracted file sha256>" }
  ]
}
```

`path` is the destination path inside the game folder. Optional `sourcePath` is the file path inside the archive; this makes an explicit mapping such as `OptiScaler.dll` to `dxgi.dll` auditable.

`source` records provenance for auditing. A public archive alone is not proof of safety. Until a manifest exists, the tool can only inventory and hash a package; it cannot install it.

Automatic downloads use the separate `config/sources.lock.json` file. A GitHub source contains an exact repository, tag, asset filename, and expected SHA-256; non-GitHub sources use a fixed HTTPS `downloadUrl`. `allowAutomaticDownloads` is enabled for the pinned sources by default, while every download still requires HTTPS and a matching SHA-256.

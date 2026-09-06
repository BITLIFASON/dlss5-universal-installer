# Troubleshooting

Use this order when a setup does not behave as expected.

## The game was already modified by another installer

Stop and return to a clean game directory before comparing methods. Remove or restore the previous mod manager profile, ReShade hook, OptiScaler proxy, frame-generation wrapper, and manual DLL changes using that tool's documented procedure. The installer can warn about common conflicts, but it cannot reconstruct unknown files or guarantee a complete rollback of changes made before its own manifest and point backup existed.

## The wrong executable was detected

Run `Check` again and inspect the executable candidates. During installation, choose the real game executable, usually the large `*-Shipping.exe` inside a `Binaries\Win64` directory for Unreal Engine games. Do not select editor, crash reporter, shader compiler, launcher, or server binaries.

## The game does not start after installation

1. Close the game and launcher.
2. Run the utility and choose **Restore a selected installation**.
3. Select the matching game path and package version.
4. If the game has several tracked installation layers, choose **full restore** to return to the state before the first tracked layer.
5. Confirm that the game starts without the package.
6. Check for another proxy DLL or injector in the game directory before trying a different method.

The utility restores only files recorded by its installation manifest. It does not delete unrelated files.

## The image is unchanged

- Confirm that the selected method matches the game's native upscaler path.
- For ReShade + Feeder, confirm that the ReShade add-on runtime was installed for the selected executable.
- Check the generated logs and the ReShade overlay when applicable.
- Compare the same scene before and after installation without changing frame-generation settings.

## The installation stops before copying files

Common causes are a missing package archive, a manifest mismatch, or a SHA-256 mismatch. Run **Inventory packages and SHA-256** and compare the result with `config/sources.lock.json` and the selected package manifest. Delete an incomplete download and run the locked download again.

## Windows requests administrator rights

The game folder may not be writable by the current process. The utility shows a warning before elevation. Accept it only when the selected game path and package are correct.

## ReShade installation fails

If the game already has ReShade or a proxy DLL, the wizard offers three choices: reinstall over it, remove the detected hook, configuration, and known DLSS5 add-on files, or cancel. Before removal it asks whether the installation came from this utility. If a matching manifest exists, removal is refused and you are directed to **Restore**. If the manifest is missing, the tool warns that old backup folders may be incomplete. Before removal, it creates a point snapshot and adds it to **Restore**. That snapshot can restore the manual components, but it cannot recover original game files that were overwritten before the snapshot. The `reshade-shaders` folder, unknown DLLs, and `nvngx_dlss.dll` are left untouched. Confirm that the selected executable is the actual game process and that the pinned ReShade Add-on installer was downloaded successfully.

## How to collect useful diagnostics

Use **Advanced** interface mode, run `Check`, and keep the generated JSON inspection manifest together with the installer log. Record the game version, graphics API, selected executable, method, and whether the game launched. Do not upload proprietary game binaries, cookies, or personal settings.

## Last resort

If the game remains unstable, restore the selected installation, remove only the local package downloads if needed, and report the exact method, executable path, package version, and relevant log error in a GitHub issue.

## ReShade loads, but the image does not change

If `Home` opens but no DLSS5 effect is visible, check `ReShade.log` for `DLSS5_Feed.fx is not loaded` or search-path error `123`. The shader folders must be searched directly:

```ini
EffectSearchPaths=.\reshade-shaders\Shaders\
TextureSearchPaths=.\reshade-shaders\Textures\
```

The installer repairs these paths after its ReShade step. Restart the game, open `Home`, confirm that **DLSS 5 Feed** is listed, enable `DLSS5_Feed`, and save the preset. The effect must be below the selected motion-vector provider. An empty `ReShadePreset.ini` means that no effect is enabled yet; use `Home` once to select and save it.

A successful ReShade injection alone is not enough. Feeder also needs one motion-vector provider. The automatic Feeder profile installs the pinned LumeniteFX Kernel and creates a preset with `Lumenite_Kernel` above `DLSS5_Feed`. Do not treat the installation as working until both techniques are enabled and the log reports non-zero motion vectors.

The installer offers only two LumeniteFX providers: **Kernel** (`DLSS5_MV_PROVIDER=3`) and **QuantMotion** (`DLSS5_MV_PROVIDER=4`). Enable the selected Lumenite technique above `DLSS5_Feed`; do not enable both at once.

## OptiScaler reports a ReShade conflict

OptiScaler and ReShade both use proxy injection paths. Before an OptiScaler install, the wizard now offers to remove a detected ReShade hook and its known configuration files. It creates a point snapshot first and leaves the shader folder and unknown DLLs untouched. If the ReShade files belong to a tracked installation, restore that installation instead of deleting the hook. If the files are untracked, the wizard warns that original game DLLs overwritten before the snapshot cannot be recovered.

## Grey walls look soft or smear while the camera moves

This usually means that motion vectors are empty or disagree with the depth buffer on a flat surface. Confirm that the Feeder preset has these safeguards enabled:

```ini
GEOM_ENABLE=0
VALIDATE_LUMA=1
VALIDATE_DEPTH=1
VALIDATE_MV=1
VALIDATE_STATIC=1
STATIC_MIN_CONTRAST=0.02
```

The default profile keeps the experimental geometry fit disabled because it can introduce its own noise. Restart the game after changing the preset and test the same wall while rotating the camera. If the log still reports mostly zero motion vectors, capture the relevant `dlss5-feed.log` lines before changing the provider or stacking another upscaler.

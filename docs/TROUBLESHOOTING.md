# Troubleshooting

Use this order when a setup does not behave as expected.

## The wrong executable was detected

Run `Check` again and inspect the executable candidates. During installation, choose the real game executable, usually the large `*-Shipping.exe` inside a `Binaries\Win64` directory for Unreal Engine games. Do not select editor, crash reporter, shader compiler, launcher, or server binaries.

## The game does not start after installation

1. Close the game and launcher.
2. Run the utility and choose **Restore a selected installation**.
3. Select the matching game path and package version.
4. Confirm that the game starts without the package.
5. Check for another proxy DLL or injector in the game directory before trying a different method.

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

Confirm that the selected executable is the actual game process and that the pinned ReShade Add-on installer was downloaded successfully. If the game already has a ReShade installation, restore or review its files before installing another runtime.

## How to collect useful diagnostics

Use **Advanced** interface mode, run `Check`, and keep the generated JSON inspection manifest together with the installer log. Record the game version, graphics API, selected executable, method, and whether the game launched. Do not upload proprietary game binaries, cookies, or personal settings.

## Last resort

If the game remains unstable, restore the selected installation, remove only the local package downloads if needed, and report the exact method, executable path, package version, and relevant log error in a GitHub issue.

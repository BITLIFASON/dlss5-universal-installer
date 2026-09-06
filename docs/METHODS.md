# Methods

These methods are alternatives. Install and test one method at a time, and restore it before trying another one. The exact names in a game's graphics menu can differ.

## Native/Bridge

Use this when the game already ships with native DLSS. An additional bridge or add-on intercepts the existing call. It is usually the first performance candidate.

The bridge is only the bridge layer. A complete DLSS5 setup also needs the pinned `nvngx_dlssnr.dll` model and RenoDX add-on. The installer stages the bridge and the other required files automatically for the selected API; native DX12 keeps the game's own DLSS runtime and does not add a second bridge DLL.

After installation:

1. Start the game through its normal launcher.
2. In Graphics, select the game's **DLSS** upscaler. Start with Quality and keep dynamic resolution disabled.
3. Leave frame generation disabled for the first comparison. This separates the upscaler result from generated frames.
4. Load a save and wait for streaming and shaders to settle.
5. Capture the same view used for the baseline, then compare native/pre-generation FPS, frame time, image stability, and latency.
6. Enable frame generation only after the upscaler works reliably. Record native FPS and displayed FPS separately.

If the game has no DLSS option, Native/Bridge is the wrong first choice; restore it and use OptiScaler Bridge + DLSS5 or ReShade + Feeder when the game's buffers and API support them.

## OptiScaler Bridge + DLSS5

Routes an in-game FSR/XeSS upscaler call through OptiScaler into the DLSS5 neural-rendering add-on. This is a combined method; the installer does not offer standalone OptiScaler.

After installation:

1. Start the game and open Graphics. Select the game's **FSR** or **XeSS** upscaler. For a first test, use XeSS when the game supports it and FSR has a game-specific workaround; the bridge needs an FSR/XeSS input.
2. Start with the Quality preset, disable dynamic resolution, and keep frame generation disabled.
3. Load a save. OptiScaler's settings are often unavailable or incomplete in the main menu.
4. Open the OptiScaler overlay using its configured hotkey. Confirm that the input is FSR/XeSS and that the output is **DLSS**. Do not switch the output to FSR/XeSS; DLSS is the route that the DLSS5 add-on consumes.
5. Open the ReShade overlay with `Home`, then confirm that the DLSS5 neural-rendering add-on is enabled in the Add-ons/RenoDX panel.
6. Keep **FG Input** and **FG Output** set to `No Frame Generation` for the first pass. Test frame generation separately later.
7. Compare the same scene, then test a busy scene and a save/load transition. Watch for proxy conflicts, crashes, flicker, ghosting, and input latency.

For **Assetto Corsa Rally**, select **XeSS** for the first bridge test and restart the game after changing the upscaler. The Bridge profile disables FFX/FSR input hooks by default so the XeSS path is used; if the OptiScaler overlay says that FSR is active but not used, do not enable FFX inputs. The OptiScaler compatibility list notes that FSR 3.1 inputs require an additional `Engine.ini` command to prevent crashes; this installer does not add that game-specific tweak yet. The overlay can show that DLSS, FSR, and XeSS libraries exist; that status means the libraries are available, not that the game has already selected the correct input. The game upscaler selection still has to be made first.

## ReShade + Feeder

ReShade receives the image, depth buffer, and motion vectors; Feeder builds a DLAA contract for DLSS5. The automatic Feeder profile includes the pinned LumeniteFX Kernel provider and a preset with `Lumenite_Kernel` above `DLSS5_Feed`. This is the most universal route, but it usually costs more FPS and is more sensitive to the game.

After installation:

1. Start the game using its normal DX11/DX12 renderer. Keep the same resolution and quality preset as the baseline, disable dynamic resolution, and leave frame generation disabled initially.
2. Press `Home` to open ReShade. ReShade loading successfully is only the first check; the effects are not enabled automatically.
3. Enable **one** installed LumeniteFX provider: `LUMENITE: Kernel 2.0` **or** `LUMENITE: QuantMotion`.
4. Enable **DLSS 5 Feed** and place it below the selected LumeniteFX provider in the technique list.
5. If the preset exposes a neural-rendering toggle, enable it after the provider and Feed are active. Do not enable a second motion-vector provider.
6. Save the preset, load a repeatable save, and wait about 30 seconds. Check a still view and the same view while rotating the camera.
7. Compare native/pre-generation FPS and frame time first. Enable frame generation only after the image is stable.

If `Home` opens but the image does not change, check that both techniques are checked, the provider is above `DLSS 5 Feed`, and `ReShade.log` contains no shader-path or depth/motion-buffer errors.

In this repository, this is the complete DLSS5 path: the Feeder package includes the DLSS5 neural-rendering add-on and runtime, the Feed shader, and the LumeniteFX motion provider. Use this method when the goal is to test DLSS5 neural rendering rather than only replace the game's upscaler.

The installer never treats these methods as compatible at the same time. A separate manifest and point backup are created before switching.

## Upstream references

Read the upstream documentation when a game needs a renderer-specific workaround or when you want to inspect the component behavior directly:

- [NIGos/dlss5-bridge](https://github.com/NIGos/dlss5-bridge) — native DLSS bridge and DLSS5 add-on requirements;
- [OptiScaler](https://github.com/optiscaler/OptiScaler) and its [installation wiki](https://github.com/optiscaler/OptiScaler/wiki/Installation) — proxy names, ReShade sideloading, and game-specific configuration;
- [ShugokiFable/dlss5-aio](https://github.com/ShugokiFable/dlss5-aio) — bundled DLSS5 layouts and Feeder examples;
- [umar-afzaal/LumeniteFX](https://github.com/umar-afzaal/LumeniteFX) — motion-vector providers used by Feeder;
- [crosire/reshade](https://github.com/crosire/reshade) — ReShade core and add-on support.

The installer lockfile records the exact release and SHA-256 used by the automated flow; these links are documentation references and are not a substitute for the lockfile.

### NativeBridge runtime selection

For Unreal Engine games, the installer searches the game folder for a native `nvngx_dlss.dll`, prioritising the standard Marketplace path `Engine/Plugins/Marketplace/DLSS/Binaries/ThirdParty/Win64` and equivalent DLSS/Streamline plugin paths. It stages the detected runtime beside the selected executable only for the DX11/Vulkan Bridge route and installs `renodx-dlss5.addon64` with `nvngx_dlssnr.dll`. For native DX12, it installs RenoDX only and leaves the game's native runtime in its original location. For OptiBridge, ReShade is sideloaded as `ReShade64.dll` and OptiScaler loads it through `LoadReshade=true`. If the game has no native runtime, the pinned DLSS5-AIO runtime is used as a fallback. The nested engine copy is never overwritten.

The companion Streamline files under `Engine/Plugins/Marketplace/StreamlineCore/Binaries/ThirdParty/Win64` are game dependencies and are left untouched. They are not copied unless a package explicitly requires them.

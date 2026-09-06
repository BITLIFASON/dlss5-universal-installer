# In-game verification checklist

Use this short checklist after every installation.

OptiScaler Bridge + DLSS5 is a combined route. The game supplies FSR/XeSS input, OptiScaler routes it to DLSS, and the DLSS5 add-on consumes that DLSS call. Standalone OptiScaler is not offered by this installer.

## Before launching

- Keep the same resolution, graphics preset, ray tracing/path tracing settings, and display mode.
- Use the game's normal DX11/DX12 renderer and disable dynamic resolution or automatic quality while comparing results.
- Keep HDR disabled for an SDR display. Do not change DLSS mode, sharpening, motion blur, or frame generation between the baseline and the test.
- Use the same save and scene for before/after captures.
- If the game uses a launcher, start it through the normal launcher.
- Close overlays that can interfere with injection while diagnosing crashes.

## First launch

1. Open the game graphics settings and configure the selected method:
   - **Native/Bridge:** select the game's `DLSS` upscaler. Start with Quality, disable dynamic resolution, and leave frame generation off.
   - **OptiScaler Bridge + DLSS5:** select the game's `FSR` or `XeSS` input. Use `XeSS` first when the game's FSR input needs a workaround, restart after changing the upscaler, then load a save before opening the OptiScaler overlay. The Bridge profile disables FFX/FSR input hooks by default for the XeSS path. Leave `FG Input` and `FG Output` at `No Frame Generation` initially.
   - **ReShade + Feeder:** use the normal DX11/DX12 path, keep the baseline resolution and quality, disable dynamic resolution, and leave frame generation off.
2. Load the test save. Upscaler and OptiScaler controls may not work fully in the main menu.
3. For ReShade + Feeder, press `Home` to open the ReShade overlay. The key can differ if you changed the ReShade hotkey.
4. Enable the active LumeniteFX technique selected during installation: `LUMENITE: Kernel 2.0` **or** `LUMENITE: QuantMotion`. Both shader files may be installed, but only one provider must be enabled.
5. Enable `DLSS 5 Feed` and keep it **below** the selected LumeniteFX technique in the technique list. ReShade being loaded does not mean these techniques are enabled automatically.
6. In the DLSS5/RenoDX panel, enable neural rendering if the selected consumer exposes a separate toggle. Do not enable another neural consumer or another motion-vector provider.
7. Confirm the overlay reports the selected provider as enabled, then save/reload the preset if ReShade asks.
8. Wait about 30 seconds for shaders and streaming to settle.
9. Check the same view with the camera still and moving, then test a busy scene and a menu or save/load transition.

## Performance comparison

Record these separately:

- native/pre-generation FPS;
- displayed FPS after frame generation, if enabled;
- frame-time consistency and stutter;
- input latency and camera responsiveness.

Generated FPS is not a replacement for native performance. A high displayed number with unstable frame times or poor latency is not a successful result.

## ReShade and toggles

`Home` is the usual key for the ReShade overlay. Other keys depend on the preset or add-on. Do not enable several competing presets or injection methods at the same time.

For **ReShade + Feeder**, the required activation order is: selected LumeniteFX provider first, then `DLSS 5 Feed`, then the neural-rendering toggle. If either technique is unchecked, the installation can appear to do nothing even though ReShade itself is working. If an effect is missing, check `ReShade.log` and the shader paths before changing other game settings. If the game does not expose a usable depth/motion buffer, this method needs game-specific configuration.

## Method-specific quick reference

| Method | Select in the game | Configure after loading a save | First comparison |
|---|---|---|---|
| Native/Bridge | `DLSS` | No ReShade steps; verify the native path is active | DLSS Quality, no frame generation |
| OptiScaler Bridge + DLSS5 | `FSR` or `XeSS` | Open OptiScaler, confirm FSR/XeSS input and DLSS output; verify the DLSS5 add-on in ReShade | Quality mode, same scene and camera |
| ReShade + Feeder | Normal DX11/DX12 path | `Home` → one Lumenite provider → `DLSS 5 Feed` below it → neural toggle if present | Effects enabled, no frame generation |

The library lines in the OptiScaler overlay (`DLSS: Exists`, `FSR 3.1: Exists`, `XeSS: Exists`) report available libraries. They do not select the game's input automatically; the input must still be selected in the game's Graphics menu. For the bridge route, the expected state is an FSR/XeSS input with **DLSS output**. Selecting FSR as the output bypasses the DLSS5 path.

For **Assetto Corsa Rally**, use `XeSS` for the first bridge test. Its FSR 3.1 input requires a game-specific `Engine.ini` command to avoid crashes, so do not select FSR 3.1 until that separate tweak has been verified.

## Accept or roll back

Keep the installation only if the game remains stable for 10–15 minutes and the image is free of persistent ghosting, flicker, broken UI, missing effects, or unacceptable latency. If the game crashes or the image is corrupted, exit the game and use **Restore a selected installation** before trying another method.

# In-game verification checklist

Use this short checklist after every installation.

## Before launching

- Keep the same resolution, graphics preset, ray tracing/path tracing settings, and display mode.
- Use the game's normal DX11/DX12 renderer and disable dynamic resolution or automatic quality while comparing results.
- Keep HDR disabled for an SDR display. Do not change DLSS mode, sharpening, motion blur, or frame generation between the baseline and the test.
- Use the same save and scene for before/after captures.
- If the game uses a launcher, start it through the normal launcher.
- Close overlays that can interfere with injection while diagnosing crashes.

## First launch

1. Open the game graphics settings and enable the path required by the selected method: the game's supported upscaler or DLSS path for Native/Bridge and OptiScaler, or the normal DX11/DX12 render path for ReShade + Feeder. Keep the chosen resolution and quality preset, and disable dynamic resolution or automatic quality while comparing.
2. Press `Home` to open the ReShade overlay. The key can differ if you changed the ReShade hotkey.
3. Enable the active LumeniteFX technique selected during installation: `LUMENITE: Kernel 2.0` **or** `LUMENITE: QuantMotion`. Both shader files may be installed, but only one provider must be enabled.
4. Enable `DLSS 5 Feed` and keep it **below** the selected LumeniteFX technique in the technique list. ReShade being loaded does not mean these techniques are enabled automatically.
5. In the DLSS5/RenoDX panel, enable neural rendering if the selected consumer exposes a separate toggle. Do not enable another neural consumer or another motion-vector provider.
6. Confirm the overlay reports the selected provider as enabled, then save/reload the preset if ReShade asks.
7. Load the test save and wait about 30 seconds.
8. Check the same view with the camera still and moving.
9. Test a busy scene and a menu or save/load transition.

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

## Accept or roll back

Keep the installation only if the game remains stable for 10–15 minutes and the image is free of persistent ghosting, flicker, broken UI, missing effects, or unacceptable latency. If the game crashes or the image is corrupted, exit the game and use **Restore a selected installation** before trying another method.

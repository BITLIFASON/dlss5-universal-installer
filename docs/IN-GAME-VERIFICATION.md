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

1. Load the test save and wait about 30 seconds.
2. Check the same view with the camera still and moving.
3. Test a busy scene and a menu or save/load transition.

## Performance comparison

Record these separately:

- native/pre-generation FPS;
- displayed FPS after frame generation, if enabled;
- frame-time consistency and stutter;
- input latency and camera responsiveness.

Generated FPS is not a replacement for native performance. A high displayed number with unstable frame times or poor latency is not a successful result.

## ReShade and toggles

`Home` is the usual key for the ReShade overlay. Other keys depend on the preset or add-on. Do not enable several competing presets or injection methods at the same time.

For **ReShade + Feeder**, enable `DLSS5_Feed` in the overlay and place it below the selected motion-vector provider. If it is missing, check `ReShade.log` and the shader paths before changing other game settings. If the game does not expose a usable depth/motion buffer, this method needs game-specific configuration.

## Accept or roll back

Keep the installation only if the game remains stable for 10–15 minutes and the image is free of persistent ghosting, flicker, broken UI, missing effects, or unacceptable latency. If the game crashes or the image is corrupted, exit the game and use **Restore a selected installation** before trying another method.

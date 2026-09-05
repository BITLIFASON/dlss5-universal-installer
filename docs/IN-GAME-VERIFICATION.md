# In-game verification checklist

Use this checklist after every installation. It is intended for a reproducible comparison, not a synthetic benchmark.

## Before launching

- Keep the same resolution, graphics preset, ray tracing/path tracing settings, and display mode.
- Use the same save and scene for before/after captures.
- If the game uses a launcher, start it through the normal launcher.
- Close overlays that can interfere with injection while diagnosing crashes.

## First launch

1. Load the test save and wait 30–60 seconds for shaders and asset streaming to settle.
2. Check that the game reaches the world without a crash or a black screen.
3. Move the camera slowly, then quickly. Inspect foliage, fences, hair, neon signs, reflections, particles, and UI edges.
4. Check a busy scene, driving or fast traversal, a menu transition, and a save/load transition.

## Performance comparison

Record these separately:

- native/pre-generation FPS;
- displayed FPS after frame generation, if enabled;
- frame-time consistency and stutter;
- input latency and camera responsiveness.

Generated FPS is not a replacement for native performance. A high displayed number with unstable frame times or poor latency is not a successful result.

## ReShade and toggles

If ReShade is installed, `Home` commonly opens its overlay, but the preset may use another key. Toggle the active preset once and compare the same camera view. Do not enable several competing presets or injection methods at the same time.

## Accept or roll back

Keep the installation only if the game remains stable for 10–15 minutes and the image is free of persistent ghosting, flicker, broken UI, missing effects, or unacceptable latency. If the game crashes or the image is corrupted, exit the game and use **Restore a selected installation** before trying another method.

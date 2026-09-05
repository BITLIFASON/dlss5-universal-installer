# Test matrix

The first test series uses three different games and three different methods:

| Game | Method | What it checks |
|---|---|---|
| Routine | Native/Bridge | Lowest overhead with native DLSS |
| GRAIN.ROT | OptiScaler | Upscaler interception in Unreal Engine |
| Rogue Legacy 2 | ReShade + Feeder | Depth buffer, motion vectors, and post-processing |

Use the same order for each game:

1. Run `-Action Check` and save the manifest.
2. Record the baseline: resolution, preset, and native FPS without frame generation.
3. Install one verified package manifest.
4. Check launch, image quality, and logs.
5. Record the same measurements again.
6. If there is a problem, run `-Action Restore` and confirm that the game launches again.

Archives and manifests must come from the author's official repository or the project's official website. A public file without a confirmed source is not added to the test matrix.

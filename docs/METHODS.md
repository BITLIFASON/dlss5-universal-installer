# Methods

## Native/Bridge

Use this when the game already ships with native DLSS. An additional bridge or add-on intercepts the existing call. It is usually the first performance candidate.

## OptiScaler

Intercepts the upscaler path through a proxy DLL and its own configuration. It can help when Native/Bridge does not work, but requires especially careful rollback.

## ReShade + Feeder

ReShade receives the image, depth buffer, and motion vectors; Feeder builds a DLAA contract for DLSS5. The automatic Feeder profile includes the pinned LumeniteFX Kernel provider and a preset with `Lumenite_Kernel` above `DLSS5_Feed`. This is the most universal route, but it usually costs more FPS and is more sensitive to the game.

The installer never treats these methods as compatible at the same time. A separate manifest and point backup are created before switching.

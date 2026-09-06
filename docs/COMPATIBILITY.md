# Compatibility matrix

This matrix describes the current installer scope. A method marked as a candidate still requires a real game test; it is not a compatibility guarantee. Documented failed combinations produce a prominent warning before installation.

| Target | Native/Bridge | OptiScaler Bridge + DLSS5 | ReShade + Feeder | Current status |
|---|---:|---:|---:|---|
| DirectX 11 x64 | Candidate when the game ships native DLSS | Candidate when the proxy path is supported | Candidate when ReShade can access depth and motion data | Supported scope; verify per game |
| DirectX 12 x64 | Candidate when the game ships native DLSS | Candidate when the proxy path is supported | Candidate when ReShade can access depth and motion data | Supported scope; verify per game |
| DirectX 11/12 x86 | Not assumed | Not assumed | Requires a compatible x86 or host component | Experimental only |
| Vulkan | Not implemented in the first release | Not implemented in the first release | Not implemented in the first release | Out of scope for now |
| OpenGL | Not implemented in the first release | Not implemented in the first release | Not implemented in the first release | Out of scope for now |
| Online games with anti-cheat | Not a target | Not a target | Not a target | Do not use without confirming the game's rules |

## Method guidance

### Native/Bridge

Choose this first when inspection finds native DLSS files such as `nvngx_dlss.dll`. It normally adds the least extra interception overhead, but the game must expose a compatible native DLSS path.

### OptiScaler Bridge + DLSS5

Use this when the game exposes an FSR or XeSS input that can be redirected through OptiScaler into the DLSS5 neural-rendering add-on. The game's input must be FSR/XeSS and the bridge output must be DLSS. Proxy DLL conflicts and game-specific configuration are possible, so restore the previous installation before switching to another method. Standalone OptiScaler is not installed by this project.

### ReShade + Feeder

Use this for games without a native DLSS path when ReShade can obtain the required depth and motion information. It is the broadest route in this installer, but it can cost more performance and may require per-game shader or buffer configuration.

## How compatibility is determined

The installer inspects executable architecture, candidate executable paths, native DLSS filenames, common FSR/XeSS runtime filenames, and common proxy DLL filenames. These are hints for choosing a method, not proof that injection will work. The final decision requires a launch test, image-quality check, and performance measurement in the target game.

### Documented failed combinations

`Assetto Corsa Rally` has a recorded warning for **OptiScaler Bridge + DLSS5**. The local test produced a black rendered frame with the HUD still visible; the game's normal DLSS/FSR paths worked after rollback. The entry is stored in [`config/compatibility.json`](../config/compatibility.json). The wizard asks for confirmation and does not block the experiment automatically.

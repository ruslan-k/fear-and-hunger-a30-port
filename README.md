# Fear & Hunger for Miyoo A30 (SpruceOS)

A working port of Fear & Hunger (RPG Maker MV, 1.4.1) for the Miyoo A30, running on a custom armhf build of [quixjs](https://github.com/lowlevel-1989/quixjs) 0.3.0.

## Status

| Subsystem | State |
|---|---|
| Launch from the SpruceOS ports menu | working |
| Full-screen rotated rendering | working |
| Controls (D-pad, face buttons, Start/Select) | working |
| Audio | working |
| Quit with a long press of the physical Menu button | working |
| Memory | runs within the A30's RAM, no OOM observed |

The runner reaches the title screen, starts a new game and runs the game at the configured 30 fps target.

## Performance

The A30's Mali-400 MP GPU is used for presentation and WebGL (no software rasterizer). Measured on the overclock profile (CPU 1.344 GHz, `performance` governor), from quixjs's own per-minute perf log:

| Internal resolution | FPS | Frames over 50 ms |
|---|---|---|
| 816x624 (upstream RPG Maker MV size) | 15.1 / 17.8 / 18.7 / 22.8 | 369 / 453 / 732 / 284 per minute |
| 640x480 (native A30 panel) | 27.0 / 29.5 | 12 / 12 per minute |

The 640x480 setting is the one shipped in this repo. It matches the panel's physical resolution, removes the small black side bars, and cuts GPU work by about 40%. To go back to the stock size, restore `[game] width = 816` and `height = 624` in `port.toml`.

`[engine] js_memory` is set to 96 MB. It is a JavaScriptCore GC-policy hint (`JSC_forceRAMSize`), not a hard RSS cap. In a controlled 184-second A/B on the overclock profile, 96 MB reduced peak swap from 151 MB to 67 MB, swap-out from ~203 MiB to ~80 MiB and D-state samples from 29 to 18 out of 90, without a reproducible FPS regression. The old value is kept as `port.toml.bak-js128` on the device.

## Repository contents

- `runtime/quixjs.armhf` — prebuilt armhf runner (glibc 2.23, armv7, static JavaScriptCore). MD5: `2051213716ec3d764cd92bd684d29380`. This is the exact binary used on the device.
- `launcher/Fear and Hunger.sh` — launcher, installed into `A30PORTS/`.
- `launcher/gamecontrollerdb.txt` — SDL controller mapping for the A30 pad.
- `port/port.toml` — quixjs game configuration (copied from upstream quixjs, with the A30 install path in `inst` and the internal resolution set to the panel's native 640x480).
- `patches/quixjs-a30.patch` — two source changes: full-screen rotated presentation with `QUIX_ROT`, direct reading of the A30's physical buttons from `/dev/input/event3`, and a glibc 2.23 fallback for JavaScriptCore.
- `build/build_quixjs_a30.sh` — reproducible armhf cross-build script.
- `fonts/DejaVuSans-Bold.ttf` — font for the launcher menu.
- `LICENSE` — GPL-3.0, inherited from quixjs.

## Installation

1. Copy `launcher/Fear and Hunger.sh` to `/mnt/SDCARD/Roms/A30PORTS/` and make it executable (`chmod +x`).
2. Create `/mnt/SDCARD/Roms/A30PORTS/fearandhunger/`.
3. Copy `runtime/quixjs.armhf`, `port/port.toml`, `launcher/gamecontrollerdb.txt` and `fonts/DejaVuSans-Bold.ttf` into that directory. Make the runner executable (`chmod +x quixjs.armhf`).
4. Put the game files in `/mnt/SDCARD/Roms/A30PORTS/fearandhunger/gamedata/www/` — the `www/` folder from Fear & Hunger 1.4.1 for Windows (DRM-free from itch.io). `Game.exe` and `.dll` files are not needed.
5. Start the port from the SpruceOS ports menu.

The runner reads its settings from `port.toml` next to it and writes `log.txt` in the same directory.

## Controls

D-pad moves the cursor and the player; A confirms, B and X cancel; Y sends the `C` key used by the game's menu; Start sends Enter; Select sends Escape. Hold the physical Menu button for about one second to exit cleanly to SpruceOS.

The A30's physical buttons are keyboard events on `/dev/input/event3`; they are not carried by the virtual SDL gamepad. The patch reads that device directly and feeds the events to quixjs, which is why no helper such as gptokeyb is needed (the firmware only ships an aarch64 build of it).

## Build

The prebuilt runner is built from quixjs 0.3.0 with `build/build_quixjs_a30.sh`. Run it in an amd64 Debian/Ubuntu container with network access. It downloads the public A30 buildroot toolchain (glibc 2.23), builds JavaScriptCore/ICU/libc++ against that sysroot, applies `patches/quixjs-a30.patch`, and cross-compiles the runner with clang. The stock armhf cross toolchains link against a newer glibc and the resulting binary will not start on the A30.

QuixJS is GPL-3.0; JavaScriptCore, ICU, tomlc17, stb_vorbis, nestegg and PixiJS keep their own licenses (see upstream `runtime/thirdparty` and the release licenses).

## A30 low-memory guard (source-only change)

The stock quixjs 0.3.0 `platform_mem_available_mb()` returns -1 on older A30
kernels without `MemAvailable`. As a result, the `low_memory_mb` rescue in
`runtime/core/main.c` never runs. The extra patch
`patches/quixjs-a30-memavailable.patch` falls back to
`MemFree + 0.5 * max(0, Cached + Buffers + SReclaimable - Shmem)`.
It does **not** count SwapCached as free. When `MemAvailable` exists, its
value is still preferred.

The patch takes effect **only after rebuilding** with
`build/build_quixjs_a30.sh` and deploying the new `runtime/quixjs.armhf`;
the committed prebuilt binary is **unchanged**. The port config uses
`low_memory_mb = 96`. Set it to `0` to A/B test the old behaviour. This
guard targets memory-pressure stalls, not unconditional FPS uplift. Compare
the same scene for at least three minutes: FPS and slow frames in `log.txt`,
VmRSS/VmSwap in `/proc/<pid>/status`, and `pswpout` in `/proc/vmstat`.
If full GC occurs repeatedly or frame pacing deteriorates, restore `0`.

## Experimental ARMv7 NEON texture conversion

The Allwinner A33 has ARMv7 NEON/VFPv4, but our previous build explicitly
selected `-mfpu=vfpv3-d16`. Quixjs 0.3.0 already contains an exact integer
NEON implementation of WebGL `UNPACK_PREMULTIPLY_ALPHA_WEBGL` but gates it
on `__aarch64__`. The small `quixjs-a30-neon.patch` also enables it when
`__ARM_NEON` is defined. The build defaults to
`-mcpu=cortex-a7 -mfpu=neon-vfpv4`.

To A/B the SIMD optimization without changing the game settings:

```sh
A30_USE_NEON=0 bash build/build_quixjs_a30.sh   # scalar build
# Copy runtime/quixjs.armhf to a separate named backup before the next build.
A30_USE_NEON=1 bash build/build_quixjs_a30.sh   # NEON build
```

Compare identical movement/battle routes and inspect `log.txt` for slow
frames. Both builds use the same WebGL semantics and 640x480 rendering;
NEON accelerates the CPU-side alpha premultiplication on texture uploads,
**not** the GPU shader or the JavaScript game logic. No real-device FPS
improvement is claimed. The NEON intrinsic code cross-compiled to ARMv7
assembly with clang; the resulting ARM EABI5 binary requires only GLIBC 2.17.

Device A/B (2026-11-21, Miyoo A30, quixjs 0.3.0, stock `port.toml` with no
`low_memory_mb`, 640x480, 60 s warmup + 120 s windows): median FPS 24.9
(scalar) vs 24.5 (NEON), JS/frame 38.6 vs 39.0 ms, p95 frame time 115 vs
107 ms. Lower RSS (about 280 MB vs 205-226 MB) and VmSwap (4.5 MB vs
1.4 MB) were observed, but baseline memory conditions differed and the two
builds also change CPU tuning (`-mfpu=vfpv3-d16` vs `-mcpu=cortex-a7
-mfpu=neon-vfpv4`). So NEON is not a proven FPS win, and no SIMD-only
conclusion can be drawn. Keep it experimental and fixed-scene A/B plus a
`low_memory_mb` comparison before claiming a gain. Always retain the previous
working binary.

## Backported RPG Maker hooks from quixjs 0.4.0 (experimental)

`patches/quixjs-a30-hooks-0.4.patch` replaces the 0.3.0
`refresh-on-net-change` and `pure-common-events` hooks with their 0.4.0
algorithms (partial map refresh, richer pure-event detection). 0.4.0 calls
`__quixEngine.sameCode`, which does not exist in 0.3.0; the patch inlines an
equivalent helper in each hook, so no runtime C code or build rules change.
The build script applies the patch automatically. `find-path-index` and
`__quixEngine.lib()` are deliberately excluded: they need additional 0.4.0
runtime support.

Device baseline for the hooks A/B (2026-11-21, A30, Scene_Map map 74, 640x480,
scalar binary, 30 s warmup + 150 s window): median FPS 26.4, JS/frame 35.0 ms,
p95 frame time 90 ms (153 samples). The hooks arm was built (ARM EABI5, SHA-256
`85b62ebb1cd2945652f212bb33444799964434192f2499fb22ecb262f6057c9c`) but the
device went offline before the matched run; no effect is claimed. Check the
log for `[refresh-on-net-change] partial refresh: on` before trusting the
optimization on a new build.

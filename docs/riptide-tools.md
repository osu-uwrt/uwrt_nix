# riptide-tools: nereus and notgroot

Both riptide shells put `riptide-tools` on PATH: one build, from the dev pin, so `riptide-dev` and `riptide-release` resolve the same store paths (`nix/riptide-tools.nix`).

| Command | From |
|---|---|
| `notgroot`, `notgroot-check`, `notgroot-globals` | notgroot (BT.CPP 4.10.0 for `notgroot-check`, fetched with `fetchFromGitHub`, separate from riptide's BT v3) |
| `nereus-packs`, `nereus-dataset` | nereus' Python pack/dataset tools, deps from nixpkgs (not uv.lock) |
| `nereus-dataset-render` | nereus' headless renderer (the `datasets` preset: simulation, renderer, offscreen cameras, no ROS) |
| `nixGLIntel` | Linux only, see below |

`nix build .#riptide-tools` (or `.#nereus`, `.#notgroot`) builds them on their own. `nix build .#checks.<system>.notgroot-tests` / `nereus-tests` run the projects' own ctest suites the same way. On Linux the build sandbox has no GL driver, so the tests get Mesa's software EGL (llvmpipe, surfaceless) and the offscreen/renderer tests really run; tests that need a window skip.

**Assimp 5.2.5, not nixpkgs' 6.x.** Assimp 6 orders mesh indices differently, so nereus' recorded mesh references (made with jammy's Assimp 5.2) fail with it (`MeshAssets.EveryOriginalSubmesh…`: same vertices and statistics, different index hashes). nereus builds against both; `riptide-tools.nix` pins 5.2.5 (without its MMD importer, which gcc 15 can't compile) for the package, the tests and the shells' `build.sh`.

## nereus' ROS bridge and viewer: built in the workspace

`nereus-sim` and `nereus-viewer` need the workspace's `riptide_msgs2` (the UWRT panels), and nereus' launch files run them from nereus' own `build/ros-viewer/`. So they're not in the Nix package; build them with nereus' own script inside `riptide-dev` or `riptide-release`, which carry every library they need (`buildInputs`, found through `NIXPKGS_CMAKE_PREFIX_PATH`, from each shell's own pin) plus `uv`:

```bash
cd ~/osu-uwrt/development/software        # direnv loads riptide-dev
uwrt build                                # riptide_msgs2 and the rest first
(cd src/nereus && ./build.sh ros-viewer)  # .venv (uv) + build/ros-viewer
ros2 launch src/nereus/integrations/uwrt/launch/sim.launch.py
```

Release has nereus as a submodule at the workspace root, not in `src/`:

```bash
cd ~/osu-uwrt/release                 # direnv loads riptide-release
uwrt build
(cd nereus && ./build.sh ros-viewer)
ros2 launch nereus/integrations/uwrt/launch/sim.launch.py
```

- `uv sync` makes `.venv` from Nix's Python (`UV_PYTHON`), never a downloaded one (`UV_PYTHON_DOWNLOADS=never`). Its packages still come from nereus' `uv.lock` (PyPI wheels), as on apt machines.
- notgroot's `./build.sh` works in the same shell.

## macOS

- **Offscreen cameras**: CGL (`libraries/rendering/src/offscreen_cgl.cpp`), a windowless core-profile context, instead of EGL, and not a hidden GLFW window: GLFW can only make windows on the main thread on macOS, while camera hosts are created and used on worker threads (and a GLFW window would give `nereus-sim` a Dock icon). CGL has neither problem and also renders with the display off.
- **File dialogs**: `osascript` (`choose file` / `choose folder` / `choose file name`) when there's no zenity or kdialog.
- **notgroot pinch**: the trackpad's magnify events (`app/src/pinch_cocoa.mm`). Cmd+scroll zooms too (ImGui maps macOS Cmd to Ctrl).
- **nereus viewer** keeps the system title bar (the custom one needs X11).
- **Retina and the Dock:** both apps scale their UI by the desktop scale divided by the display's pixels per point (1 on a Retina Mac, whose window units are already points), with fonts rasterized at full resolution. Their Dock icon is set through Cocoa (`dock_icon_cocoa.mm`): GLFW has no window icons on macOS, and a bare executable would get the generic "exec" tile.
- **Debug builds (`./build.sh dev`)** link glew through `riptide-tools.nix`'s glew override: nixpkgs' `GLEW::GLEW` loses its config fallback, so Debug builds linked a bare `GLEW`.
- **Fonts**: `FONTCONFIG_FILE` points at a config that adds `/System/Library/Fonts`, `/Library/Fonts`, `~/Library/Fonts` (Linux: `/usr/share/fonts`, ...) to nixpkgs' default, which only knows its own DejaVu. The shells export it too, for the workspace-built viewer.
- Bullet: nereus links Debian's double-precision `libBullet*-float64`; the flake builds bullet with `USE_DOUBLE_PRECISION` and those names.
- **Known test differences (macOS only)**, 4 of nereus' 343 tests: `BoxContacts.PlantMatchesOriginal…` misses its 1e-9 contact reference by 1e-5 because clang contracts multiply-adds into FMA on arm64 (it passes with `-ffp-contract=off`). `PackRuntime.MatchesReference…` and the two `Session.ReplaysTheRecordedScript…` replays (recorded on Linux) differ from the first depth sample on, by about 1.5 cm: most likely sensor noise, since `std::normal_distribution` is implementation-defined and libc++ draws other values than libstdc++ from the same seed. So a Mac run is not bit-identical to a Linux run with the same seed.

## Linux (non-NixOS): nixGL

Nix-built GL programs can't load the distro's GL drivers. The `notgroot` and `nereus-dataset-render` launchers run through `nixGLIntel` (Mesa from the same nixpkgs) unless `/etc/NIXOS` exists. Programs built in the workspace (nereus' viewer and sim) need it by hand:

```bash
nixGLIntel ros2 launch src/nereus/integrations/uwrt/launch/sim.launch.py
nixGLIntel src/nereus/build/ros-viewer/nereus-viewer
```

`UWRT_NIXGL` picks another wrapper for the launchers (`none` runs them directly).

**NVIDIA** (proprietary driver): nixGLIntel only covers Mesa (Intel/AMD, and llvmpipe). NVIDIA needs `nixGLNvidia`, which has to match the installed kernel driver version, so it can only be built impurely:

```bash
nix run --impure github:nix-community/nixGL#nixGLNvidia -- <program>
# or once:   nix build --impure github:nix-community/nixGL#nixGLNvidia   and set UWRT_NIXGL to result/bin/nixGLNvidia-<version>
```

It reads the driver version from `/proc/driver/nvidia/version` at eval time, and must be rebuilt after a driver update. Hybrid laptops can stay on the iGPU with nixGLIntel, for example when the NVIDIA GPU has no driver loaded.

## Sources

The flake inputs `nereus` and `notgroot` fetch the repos' `nix-macos` branches from GitHub (notgroot is private, so over ssh). `nix flake update nereus notgroot` moves them to the branches' current commits. Uncommitted edits: `--override-input notgroot git+file://$HOME/osu-uwrt/notgroot`.

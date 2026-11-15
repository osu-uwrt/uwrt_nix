# riptide-tools: nereus and notgroot

Both riptide shells put `riptide-tools` on PATH: one build, from the dev pin, so `riptide-dev` and `riptide-release` resolve the same store paths (`nix/riptide-tools.nix`).

| Command | From |
|---|---|
| `notgroot`, `notgroot-check`, `notgroot-globals` | notgroot (BT.CPP 4.10.0 for `notgroot-check`, fetched with `fetchFromGitHub`, separate from riptide's BT v3) |
| `nereus-packs`, `nereus-dataset` | nereus' Python pack/dataset tools, deps from nixpkgs (not uv.lock) |
| `nereus-dataset-render` | nereus' headless renderer (the `datasets` preset: simulation, renderer, offscreen cameras, no ROS) |
| `nixGLIntel` | Linux only, see below |

`nix build .#riptide-tools` (or `.#nereus`, `.#notgroot`) builds them on their own. `nix build .#checks.<system>.notgroot-tests` / `nereus-tests` run the projects' own ctest suites the same way.

## nereus' ROS bridge and viewer: built in the dev workspace

`nereus-sim` and `nereus-viewer` need the workspace's `riptide_msgs2` (the UWRT panels), and nereus' launch files run them from `src/nereus/build/ros-viewer/`. So they're not in the Nix package; build them with nereus' own script inside `riptide-dev`, which carries every library they need (`buildInputs`, found through `NIXPKGS_CMAKE_PREFIX_PATH`) plus `uv`:

```bash
cd ~/osu-uwrt/development/software        # direnv loads riptide-dev
uwrt build                                # riptide_msgs2 and the rest first
(cd src/nereus && ./build.sh ros-viewer)  # .venv (uv) + build/ros-viewer
ros2 launch src/nereus/integrations/uwrt/launch/sim.launch.py
```

- `uv sync` makes `.venv` from Nix's Python (`UV_PYTHON`), never a downloaded one (`UV_PYTHON_DOWNLOADS=never`). Its packages still come from nereus' `uv.lock` (PyPI wheels), as on apt machines.
- notgroot's `./build.sh` works in the same shell.
- `riptide-release` only gets the binaries; release's `nereus` submodule isn't built there.

## macOS

- **Offscreen cameras**: CGL (`libraries/rendering/src/offscreen_cgl.cpp`), a windowless core-profile context, instead of EGL. The plan said a hidden GLFW window; GLFW can only make windows on the main thread on macOS, while camera hosts are created and used on worker threads (and a GLFW window would give `nereus-sim` a Dock icon). CGL has neither problem and also renders with the display off.
- **File dialogs**: `osascript` (`choose file` / `choose folder` / `choose file name`) when there's no zenity or kdialog.
- **notgroot pinch**: the trackpad's magnify events (`app/src/pinch_cocoa.mm`). Cmd+scroll zooms too (ImGui maps macOS Cmd to Ctrl).
- **nereus viewer** keeps the system title bar (the custom one needs X11).
- **Fonts**: `FONTCONFIG_FILE` points at a config that adds `/System/Library/Fonts`, `/Library/Fonts`, `~/Library/Fonts` (Linux: `/usr/share/fonts`, ...) to nixpkgs' default, which only knows its own DejaVu. The shells export it too, for the workspace-built viewer.
- Bullet: nereus links Debian's double-precision `libBullet*-float64`; the flake builds bullet with `USE_DOUBLE_PRECISION` and those names.

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

It reads the driver version from `/proc/driver/nvidia/version` at eval time, and must be rebuilt after a driver update. Hybrid laptops can stay on the iGPU with nixGLIntel (ethan-XPS does: the RTX 3050 has no driver loaded).

## Sources

The flake inputs `nereus` and `notgroot` point at the local `nix-macos` branches (`git+file://...?ref=nix-macos`) until those are pushed. Then repoint them at GitHub (`git+https://github.com/osu-uwrt/nereus?ref=<branch>`, `git+ssh://git@github.com/osu-uwrt/notgroot?ref=<branch>`) and `nix flake update nereus notgroot`, before sharing uwrt_nix: nobody else has those paths. Uncommitted edits: `--override-input notgroot git+file://$HOME/osu-uwrt/notgroot`.

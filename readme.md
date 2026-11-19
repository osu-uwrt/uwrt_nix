# uwrt_nix

The development environment for UWRT's riptide software and firmware, as a Nix flake. On macOS (Apple
silicon) and Linux it gives every machine the same ROS 2 Humble, colcon, compilers and tools, without apt or
`/opt/ros`. With direnv, `cd` into a workspace loads its environment and leaving unloads it.

| Shell | For | Loaded in |
|---|---|---|
| `riptide-dev` (default) | the dev colcon workspace: a ROS env built from its package.xml dependencies, colcon with colcon_riptide, nereus' and notgroot's tools and build libraries | `~/osu-uwrt/development/software` |
| `riptide-release` | the release workspace, same idea on the release pin (nereus' build libraries from that pin) | `~/osu-uwrt/release` |
| `firmware` | titan_firmware: Arm GCC 13, pico-sdk, libmicroros, openocd, Rust, titan's host tools, the micro-ROS agent | `~/osu-uwrt/development/titan_firmware` |

## Quick start

On a machine with Nix (flakes on), the ROS binary caches, direnv and nix-direnv, which [docs/setup.md](docs/setup.md)
walks through:

```sh
git clone git@github.com:osu-uwrt/uwrt_nix.git ~/osu-uwrt/uwrt_nix   # plus the workspaces, docs/setup.md step 6
nix profile add ~/osu-uwrt/uwrt_nix#uwrt
uwrt setup        # .envrc in each workspace that exists, then direnv allow
uwrt doctor       # checks the machine
cd ~/osu-uwrt/development/software && uwrt build
```

Without direnv: `nix develop --impure ~/osu-uwrt/uwrt_nix#riptide-dev` (`--impure` because the shell reads the
workspace's package.xml files).

## `uwrt`

| Command | |
|---|---|
| `uwrt dev` / `release` / `fw [cmd…]` | a shell (or one command) in that workspace's env, from anywhere |
| `uwrt build [colcon args]` | colcon build from the workspace root, then a merged `build/compile_commands.json` |
| `uwrt rmw zenoh\|fastdds-local\|show` | pick the RMW (`fastdds-local` for local work, `zenoh` for the robot) |
| `uwrt setup` | write the `.envrc` files |
| `uwrt doctor` | check Nix, caches, direnv, git, rsync, maxfiles and the workspaces |
| `uwrt deps update` | regenerate `deps/system-keys.json` after bumping nix-ros-overlay |

## Docs

| | |
|---|---|
| [docs/setup.md](docs/setup.md) | first-time machine setup, cloning the workspaces, updating, troubleshooting |
| [docs/sourcing.md](docs/sourcing.md) | how a workspace gets its env: `.envrc`, `uwrt`, RMW settings, zsh completion, clangd, apt ROS on Linux |
| [docs/riptide-tools.md](docs/riptide-tools.md) | nereus and notgroot, the simulator, nixGL on Linux |
| [docs/firmware.md](docs/firmware.md) | the firmware shell: building, uploading, the micro-ROS agent, CAN |
| [docs/complete_controller_macos.md](docs/complete_controller_macos.md) | the legacy complete_controller on macOS |

## Layout

| Path | What |
|---|---|
| `flake.nix`, `flake.lock` | inputs (nix-ros-overlay for dev and for release, the team repos built here, upstream uwrt_nix for the firmware shell) and outputs: the shells, `packages` (`uwrt`, `colcon`, `riptide-tools`, `nereus`, `notgroot`, `upload-tool`, `canmore-cli`, `canmore-can`, `micro-ros-agent`, `libmicroros`), `checks`, `apps.deps-update` |
| `nix/riptide-shell.nix` | one riptide shell: scans `$UWRT_WS/src`, builds the ROS env, on macOS wraps its programs so `DYLD_LIBRARY_PATH` survives SIP |
| `nix/deps.nix`, `deps/*.json` | package.xml keys to Nix packages: `team-keys.json` (hand-kept, per platform), then `system-keys.json` (generated from rosdistro), then ROS packages by name |
| `nix/skip.nix` | packages colcon ignores and the scan leaves out |
| `nix/overlay.nix`, `nix/patches/` | fixes to upstream ROS packages, mostly for macOS |
| `nix/ros-extra.nix` | ROS packages not in rosdistro (chameleon_tf, nortek_dvl, zed_interfaces) |
| `nix/colcon.nix` | colcon, colcon_riptide and the colcon defaults file |
| `nix/strip-apt.sh` | the shells' hook drops `/opt/ros` and other workspaces from the path variables |
| `nix/riptide-tools.nix` | nereus' and notgroot's tools, and their tests as `checks` |
| `nix/firmware-shell.nix`, `nix/titan-tools.nix`, `nix/libmicroros.nix`, `nix/micro-ros-agent.nix` | the firmware shell and what it adds to upstream's |
| `nix/uwrt.nix`, `uwrt/` | the `uwrt` and `uwrt-env` commands, their config files and zsh completion |
| `scripts/`, `tests/` | the `deps-update` script, macOS library checks |

The flake only sees files git tracks: `git add` a new file before it counts.

## Maintenance

- **Bump ROS:** `nix flake update nix-ros-overlay` (and `nix-ros-overlay-release` to cut a release), then
  `uwrt deps update` and commit both. Pick a revision the caches have built: older pins drop out of the
  caches over time, and `uwrt doctor` warns after 90 days.
- **Bump a team repo:** `nix flake update <input>` (`nereus`, `notgroot`, `titan_firmware`, …).
- **Test an uncommitted checkout:** `--override-input notgroot git+file://$HOME/osu-uwrt/notgroot`.
- **After a commit here:** `nix profile upgrade uwrt`, so the `uwrt` on PATH matches.

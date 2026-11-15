# Sourcing: direnv, `uwrt` and coexistence with apt ROS

How a workspace gets its environment, and how that lives next to an apt ROS setup on Linux.

## Setup (once per machine)

```bash
nix profile add ~/osu-uwrt/uwrt_nix#uwrt   # uwrt and uwrt-env on PATH everywhere
uwrt setup                                 # .envrc in development/software and release, then direnv allow
uwrt doctor                                # checks nix, direnv + nix-direnv, git, rsync, maxfiles, the bashrc guard
```

Needs direnv with its shell hook (`eval "$(direnv hook zsh)"` or `bash`) and nix-direnv 3 sourced from `~/.config/direnv/direnvrc`.

Workspace locations default to `~/osu-uwrt/development/software`, `~/osu-uwrt/release` and `~/osu-uwrt/uwrt_nix`. Override them with `UWRT_DEV_WS`, `UWRT_RELEASE_WS` and `UWRT_NIX` in `~/.uwrt/env` (or the environment) before `uwrt setup`.

## What happens on `cd`

`uwrt setup` writes this `.envrc` (untracked; in release it's listed in `.git/info/exclude`, never `.gitignore`):

1. `export UWRT_WS=$PWD`. The shell scans `$UWRT_WS/src`'s package.xml files at eval time, hence `--impure`.
2. `watch_file` on every tracked file in uwrt_nix (every file, if uwrt_nix isn't a git checkout), its git `HEAD`, index and branch ref, and every package.xml. The git files matter because a commit changes no tracked file but does change the flake's revision (it's in `uwrt`'s version); as a side effect, `git add` and some `git status` index refreshes in uwrt_nix also trigger a re-evaluation. nix-direnv re-evaluates only when one of these is newer than its cache, so editing a dependency in a package.xml takes effect on the next prompt. Adding a package, or adding/removing a `COLCON_IGNORE`, needs `direnv reload`. (A deleted package.xml doesn't trigger one either; its deps just stay in the env until the next re-eval.)
3. `use flake <uwrt_nix>#riptide-dev --impure` (or `#riptide-release`). The shellHook drops `/opt/ros` and every colcon workspace the outer shell had sourced from the path variables (`nix/strip-apt.sh`) and sets `UWRT_NIX_SHELL`.
4. `eval "$(uwrt-env)"`: the RMW settings (below). `~/.uwrt/env` is watched after `use flake`, so switching RMW only reloads; it doesn't re-evaluate Nix.
5. `source install/local_setup.bash` if the workspace is built. On macOS `DYLD_LIBRARY_PATH` is then unset again: it would shadow system libraries (libyaml, …) for every program, and install rpaths plus the ROS program wrappers already find the libraries.

A cached load takes about 0.2–0.3 s. A cache miss (changed package.xml, uwrt_nix edit) takes about 1.3 s, longer when something has to build. A fresh Mac's first load builds about 100 core ROS packages (about 8 minutes).

## `uwrt`

| Command | What it does |
|---|---|
| `uwrt dev` / `uwrt release` | A shell in that workspace with its env, from anywhere (`direnv exec`; falls back to `nix develop` without direnv) |
| `uwrt dev <cmd…>` | Runs one command in that env, in the current directory |
| `uwrt build [colcon args]` | `colcon build` from the workspace root (works from any subdirectory), then, even when the build fails, merges `build/*/compile_commands.json` into `build/compile_commands.json` and refreshes the workspace's GC roots (see below) |
| `uwrt rmw zenoh\|fastdds-local\|show` | Saves the RMW in `~/.uwrt/env`; direnv applies it on the next prompt |
| `uwrt deps update` | Regenerates `deps/system-keys.json` from the pinned rosdistro |
| `uwrt setup [--patch-bashrc [FILE] \| --unpatch-bashrc [FILE]] [--dry-run] [--force]` | See above and below |
| `uwrt doctor` | Machine checks; exits non-zero on a failure. Also warns when the `uwrt` you ran wasn't built from uwrt_nix's current commit (`uwrt --version` shows `0.2.0+<commit>`; `nix profile upgrade uwrt`) |

## RMW (`uwrt-env`, replaces release's `config_rmw.bash`)

| | `fastdds-local` (macOS default) | `zenoh` (Linux default, the team's) |
|---|---|---|
| `RMW_IMPLEMENTATION` | `rmw_fastrtps_cpp` | `rmw_zenoh_cpp` |
| Domain | `93` (`UWRT_LOCAL_DOMAIN`) | `4` (`UWRT_ROBOT_DOMAIN`) |
| Other | `ROS_LOCALHOST_ONLY=1`; unsets `ZENOH_*` and the FastDDS discovery-server settings release's scripts export (`ROS_DISCOVERY_SERVER`, `ROS_SUPER_CLIENT`, `FASTRTPS_/FASTDDS_DEFAULT_PROFILES_FILE`, `ROS_AUTOMATIC_DISCOVERY_RANGE`, `ROS_STATIC_PEERS`) | `ZENOH_SESSION_CONFIG_URI` = release's `scripts/dds_scripts/zenoh/zenoh_client.json5` (else a copy shipped with uwrt), `ZENOH_ROUTER_CHECK_ATTEMPTS=10` |

With zenoh every node connects to the robot's router (`orin2:7447`) and gives up when it's off, so local work uses `fastdds-local`. `~/.uwrt/env` takes `KEY=value` lines; uwrt reads them without running them.

**Tab completion (opt-in, zsh):** one line in `~/.zshrc`, after `compinit`, costs about 0.3 s per new shell:

```zsh
eval "$(uwrt dev register-python-argcomplete --shell zsh ros2 colcon 2>/dev/null)"
```

Completion then works wherever `ros2`/`colcon` are on PATH, i.e. inside a workspace. bash: the same with `--shell bash`.

## Editors (compile_commands.json, clangd)

colcon's defaults export compile commands, and `uwrt build` merges them into `<workspace>/build/compile_commands.json`. clangd finds that file on its own (it looks in `build/` of each parent directory).

The compiler in those commands is Nix's clang/gcc wrapper, which adds the SDK, libc++ and dependency include paths from environment variables. clangd needs both of these:
- `--query-driver='/nix/store/*-clang-wrapper-*/bin/clang*'` (Linux: `'/nix/store/*-gcc-wrapper-*/bin/*'`), so it asks the wrapper for its include paths;
- the workspace env, so the wrapper sees those variables. Start the editor (or clangd) from inside the workspace (`uwrt dev`, or a direnv integration).

Checked on macOS with Apple's clangd 21: 62 errors without the flag, 2 with the flag outside the env, none with both.

## Linux: coexisting with apt ROS in `~/.bashrc`

A `.bashrc` that sources `/opt/ros` and apt-built workspaces would leak them into nested shells (`nix develop` reads `~/.bashrc`; so does every terminal an editor opens). `uwrt setup --patch-bashrc` wraps each ROS part of `~/.bashrc` in:

```bash
# >>> uwrt nix guard >>> (uwrt setup --patch-bashrc; apt ros only outside nix shells)
if [ -z "${UWRT_NIX_SHELL:-}" ] && [ ! -f ~/.uwrt/use_nix ]; then
...
fi # <<< uwrt nix guard <<<
```

- It finds the parts by statement, not by line number: bash itself (`bash -n`) says where each top-level statement ends, and statements mentioning ROS (`/opt/ros`, `ros2`, `ROS_*`, `RMW_*`, `ZENOH*`, the `sr`/`srd` selection functions, workspace `install/setup.bash`, …) are wrapped. Other lines (GPG_TTY, aliases, cargo) stay outside.
- `--dry-run` prints the diff. It keeps a timestamped backup and refuses a file that doesn't parse (or a result that wouldn't). On a partly guarded file it wraps only what's left; on a fully guarded one it does nothing. Heredocs stay whole. `uwrt setup --unpatch-bashrc` removes the guard again, byte-identical to before (including CRLF line endings and a missing final newline).
- Note: aliases and functions that would work fine with Nix's `ros2` (`ros_restart`, `zenohd`, `rviz()` on xps) are inside the guard too, because they mention ROS. An alias *called* elsewhere in the file without a ROS word (e.g. an uncommented `srd` autoselect) stays outside and would say "command not found" in a Nix shell; guard such a line by hand.
- `touch ~/.uwrt/use_nix` turns apt ROS off for every new shell, not just inside Nix shells.
- `uwrt doctor` fails on Linux when `~/.bashrc` has a ROS statement outside the guard (the same detection the patcher uses, so it covers workspaces like `~/ros2_ws/install/setup.bash` too).

The shells also strip apt paths themselves (step 3 above), so the env is clean even when the outer shell had apt ROS sourced. The guard covers shells started *inside* a Nix env. The strip also drops another riptide shell's ROS env, so a `nix develop` of one shell nested inside the other ends up with only its own.

## Known limits and decisions

- **One colcon for both shells** (user decision, 2026-11-15). colcon and colcon_riptide come from the dev overlay pin in `riptide-release` too. colcon runs ament_python `setup.py` builds with its own Python, so once the release pin's Python differs from the dev pin's, release Python packages may break and need a per-pin colcon again. Today both pins are the same commit.
- **Envs and garbage collection.** A colcon workspace links against the ROS env it was configured with. nix-direnv only roots the *current* env (under `.direnv/`), and already-configured packages keep pointing at the old one after the env changes (a uwrt_nix edit or bump). So `uwrt build` keeps a GC root in `build/.uwrt-gcroots/` for every ROS env any package's CMake cache uses, drops roots nothing uses any more, and names the packages still on an older env (`uwrt build --cmake-clean-cache --packages-select …` moves them over). Builds made with plain `colcon build` get their roots at the next `uwrt build`. `rm -rf build` drops the roots with it.
- uwrt's closure is the dev pin's python3, the same store path the ROS env already uses, so the profile install adds nothing on a machine with the shells.
- `uwrt fw` and titan_firmware's `.envrc` come with the firmware shell (Phase 4).

## colcon arguments

`COLCON_DEFAULTS_FILE` (from `nix/colcon.nix`) gives `colcon build` its `--cmake-args`: RelWithDebInfo, compile_commands.json, link-path install rpaths, gnu17 C, CMake policy floor 3.5 and, on macOS, absolute install names. **colcon replaces that list when you pass `--cmake-args` yourself**, so `colcon build --cmake-args -DFOO=1` drops all of them (on macOS, msg packages' Python extensions then can't load their own libraries). If you need extra CMake options, repeat the defaults with them (they're listed in `$COLCON_DEFAULTS_FILE`). Installs are copies, not symlinks: edit a Python script, rebuild the package.

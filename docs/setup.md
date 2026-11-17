# Setting up a machine

From a fresh macOS or Linux machine to a workspace that loads its environment on `cd`. Do this once per
machine. The steps are the same on both systems except where a section says otherwise. NixOS isn't covered.

## 1. Prerequisites

- **macOS** (Apple silicon): the Command Line Tools, for git, clang and ssh: `xcode-select --install`. Their
  git has to be 2.45 or newer (`git --version`); see [riptide_control on macOS](#riptide_control-on-macos).
- **Linux** (x86_64 or aarch64): any distribution with systemd. An apt ROS install can stay; see
  [Linux](#linux).
- A GitHub SSH key with access to the osu-uwrt organization. notgroot is private, so the flake fetches it over
  ssh, and some team repos are cloned over ssh.

## 2. Install Nix

Use the NixOS community installer ([github.com/NixOS/nix-installer](https://github.com/NixOS/nix-installer)),
the same on macOS and Linux:

```sh
curl --proto '=https' --tlsv1.2 -sSfL https://artifacts.nixos.org/nix-installer | sh -s -- install --enable-flakes
```

It creates the `/nix` volume on macOS, runs the daemon, and keeps its own settings in `/etc/nix/nix.conf` and
yours in `/etc/nix/nix.custom.conf`. On macOS it also adds a boot job that puts Nix back into `/etc/zshrc`
after macOS updates overwrite it. Open a new terminal afterwards. `nix config show experimental-features`
must list `nix-command` and `flakes`.

If Nix is already installed some other way (for example nixos.org's `install` script, which has no
`nix.custom.conf`), keep it, and put the settings below in `/etc/nix/nix.conf` instead.

## 3. Binary caches

Without these, the first shell compiles for hours instead of downloading.

| Cache | Has |
|---|---|
| `ros.cachix.org` | nix-ros-overlay's Linux builds |
| `ros-darwin.cachix.org` | nix-ros-overlay's macOS builds (ros-base and its dependencies) |
| `uwrt.cachix.org` | upstream uwrt_nix's firmware tools (Rust, pico-sdk), for the firmware shell |

Add them to `/etc/nix/nix.custom.conf` (installer upgrades leave it alone):

```
extra-substituters = https://ros.cachix.org https://ros-darwin.cachix.org https://uwrt.cachix.org
extra-trusted-public-keys = ros.cachix.org-1:dSyZxI8geDCJrwgvCOHDoAfOm5sV1wCPjBkKL+38Rvo= ros-darwin.cachix.org-1:2czU3rRAUlPoUSW6Gaj+oBLj5wGAi9lWrNldgoQF/PM= uwrt.cachix.org-1:8jsEBONNUB05TKTqyzw8rWFHZ8cKaBc4PagJJI09qco=
trusted-substituters = https://cache.nixos.org https://ros.cachix.org https://ros-darwin.cachix.org https://uwrt.cachix.org
```

Edit it with `sudo` (`sudo nano /etc/nix/nix.custom.conf`), copying the lines exactly. A line Nix can't parse
breaks every `nix` command until it's fixed. Then restart the daemon:

```sh
sudo launchctl kickstart -k system/org.nixos.nix-daemon   # macOS
sudo systemctl restart nix-daemon                          # Linux
nix config show substituters                               # should list all three
```

The keys are the same ones `flake.nix` names in `nixConfig`. The other way to get them, upstream uwrt_nix's,
is `trusted-users = root <you>` plus `accept-flake-config = true`, which lets the flake add its own caches.
That works too, but a trusted user can change any daemon setting, so the explicit list is preferred.

## 4. macOS: open file limit

colcon and Nix open more files than macOS's default limit (256) allows. The `uwrt` package ships a
LaunchDaemon that raises it at every boot. Install it once `uwrt` is in your profile (step 7):

```sh
sudo cp ~/.nix-profile/share/uwrt/limit.maxfiles.plist /Library/LaunchDaemons/
sudo launchctl load -w /Library/LaunchDaemons/limit.maxfiles.plist
launchctl limit maxfiles    # 65536 524288
```

New terminals pick up the new limit.

## 5. direnv and rsync

direnv loads a directory's environment when you `cd` in, and nix-direnv caches it so later loads are instant.
GNU rsync is needed by `colcon deploy` (macOS's `/usr/bin/rsync` is openrsync, which lacks flags it uses).

```sh
nix profile add nixpkgs#direnv nixpkgs#nix-direnv nixpkgs#rsync
mkdir -p ~/.config/direnv
echo 'source "$HOME/.nix-profile/share/nix-direnv/direnvrc"' >> ~/.config/direnv/direnvrc
```

Hook direnv into your shell, then open a new terminal:

| Shell | Add this line | To |
|---|---|---|
| zsh (macOS default) | `eval "$(direnv hook zsh)"` | `~/.zshrc` |
| bash | `eval "$(direnv hook bash)"` | `~/.bashrc` |

On macOS the Nix profile comes ahead of Homebrew and `/usr/bin` on PATH, so `which rsync` should be under
`~/.nix-profile/bin`.

## 6. Clone the repositories

Everything lives under `~/osu-uwrt`. Other locations work if you set them in `~/.uwrt/env` before step 7
(`UWRT_NIX`, `UWRT_DEV_WS`, `UWRT_RELEASE_WS`, `UWRT_FW_DIR`; see [sourcing.md](sourcing.md)).

| Path | What | Shell |
|---|---|---|
| `uwrt_nix` | this repo | |
| `development/software` | the dev colcon workspace, repos in `src/` | `riptide-dev` |
| `release` | `osu-uwrt/riptide_release`, a colcon workspace with the repos as submodules | `riptide-release` |
| `development/titan_firmware` | firmware | `firmware` |
| `notgroot` | the behavior tree editor (its own `./build.sh` works in `riptide-dev`) | |

You only need the workspaces you work in. `uwrt setup` skips the ones that aren't there.

```sh
mkdir -p ~/osu-uwrt/development/software/src && cd ~/osu-uwrt
git clone git@github.com:osu-uwrt/uwrt_nix.git
cd uwrt_nix && git checkout nix-macos && cd ..

# dev workspace: the repos you work on (riptide_setup's dev_install/riptide.repos lists them).
# the core ones with the macOS fixes are on nix-macos until those merge
cd development/software/src
for r in riptide_autonomy riptide_core nereus; do git clone -b nix-macos git@github.com:osu-uwrt/$r.git; done
git clone -b nix-macos --ref-format=reftable git@github.com:osu-uwrt/riptide_control.git   # see below
for r in riptide_launch riptide_perception riptide_gui; do git clone git@github.com:osu-uwrt/$r.git; done
cd ~/osu-uwrt

# release
git -c init.defaultRefFormat=reftable clone --recurse-submodules git@github.com:osu-uwrt/riptide_release.git release

# firmware
git clone -b nix-macos --recurse-submodules git@github.com:osu-uwrt/titan_firmware.git development/titan_firmware

git clone -b nix-macos git@github.com:osu-uwrt/notgroot.git
```

The dev workspace doesn't need `dependencies/` from riptide.repos: chameleon_tf, nortek_dvl and the ZED
interfaces come from the flake. Packages the shells can't build on any platform (c_simulator, camera_faker,
riptide_rviz) are skipped by `nix/skip.nix`, so cloning them does no harm.

**Release on macOS.** riptide_release's `master` points its submodules at commits without the macOS fixes.
Move these to their `nix-macos` branches:

```sh
cd ~/osu-uwrt/release/src
for r in riptide_control riptide_core riptide_autonomy nortek_dvl; do git -C $r fetch origin nix-macos && git -C $r checkout nix-macos; done
git -C apriltag_ros remote add uwrt https://github.com/osu-uwrt/apriltag_ros.git
git -C apriltag_ros fetch uwrt nix-macos && git -C apriltag_ros checkout -b nix-macos uwrt/nix-macos
touch opbox_software/COLCON_IGNORE   # its Nix fixes aren't on GitHub yet; this goes for Linux too
```

### riptide_control on macOS

osu-uwrt/riptide_control has both an `MPC` and an `mpc` branch. On macOS's case-insensitive disk their ref
files collide and fetches fail. Cloning with git's reftable ref storage (`--ref-format=reftable`, or
`init.defaultRefFormat=reftable` for release's submodules) keeps ref names case-sensitive. It needs git 2.45+,
and tools built on libgit2 (some editor git panels) can't read these repos. Linux clones don't need it.
`uwrt doctor` checks the git version against any reftable repo in the workspaces.

## 7. Install `uwrt` and write the .envrc files

```sh
nix profile add ~/osu-uwrt/uwrt_nix#uwrt   # uwrt and uwrt-env, on PATH everywhere
uwrt setup                                 # .envrc in each workspace and titan_firmware, then direnv allow
uwrt doctor                                # every line should be ok
```

`uwrt setup` also writes `~/.config/direnv/direnv.toml` (quiet `cd`s) if you don't have one. The `.envrc`
files are untracked. In release and titan_firmware they go in `.git/info/exclude`.

For tab completion of `ros2`, `colcon` and `uwrt` in zsh, and a `(riptide-dev)` prompt tag, add the lines in
[sourcing.md](sourcing.md), "Shell niceties (zsh)", to `~/.zshrc`.

## 8. First run

```sh
cd ~/osu-uwrt/development/software   # prints "Activating riptide-dev"
uwrt build                           # colcon build, plus a merged compile_commands.json
ros2 pkg list | grep riptide
```

The first `cd` evaluates the workspace's dependencies and fetches them. On a fresh Mac about 100 core ROS
packages build locally (about 8 minutes) because of macOS fixes in `nix/overlay.nix`. Later `cd`s take
under a second. The simulator: [riptide-tools.md](riptide-tools.md), "nereus' ROS bridge and viewer".

Release works the same way (`cd ~/osu-uwrt/release`). For firmware, `cd ~/osu-uwrt/development/titan_firmware`
loads the firmware shell; building and uploading are in [firmware.md](firmware.md).

From anywhere, `uwrt dev`, `uwrt release` and `uwrt fw` open a shell in that workspace's environment.

Local work uses the `fastdds-local` RMW on macOS. Linux defaults to `zenoh`, which needs the robot's router.
Switch with `uwrt rmw` ([sourcing.md](sourcing.md), "RMW").

## Linux

- **apt ROS.** If `~/.bashrc` sources `/opt/ros` or apt-built workspaces, they leak into Nix shells.
  `uwrt setup --patch-bashrc --dry-run` shows how it would guard them, and without `--dry-run` it applies the
  change. See [sourcing.md](sourcing.md), "Linux: coexisting with apt ROS".
- **OpenGL.** Nix programs on non-NixOS Linux need nixGL for the nereus viewer and notgroot; the shells set it
  up ([riptide-tools.md](riptide-tools.md), "Linux (non-NixOS): nixGL").
- **Big messages on fastdds-local** need `net.core.rmem_max`/`wmem_max` raised ([sourcing.md](sourcing.md),
  "RMW").

## Editors

GUI apps don't load your shell's environment. Start VS Code from a terminal inside the workspace
(`cd ~/osu-uwrt/development/software && code .`), or use a direnv extension, so builds, clangd and the
terminal see the workspace's env. For clangd's
`--query-driver` setting see [sourcing.md](sourcing.md), "Editors".

## Updating

```sh
cd ~/osu-uwrt/uwrt_nix && git pull
nix profile upgrade uwrt              # uwrt doctor warns while the profile copy is older than the checkout
```

The next `cd` into a workspace re-evaluates on its own. A uwrt_nix change can move the ROS env, which leaves
already-built packages pointing at the old one. `uwrt build` names them and gives the command
(`uwrt build --cmake-clean-cache --packages-select …`).

## Troubleshooting

| Problem | Fix |
|---|---|
| Anything | `uwrt doctor` |
| `nix: command not found` after a macOS update | the update reset `/etc/zshrc`: `sudo /nix/nix-installer repair`, then a new terminal |
| `cannot connect to socket` | `sudo launchctl kickstart -k system/org.nixos.nix-daemon` (macOS), `sudo systemctl restart nix-daemon` (Linux) |
| `cd` loads nothing | `direnv status`; `direnv allow` after an `.envrc` changed; `uwrt setup` if it's missing |
| A new package's dependencies are missing | `direnv reload` (a new package.xml or `COLCON_IGNORE` isn't watched) |
| `uwrt_nix: unknown rosdep keys` | a package.xml names a key Nix can't resolve: add it to `deps/team-keys.json`, or `uwrt deps update` |
| A file you added to uwrt_nix isn't seen | the flake only sees files git knows about: `git add` it |
| First load compiles for a long time | the caches in step 3 aren't active: `nix config show substituters` |
| Disk full | `nix profile wipe-history --older-than 30d && nix store gc`, then `uwrt build` for packages it names |
| Effective Nix settings | `nix config show` |

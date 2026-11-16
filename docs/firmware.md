# The firmware shell

`devShells.firmware` is for titan_firmware: the Arm toolchain, the micro-ROS library, titan's host tools and the
micro-ROS agent. It is upstream [osu-uwrt/uwrt_nix](https://github.com/osu-uwrt/uwrt_nix)'s `firmware` shell
plus what that one doesn't have yet:

| From upstream uwrt_nix | Added here |
|---|---|
| Arm GCC 13.3 (`arm-none-eabi-*`, including gdb), cmake, ninja, python3, git | openocd 0.12 |
| pico-sdk 1.5.1 (`PICO_SDK_PATH`) | `upload_tool`, `canmore_cli` (built from titan_firmware) |
| libmicroros (`MICRO_ROS_LIB_DIR`), cached on uwrt.cachix.org | `micro_ros_agent` (the team's fork) |
| Rust with `thumbv6m-none-eabi`, picotool, probe-rs, just, screen, libusb | `uwrt`, `UWRT_UPLOAD_TOOL` |

## Getting in

`uwrt setup` writes `titan_firmware/.envrc` (it looks in `~/osu-uwrt/development/titan_firmware`, or
`UWRT_FW_DIR` in `~/.uwrt/env`), so `cd` into the checkout loads the shell. From anywhere, `uwrt fw` opens a
shell there, and `uwrt fw <cmd>` runs one command. Without direnv: `nix develop ~/osu-uwrt/uwrt_nix#firmware`.

uwrt.cachix.org has to be a trusted substituter (in `/etc/nix/nix.custom.conf` on a Mac), or the first load
builds libmicroros and the Rust toolchain from source.

## Building and uploading

Same as before, in a board's folder:

```sh
git submodule update --init --recursive   # once: pico-sdk and tinyusb (the shell warns when they're missing)
mkdir -p build && cd build && cmake .. && make -j
make upload                                # UWRT_UPLOAD_TOOL: the shell's upload_tool, nothing built in-tree
```

- **pico-sdk:** titan_firmware still builds against its own `lib/pico-sdk` submodule (`global_defs.cmake` sets
  it). The shell's `PICO_SDK_PATH` is the same 1.5.1 tag, for other repositories.
- **micro-ROS library:** `MICRO_ROS_LIB_DIR` points at upstream's library, built from master's `colcon.meta`
  (15 publishers and 15 subscriptions). The Docker-built `lib/micro_ros_pico/libmicroros` from
  `poac-multiple-servos` had 25 of each. To use a local library, `unset MICRO_ROS_LIB_DIR` or pass
  `-DMICRO_ROS_LIB_DIR=<dir>` to cmake.
- **Compiler:** GCC 13. GCC 14 and 15 fail to link titan_bootloader (`boot_app.c:44`, a Thumb call to the
  linker-script symbol `__boot_trampoline_entry__`). App code is 2–5% smaller than with jammy's GCC 10.

## The micro-ROS agent

`micro_ros_agent serial --dev /dev/cu.usbmodem…` (or `udp4 -p 8888`). It takes `ROS_DOMAIN_ID` and the
fastdds-local profile from `uwrt-env`, like the workspaces, and always runs on Fast DDS, whatever `uwrt rmw`
says. CAN (`micro_ros_agent can`) is Linux only until the CAN transport work in Phase 5.

## Checking without hardware

[firmware_simulator](https://github.com/osu-uwrt/firmware_simulator) runs the C images. A board with micro-ROS
over USB exposes its second CDC port as a pty that the agent can open:

```sh
firmware_simulator run IVCBoard2_with_bl.uf2 --board boards/talos/ivc_board.toml \
  --usb-cdc pty:/tmp/ivc-log --usb-cdc2 pty:/tmp/ivc-ros --realtime --time 120s
micro_ros_agent serial --dev /tmp/ivc-ros
```

`--realtime` matters: without it the emulator runs several times faster than the wall clock and is gone
before `ros2` gets to it.

## macOS limits

- No SocketCAN: `upload_tool`, `canmore_cli` and the agent reach boards over USB, Ethernet and serial only.
  CAN through gs_usb/slcan adapters is Phase 5.
- titan_firmware, titan_canmore and the agent's Micro-XRCE-DDS-Agent come from local `nix-macos` branches
  (`git+file` inputs) until those are pushed.

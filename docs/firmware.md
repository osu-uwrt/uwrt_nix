# The firmware shell

`devShells.firmware` is for titan_firmware: the Arm toolchain, the micro-ROS library, titan's host tools and the
micro-ROS agent. It is upstream [osu-uwrt/uwrt_nix](https://github.com/osu-uwrt/uwrt_nix)'s `firmware` shell
plus what that one doesn't have yet:

| From upstream uwrt_nix | Added here |
|---|---|
| Arm GCC 13.3 (`arm-none-eabi-*`, including gdb), cmake, ninja, python3, git | openocd 0.12 |
| pico-sdk 1.5.1 (`PICO_SDK_PATH`) | `upload_tool`, `canmore_cli`, `canmore_can` (built from titan_firmware) |
| libmicroros's recipe (rebuilt here with titan's `colcon.meta`) | `micro_ros_agent` (the team's fork) |
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
- **micro-ROS library:** `MICRO_ROS_LIB_DIR` points at upstream's libmicroros recipe built with titan_firmware's
  own `colcon.meta` (`nix/libmicroros.nix`), so the entity limits follow titan: 25 publishers and 25
  subscriptions, like the Docker-built library on the robot (some boards fault with master's 15). It isn't on
  uwrt.cachix.org, so the first load builds it (about a minute). To use a local library, `unset
  MICRO_ROS_LIB_DIR` or pass `-DMICRO_ROS_LIB_DIR=<dir>` to cmake.
- **Compiler:** GCC 13. GCC 14 and 15 fail to link titan_bootloader (`boot_app.c:44`, a Thumb call to the
  linker-script symbol `__boot_trampoline_entry__`). App code is 2–5% smaller than with jammy's GCC 10.

## The micro-ROS agent

The shell has no `ros2`, so the agent is a plain command on PATH instead of `ros2 run micro_ros_agent
micro_ros_agent`, with the same arguments:

```sh
micro_ros_agent serial --dev /dev/cu.usbmodem103   # -v4 to watch the session and entities get created
```

A board with micro-ROS over USB shows up as two ports: the lower-numbered one is its log, the other is micro-ROS
(e.g. `usbmodem101` and `usbmodem103`). `udp4 -p 8888` works too. It takes the
fastdds-local profile from `uwrt-env`, like the workspaces, and always runs on Fast DDS, whatever `uwrt rmw`
says. Over CAN: `micro_ros_agent can -D <bus>`, where the bus is anything from [CAN](#can) (`can0`, `gsusb0`, ...).

## CAN

titan_canmore's `CANTransport` opens a bus from a spec, so the same tools work on Linux and macOS:

| Spec | What |
|---|---|
| `can0`, `vcan0` | SocketCAN (Linux). The rate comes from `ip link`, as before |
| `gsusb[:<serial>][#<ch>][@<rate>]` | gs_usb/candleLight adapter over libusb (CANable 2 with candleLight FD firmware) |
| `slcan:<port>[@<rate>]` | slcan adapter (CANable 2 with its slcan FD firmware), e.g. `slcan:/dev/cu.usbmodem1234` |
| `cannelloni:<host>:<port>[@<rate>]` | cannelloni over UDP, e.g. firmware_simulator's `--cannelloni` hub |
| `gsusb0`, `slcan0`, ... | a bus brought up with `canmore_can up` |

Rates: `@1M/5M` for the internal CAN FD bus, `@250k` for the external bus. On a CAN FD bus the adapter runs CAN
FD, but the tools send classic frames unless the spec ends in `+fd`: titan_firmware's boards only take classic
CANmore frames. SocketCAN keeps sending CAN FD on an interface with a CAN FD MTU.

On a Mac, bring an adapter up once per plug-in, like `ip link set can0 up` on Linux:

```sh
canmore_can list                 # adapters and buses
canmore_can up gsusb             # finds the rate itself (listen-only: 1M/5M, then 250k), or give it: gsusb@250k
upload_tool <image>.uf2          # finds gsusb0, like it finds can0
canmore_cli
micro_ros_agent can -D gsusb0
canmore_can down gsusb0
```

`up` owns the adapter and serves the bus on a localhost cannelloni hub, so several tools share it. Without it, a
tool can open an adapter itself through `CANMORE_CAN=gsusb@1M/5M` (one process per adapter). `canmore_can dump
<bus> --pcap -` feeds Wireshark/tshark; titan_firmware's `tools/canmore_dissector.lua` decodes it with Decode As
→ CAN next level dissector → CANMORE. python-can's `slcan` and `gs_usb` interfaces work too.

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

Over CAN, a robot file's bus served as a cannelloni hub is a bus like any other:

```sh
firmware_simulator robot robots/talos_c.toml --cannelloni internal=127.0.0.1:20000 --realtime --time 3600s
CANMORE_CAN=cannelloni:127.0.0.1:20000@1M/5M upload_tool talos/PoacBoard/build/poac_board_ota.uf2
micro_ros_agent can -D cannelloni:127.0.0.1:20000@1M/5M
```

The board picks the ROS domain, not the agent's `ROS_DOMAIN_ID`. The C boards use 0, which is also fastdds-local's
default (`UWRT_LOCAL_DOMAIN`), so `ros2` sees them unless you've moved off 0 or a board is rebuilt with another one.

## macOS limits

- No SocketCAN: CAN goes through gs_usb/slcan adapters (`canmore_can up`) or cannelloni, see [CAN](#can).

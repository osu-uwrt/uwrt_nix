# the firmware shell: upstream uwrt_nix's firmware shell (arm gcc 13, pico-sdk 1.5.1, libmicroros, rust with
# thumbv6m, picotool, probe-rs) plus what it lacks: openocd, titan's host tools, the micro-ros agent and uwrt.
# titan_firmware builds against its own lib/pico-sdk submodule (global_defs.cmake sets PICO_SDK_PATH), the
# shell's PICO_SDK_PATH is for other repos. titan's cmake reads MICRO_ROS_LIB_DIR and UWRT_UPLOAD_TOOL
{ pkgs, upstream, titanTools, uwrt, libmicroros, extraPackages ? [ ] }:
pkgs.mkShell {
  name = "firmware";
  inputsFrom = [ upstream ];
  packages = [ pkgs.openocd titanTools.upload-tool titanTools.canmore-cli uwrt ] ++ extraPackages;

  # inputsFrom brings the packages but not the variables
  inherit (upstream) PICO_SDK_PATH PICO_TOOLCHAIN_PATH CMAKE_POLICY_VERSION_MINIMUM;
  # ours, not upstream's: built with titan_firmware's colcon.meta (nix/libmicroros.nix)
  MICRO_ROS_LIB_DIR = "${libmicroros}";
  UWRT_UPLOAD_TOOL = "${titanTools.upload-tool}/bin/upload_tool";
  UWRT_NIX_SHELL = "firmware";

  shellHook = ''
    echo "Activating firmware" >&2
    # titan_firmware can't build without its submodules (pico-sdk, and tinyusb inside it)
    if _top=$(git rev-parse --show-toplevel 2>/dev/null) && [ -f "$_top/global_defs.cmake" ] \
      && ! { [ -f "$_top/lib/pico-sdk/external/pico_sdk_import.cmake" ] && [ -f "$_top/lib/pico-sdk/lib/tinyusb/src/tusb.h" ]; }; then
      echo "firmware: submodules missing, run: git -C $_top submodule update --init --recursive" >&2
    fi
    unset _top
  '';
}

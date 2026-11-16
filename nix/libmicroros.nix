# upstream uwrt_nix's libmicroros, built with titan_firmware's own colcon.meta instead of upstream's copy of
# master's. titan's nix-macos branch has 25 publishers/subscriptions (user, 2026-11-16: at least one board faults
# with master's 15), so the library follows whatever titan's file says. not on uwrt.cachix.org, builds locally once
{ lib, upstream, titan_firmware }:
let
  meta = "${titan_firmware}/lib/micro_ros_pico/microros_static_library/library_generation/colcon.meta";
in
upstream.overrideAttrs (old:
  let
    # buildPhase passes `--metas <store path of upstream's colcon.meta>`, swap just that path
    parts = lib.splitString "--metas " old.buildPhase;
    upstreamMeta = builtins.head (lib.splitString " " (builtins.elemAt parts 1));
  in
  assert lib.length parts == 2 && lib.hasSuffix "colcon.meta" upstreamMeta;
  {
    buildPhase = lib.replaceStrings [ upstreamMeta ] [ meta ] old.buildPhase;
  })

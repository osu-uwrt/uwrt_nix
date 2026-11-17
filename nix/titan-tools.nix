# titan_firmware's host tools: upload_tool, canmore_cli and canmore_can. built from the titan_firmware input with
# upstream uwrt_nix's pico-sdk (the same 1.5.1 tag as the submodule) and the titan_canmore input put where the
# submodules go (the git inputs don't carry submodules). off linux they reach can through titan_canmore's
# gs_usb/slcan/cannelloni backends (canmore_can up), libusb for gs_usb
{ lib, pkgs, titan_firmware, titan_canmore, pico-sdk }:
let
  src = pkgs.runCommand "titan-firmware-tools-src" { } ''
    mkdir $out
    cp -r ${titan_firmware}/lib ${titan_firmware}/tools $out/
    chmod -R u+w $out
    rm -rf $out/lib/pico-sdk $out/lib/titan_canmore
    ln -s ${pico-sdk} $out/lib/pico-sdk
    cp -r ${titan_canmore} $out/lib/titan_canmore
  '';

  mkTool = name: pkgs.stdenv.mkDerivation {
    pname = lib.replaceStrings [ "_" ] [ "-" ] name;
    version = "0-unstable-${titan_firmware.shortRev or "dirty"}";
    inherit src;
    cmakeDir = "../tools/${name}";
    nativeBuildInputs = with pkgs; [ cmake pkg-config git ];
    # the tools find the repo root with git rev-parse
    postUnpack = "git init -q $sourceRoot";
    buildInputs = [ pkgs.libusb1 ];
    # pico-sdk 1.5.1's host libs still say cmake_minimum_required < 3.5
    cmakeFlags = [ "-DCMAKE_POLICY_VERSION_MINIMUM=3.5" ];
    meta = {
      description = "titan_firmware ${name}";
      mainProgram = name;
      platforms = lib.platforms.unix;
    };
  };
in {
  upload-tool = mkTool "upload_tool";
  canmore-cli = mkTool "canmore_cli";
  canmore-can = mkTool "canmore_can";
}

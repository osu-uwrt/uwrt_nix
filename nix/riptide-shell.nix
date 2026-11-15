# one riptide shell: the ros env for a workspace's package.xml deps, colcon_riptide's colcon,
# and on mac the DYLD_LIBRARY_PATH fix in every ros program.
# the workspace is $UWRT_WS (its src/ is scanned), or ~/<defaultWorkspace>. needs --impure
{ lib, pkgs, ros, colcon, skip, name, defaultWorkspace, extraRos ? [ ], tools ? [ ] }:
let
  darwin = pkgs.stdenv.hostPlatform.isDarwin;

  home = builtins.getEnv "HOME";
  wsVar = builtins.getEnv "UWRT_WS";
  ws = if wsVar != "" then wsVar else "${home}/${defaultWorkspace}";
  scanned = home != "" && builtins.pathExists "${ws}/src";
  deps = if scanned
    then import ./deps.nix { inherit lib pkgs ros skip; } "${ws}/src"
    else { deps = [ ]; skipped = [ ]; };

  base = with ros; [
    ament-cmake-core
    python-cmake-module
    ros-base
    rmw-fastrtps-cpp
    rmw-zenoh-cpp
    ros2launch
  ];

  # SIP strips DYLD_* through /bin/sh and /usr/bin/env, AMENT_PREFIX_PATH survives. rebuild it
  # from there in every wrapped program, so workspace libs in install/*/lib are found too
  dyld = ''
    _uwrt_d=; IFS=: read -ra _uwrt_p <<< "''${AMENT_PREFIX_PATH-}"
    for _uwrt_x in "''${_uwrt_p[@]}"; do if [ -d "$_uwrt_x/lib" ]; then _uwrt_d="''${_uwrt_d:+$_uwrt_d:}$_uwrt_x/lib"; fi; done
    export DYLD_LIBRARY_PATH="$_uwrt_d''${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
  '';

  env = ros.buildEnv {
    underlay = true;
    paths = lib.unique (base ++ deps.deps ++ extraRos);
    postBuild = lib.optionalString darwin ''
      rosWrapperArgs=(--run ${lib.escapeShellArg dyld})
    '';
  };
in
pkgs.mkShell {
  inherit name;
  packages = [ colcon.colcon env pkgs.rsync pkgs.openssh ] ++ tools;

  COLCON_DEFAULTS_FILE = colcon.defaultsFile;
  UWRT_NIX_SHELL = name;

  passthru = { inherit env; workspace = ws; };

  shellHook = if scanned then ''
    echo "${name}: deps from ${ws}/src${lib.optionalString (deps.skipped != [ ]) ", skipping ${lib.concatStringsSep " " deps.skipped}"}" >&2
  '' else ''
    echo "${name}: no workspace scanned (${if home == "" then "pure eval, use --impure" else "${ws}/src not found, set UWRT_WS"}), base ros only" >&2
  '';
}

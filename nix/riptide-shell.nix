# one riptide shell: the ros env for a workspace's package.xml deps, colcon_riptide's colcon,
# and on mac the DYLD_LIBRARY_PATH fix in every ros program.
# the workspace is $UWRT_WS (its src/ is scanned), or ~/<defaultWorkspace>. needs --impure
{ lib, pkgs, ros, colcon, skip, uwrt, tools, name, defaultWorkspace, extraRos ? [ ], nereusBuild ? false, buildTools ? tools }:
let
  darwin = pkgs.stdenv.hostPlatform.isDarwin;

  home = builtins.getEnv "HOME";
  wsVar = builtins.getEnv "UWRT_WS";
  ws = if wsVar != "" then wsVar else "${home}/${defaultWorkspace}";
  scanned = home != "" && builtins.pathExists "${ws}/src";
  deps = if scanned
    then import ./deps.nix { inherit lib pkgs ros skip; } "${ws}/src"
    else { deps = [ ]; skipped = [ ]; };
  skipped = lib.concatStringsSep " " deps.skipped;

  base = with ros; [
    ament-cmake-core
    python-cmake-module
    ros-base
    rmw-fastrtps-cpp
    rmw-zenoh-cpp
    ros2launch
  ];

  # SIP strips DYLD_* through /bin/sh and /usr/bin/env, AMENT_PREFIX_PATH survives. rebuild it
  # from there, so workspace libs in install/*/lib are found too
  dyld = ''
    _uwrt_d=; IFS=: read -ra _uwrt_p <<< "''${AMENT_PREFIX_PATH-}"
    for _uwrt_x in "''${_uwrt_p[@]}"; do if [ -d "$_uwrt_x/lib" ]; then _uwrt_d="''${_uwrt_d:+$_uwrt_d:}$_uwrt_x/lib"; fi; done
    export DYLD_LIBRARY_PATH="$_uwrt_d''${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
  '';

  env = ros.buildEnv {
    underlay = true;
    paths = lib.unique (base ++ deps.deps ++ extraRos);
  };

  # mac only: every program in the env again, wrapped to run the snippet above first. it goes
  # ahead of env on PATH. (buildEnv's own rosWrapperArgs is expanded unquoted, so it can't take it)
  dyldWrappers = pkgs.runCommand "${name}-dyld-wrappers" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
    mkdir -p $out/bin
    for f in ${env}/bin/*; do
      [ -f "$f" ] && [ -x "$f" ] || continue
      makeWrapper "$f" "$out/bin/$(basename "$f")" --run ${lib.escapeShellArg dyld}
    done
  '';
in
pkgs.mkShell ({
  inherit name;
  packages = lib.optional darwin dyldWrappers ++ [ colcon.colcon env uwrt tools.riptide-tools pkgs.rsync pkgs.openssh ]
    ++ lib.optionals nereusBuild [ pkgs.cmake pkgs.uv pkgs.pkg-config ];  # cmake: its hook puts buildInputs on CMAKE_PREFIX_PATH
  # nereus' ros-viewer preset (its build.sh) builds against these and the workspace, and notgroot's
  # build.sh against the rest
  buildInputs = lib.optionals nereusBuild (lib.unique (buildTools.nereusDeps ++ buildTools.notgrootDeps));

  COLCON_DEFAULTS_FILE = colcon.defaultsFile;
  FONTCONFIG_FILE = tools.fontsConf;
  UWRT_NIX_SHELL = name;
} // lib.optionalAttrs scanned {
  UWRT_SKIPPED = skipped;
} // lib.optionalAttrs nereusBuild {
  # build.sh's uv sync makes .venv from nix's python, never a downloaded one
  UV_PYTHON = "${pkgs.python3}/bin/python3";
  UV_PYTHON_DOWNLOADS = "never";
} // {
  passthru = { inherit env dyldWrappers; workspace = ws; };

  # apt ros and outer workspaces out first (see strip-apt.sh), then say what was scanned.
  # under direnv only the one Activating line, the scan detail is in uwrt doctor
  shellHook = ''
    _uwrt_own_env=${env} _uwrt_own_wrap=${if darwin then "${dyldWrappers}" else "none"}
    source ${./strip-apt.sh}
    echo "Activating ${name}" >&2
  '' + (if scanned then ''
    if [ -z "''${DIRENV_IN_ENVRC:-}" ]; then
      echo "${name}: deps from ${ws}/src${lib.optionalString (deps.skipped != [ ]) ", skipping ${skipped}"}" >&2
    fi
  '' else ''
    echo "${name}: no workspace scanned (${if home == "" then "pure eval, use --impure" else "${ws}/src not found, set UWRT_WS"}), base ros only" >&2
  '');
})

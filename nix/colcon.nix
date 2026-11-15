# colcon with colcon_riptide, and the defaults file every riptide shell points COLCON_DEFAULTS_FILE at
{ lib, pkgs, riptide_setup, skip }:
let
  py = pkgs.python3Packages;

  colcon-riptide = py.buildPythonPackage {
    pname = "colcon-riptide";
    version = lib.head (builtins.match ".*__version__ = '([^']+)'.*"
      (builtins.replaceStrings [ "\n" ] [ " " ] (builtins.readFile "${riptide_setup}/colcon_riptide/colcon_riptide/__init__.py")));
    src = "${riptide_setup}/colcon_riptide";
    pyproject = true;
    build-system = [ py.setuptools ];
    dependencies = [ py.colcon-core py.scantree py.fabric ];
    doCheck = false;
    pythonImportsCheck = [ "colcon_riptide" ];
  };

  colcon = pkgs.colcon.withExtensions [ colcon-riptide ];

  verbArgs = { packages-ignore = skip; };
  defaults = {
    # no symlink-install (the plan had it): symlinked install(PROGRAMS) scripts keep their source mode, and most
    # team scripts are 644 in git, so ros2 launch can't run them. the apt workflow copies (and chmods) them too
    build = verbArgs // {
      cmake-args = [
        "-DCMAKE_BUILD_TYPE=RelWithDebInfo"
        "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON"
        "-DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON"
        # match jammy's toolchain defaults: gcc 11 builds C as gnu17 (gcc 15 is c23, where
        # `void f()` means f(void)), and cmake 3.22 still took cmake_minimum_required < 3.5
        "-DCMAKE_C_STANDARD=17"
        "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
      ] ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
        # copied (not symlinked) dylibs keep @rpath ids, and a package's own libs aren't on its install rpath, so
        # e.g. a msg package's python extension can't find its generator_py lib. scripts start through
        # /usr/bin/env, so SIP drops DYLD_LIBRARY_PATH. absolute install names, like nix's own cmake hook gives
        "-DCMAKE_INSTALL_NAME_DIR=$<INSTALL_PREFIX>/lib"
      ];
    };
    test = verbArgs;
    list = verbArgs;
    graph = verbArgs;
    info = verbArgs;
  };
in {
  inherit colcon colcon-riptide;
  # yaml is a superset of json, colcon-defaults reads this fine
  defaultsFile = pkgs.writeText "colcon-defaults.yaml" (builtins.toJSON defaults);
}

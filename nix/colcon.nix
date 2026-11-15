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
    build = verbArgs // {
      symlink-install = true;
      cmake-args = [
        "-DCMAKE_BUILD_TYPE=RelWithDebInfo"
        "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON"
        "-DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON"
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

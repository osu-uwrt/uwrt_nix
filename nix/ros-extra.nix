# ros packages we need that aren't in rosdistro (replaces development/dependencies).
# sources are flake inputs so package.xml can be read at eval time without IFD.
# to edit one, clone it into the workspace's src, colcon's copy shadows this one
{ lib, sources }:
rosFinal: rosPrev:
let
  tagged = tags: xml: lib.unique (lib.concatMap (m: if lib.isList m then [ (lib.trim (lib.elemAt m 1)) ] else [ ])
    (builtins.split "<(${tags})[^>]*>([^<]+)</" xml));
  dashed = builtins.replaceStrings [ "_" ] [ "-" ];

  # extra: deps CMakeLists find_package()s but package.xml forgets (apt's global /opt/ros hid
  # these). they go into package.xml too, rosidl checks it for action_msgs
  mkPackage = src: extra:
    let
      xml = builtins.readFile "${src}/package.xml";
      field = f: lib.head (builtins.match ".*<${f}[^>]*>[[:space:]]*([^<]*[^<[:space:]])[[:space:]]*</${f}>.*" (builtins.replaceStrings [ "\n" ] [ " " ] xml));
      name = field "name";
      pkgs = keys: map (k: rosFinal.${dashed k}) keys;
      buildType = let t = builtins.match ".*<build_type>([^<]+)</build_type>.*" (builtins.replaceStrings [ "\n" ] [ " " ] xml);
        in if t == null then "ament_cmake" else lib.head t;
    in rosFinal.buildRosPackage {
      pname = "ros-${rosFinal.ros-environment.rosDistro}-${dashed name}";
      version = field "version";
      inherit src buildType;
      postPatch = lib.optionalString (extra != [ ]) ''
        substituteInPlace package.xml --replace-fail "<buildtool_depend>ament_cmake</buildtool_depend>" \
          "<buildtool_depend>ament_cmake</buildtool_depend>${lib.concatMapStrings (d: "<depend>${d}</depend>") extra}"
      '';
      nativeBuildInputs = pkgs (tagged "buildtool_depend|buildtool_export_depend" xml);
      propagatedBuildInputs = pkgs (tagged "depend|build_depend|build_export_depend|exec_depend" xml ++ extra);
      doCheck = false;
      meta.description = field "description";
    };
in {
  chameleon-tf = mkPackage "${sources.chameleon_tf}/chameleon_tf" [ ];
  chameleon-tf-msgs = mkPackage "${sources.chameleon_tf}/chameleon_tf_msgs" [ "action_msgs" "geometry_msgs" ];
  nortek-dvl = mkPackage "${sources.nortek_dvl}/nortek_dvl" [ "rosidl_default_generators" "sensor_msgs" ];
  nortek-dvl-msgs = mkPackage "${sources.nortek_dvl}/nortek_dvl_msgs" [ ];
  # msgs only, for the nereus viewer's svo recording. the zed wrapper itself is skipped
  zed-interfaces = mkPackage "${sources.zed_interfaces}" [ "ament_cmake_auto" ];
}

# the team's micro-ros agent (osu-uwrt/micro-ROS-agent-impl on Micro-XRCE-DDS-Agent's Happyxrce branch, plus the
# local nix-macos fmt fix), on the
# dev pin's ros with its system fastdds, like build_agent.bash + meta.meta build it on the robot.
# riptide_msgs2 comes from upstream uwrt_nix's riptide-core input, the same revision its libmicroros uses, so the
# boards and the agent agree on the messages. the socketcan transport is linux only (the fork turns it off on
# darwin), so on macos the agent does serial and udp until phase 5
{ lib, pkgs, ros, riptide-core, titan_canmore, microxrcedds_agent }:
let
  riptide-msgs2 = ros.buildRosPackage {
    pname = "ros-humble-riptide-msgs2";
    version = "0-unstable-${builtins.substring 0 8 riptide-core.rev}";
    src = riptide-core;
    sourceRoot = "source/riptide_msgs";
    buildType = "ament_cmake";
    nativeBuildInputs = with ros; [ ament-cmake rosidl-default-generators ];
    propagatedBuildInputs = with ros; [ action-msgs geometry-msgs std-msgs sensor-msgs rosidl-default-runtime ];
  };

  titan-canmore = ros.buildRosPackage {
    pname = "ros-humble-titan-canmore";
    version = "0-unstable-${titan_canmore.shortRev or "dirty"}";
    src = titan_canmore;
    buildType = "ament_cmake";
    nativeBuildInputs = [ ros.ament-cmake ];
  };

  # the agent's own micro_ros_msgs (3.0.1), the overlay's is older
  micro-ros-msgs = ros.buildRosPackage {
    pname = "ros-humble-micro-ros-msgs";
    version = "3.0.1";
    src = pkgs.fetchFromGitHub {
      owner = "micro-ROS";
      repo = "micro_ros_msgs";
      rev = "10be4d005fbc7d8dd60dbb213b65f4171419bfe9";
      hash = "sha256-B/8PIUtwmLcaTwYHgqEg2McXwtaPhNx6UZe2sJtAQuw=";
    };
    buildType = "ament_cmake";
    nativeBuildInputs = with ros; [ ament-cmake rosidl-default-generators ];
    propagatedBuildInputs = [ ros.rosidl-default-runtime ];
  };

  microxrcedds-agent = ros.buildRosPackage {
    pname = "ros-humble-microxrcedds-agent";
    version = "0-unstable-${microxrcedds_agent.shortRev or "dirty"}";
    src = microxrcedds_agent;
    buildType = "ament_cmake";
    nativeBuildInputs = [ ros.ament-cmake ];
    propagatedBuildInputs = (with ros; [
      fastrtps fastcdr rcl rosidl-runtime-cpp rosidl-typesupport-cpp rosidl-typesupport-fastrtps-cpp std-msgs
    ]) ++ [ pkgs.spdlog riptide-msgs2 titan-canmore ];
    # meta.meta's flags, minus the superbuild (no network in the sandbox)
    cmakeFlags = [
      "-DUAGENT_SUPERBUILD=OFF"
      "-DUAGENT_USE_SYSTEM_FASTDDS=ON"
      "-DUAGENT_USE_SYSTEM_FASTCDR=ON"
      "-DUAGENT_USE_SYSTEM_LOGGER=ON"
      "-DUAGENT_CED_PROFILE=OFF"
      "-DUAGENT_P2P_PROFILE=OFF"
      "-DUAGENT_BUILD_EXECUTABLE=OFF"
      "-DUAGENT_ISOLATED_INSTALL=OFF"
    ];
  };

  agent = ros.buildRosPackage {
    pname = "ros-humble-micro-ros-agent";
    version = "0-unstable-bf1c950";
    src = pkgs.fetchFromGitHub {
      owner = "osu-uwrt";
      repo = "micro-ROS-agent-impl";
      rev = "bf1c9502ba2e2bd3bdc560b38e333d1fb957faa0";
      hash = "sha256-yEyvIOY/Se2N1hEvCUwSyGJbpD33ySLVQQPBYlGXizo=";
    };
    sourceRoot = "source/micro_ros_agent";
    buildType = "ament_cmake";
    # its cmake asks for the lint/gtest packages even with tests off
    nativeBuildInputs = with ros; [ ament-cmake rosidl-cmake ament-lint-auto ament-cmake-gtest ];
    # propagated so the env below gets them (rmw_dds_common's typesupport, the msgs)
    propagatedBuildInputs = with ros; [
      fastcdr fastrtps fastrtps-cmake-module rmw-dds-common rmw rcutils rmw-fastrtps-shared-cpp rcl std-msgs
      rosidl-typesupport-fastrtps-cpp rosidl-runtime-cpp rosidl-typesupport-cpp
    ] ++ [ microxrcedds-agent micro-ros-msgs riptide-msgs2 titan-canmore ];
    cmakeFlags = [ "-DMICROROSAGENT_SUPERBUILD=OFF" "-DBUILD_TESTING=OFF" ];
  };

  # rcl and rosidl dlopen the rmw and the typesupport libs (rmw_dds_common's for the graph manager) from
  # AMENT_PREFIX_PATH (rcpputils), so the agent runs on a ros env of its own closure
  env = ros.buildEnv { paths = [ agent ros.rmw-fastrtps-cpp ]; };
in
# ros installs it under lib/ for `ros2 run`. the firmware shell has no ros, so this puts it on PATH with its env.
# the agent only bridges into fast dds, so it stays on that rmw whatever `uwrt rmw` says
pkgs.runCommand "micro-ros-agent-${agent.version}" {
  nativeBuildInputs = [ pkgs.makeWrapper ];
  passthru = { inherit agent env riptide-msgs2 microxrcedds-agent micro-ros-msgs titan-canmore; };
  meta = {
    description = "UWRT's micro-ROS agent";
    mainProgram = "micro_ros_agent";
  };
} ''
  makeWrapper ${agent}/lib/micro_ros_agent/micro_ros_agent $out/bin/micro_ros_agent \
    --set AMENT_PREFIX_PATH ${env} \
    --set RMW_IMPLEMENTATION rmw_fastrtps_cpp
''

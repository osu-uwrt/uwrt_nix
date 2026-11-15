{
  inputs = {
    # both pinned to master with darwin support (#913), bump on purpose
    nix-ros-overlay.url = "github:lopsided98/nix-ros-overlay/971fa9ca86c79a4997e7c6b2f9df0cb754e7256a";
    nix-ros-overlay-release.url = "github:lopsided98/nix-ros-overlay/971fa9ca86c79a4997e7c6b2f9df0cb754e7256a";
    nixpkgs.follows = "nix-ros-overlay/nixpkgs";  # IMPORTANT!!!
  };
  outputs = { self, nix-ros-overlay, nix-ros-overlay-release, nixpkgs }:
    nix-ros-overlay.inputs.flake-utils.lib.eachSystem [ "aarch64-darwin" "x86_64-linux" "aarch64-linux" ] (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ nix-ros-overlay.overlays.default ];
        };
        lib = pkgs.lib;
        ros = pkgs.rosPackages.humble;

        # phase 0 spike, temporary. gets replaced by the real shells in phase 1
        spikeRos = with ros; {
          inherit ros-base rclcpp rclpy rmw-fastrtps-cpp rmw-zenoh-cpp rosbag2 cv-bridge tf2-ros
            image-transport behaviortree-cpp-v3 robot-localization apriltag-ros control-toolbox
            tf-transformations xacro robot-state-publisher joint-state-publisher diagnostic-updater
            vision-msgs pluginlib;
        };
        spikePy = { inherit (pkgs.python3Packages) pybullet transforms3d fabric; };
        spikeFw = { inherit (pkgs) gcc-arm-embedded-13 gcc-arm-embedded-14 openocd; };

        # drop whatever won't eval on this platform so the shell still loads
        evals = p: (builtins.tryEval p.drvPath).success;
        avail = lib.filterAttrs (_: evals);
        dropped = lib.attrNames (lib.filterAttrs (_: p: !evals p) (spikeRos // spikePy // spikeFw));
      in {
        legacyPackages.spike = spikeRos // spikePy // spikeFw;

        devShells.spike = pkgs.mkShell {
          name = "uwrt-spike";
          packages = [
            (pkgs.colcon.withExtensions [ pkgs.python3Packages.colcon-alias ])
            (ros.buildEnv {
              underlay = true;
              paths = lib.attrValues (avail spikeRos) ++ lib.attrValues (avail spikePy);
            })
          ] ++ lib.attrValues (avail spikeFw);
          shellHook = lib.optionalString (dropped != [ ]) ''
            echo "spike: not available on ${system}: ${lib.concatStringsSep " " dropped}" >&2
          '';
        };
      });
  nixConfig = {
    extra-substituters = [ "https://ros.cachix.org" "https://ros-darwin.cachix.org" ];
    extra-trusted-public-keys = [
      "ros.cachix.org-1:dSyZxI8geDCJrwgvCOHDoAfOm5sV1wCPjBkKL+38Rvo="
      "ros-darwin.cachix.org-1:2czU3rRAUlPoUSW6Gaj+oBLj5wGAi9lWrNldgoQF/PM="
    ];
  };
}

# darwin fixes for upstream ros packages, plus ros-extra (ros packages not in rosdistro)
{ rosDistro ? "humble", sipFixes ? true, rosExtra ? null }:
final: prev:
let
  lib = prev.lib;
  darwin = prev.stdenv.hostPlatform.isDarwin;
in {
  rosPackages = prev.rosPackages // {
    ${rosDistro} = (prev.rosPackages.${rosDistro}.overrideScope (rosFinal: rosPrev: lib.optionalAttrs darwin {
      # upstream only guards _WIN32, so libcap/sched_fifo/affinity get used on mac too
      realtime-tools = rosPrev.realtime-tools.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./patches/realtime-tools-darwin.patch ];
      });

      # clang -Werror=format-security on RCLCPP_ERROR(logger, e.what())
      compressed-depth-image-transport = rosPrev.compressed-depth-image-transport.overrideAttrs (old: {
        env = (old.env or { }) // {
          NIX_CFLAGS_COMPILE = toString (old.env.NIX_CFLAGS_COMPILE or "") + " -Wno-error=format-security";
        };
      });

      # camera_ros is only for apriltag_ros' example launch and needs libcamera (linux only)
      apriltag-ros = rosPrev.apriltag-ros.overrideAttrs (old: {
        propagatedBuildInputs = lib.filter (p: (p.pname or "") != "ros-${rosDistro}-camera-ros") old.propagatedBuildInputs;
      });
    } // lib.optionalAttrs (darwin && sipFixes) {
      # libyaml.dylib's id is @rpath/libyaml.dylib and nothing linking it has an LC_RPATH,
      # so rcl/rclpy/every node only loads with DYLD_LIBRARY_PATH set. give it an absolute id
      libyaml-vendor = rosPrev.libyaml-vendor.overrideAttrs (old: {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.fixDarwinDylibNames ];
      });

      # libzenohc.dylib's id is its path in the build sandbox, rmw_zenoh only found it by leaf name
      zenoh-cpp-vendor = rosPrev.zenoh-cpp-vendor.overrideAttrs (old: {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.fixDarwinDylibNames ];
      });

      # rmw/SharedLibrary dlopen only searches DYLD_LIBRARY_PATH, which SIP strips through /bin/sh
      rcpputils = rosPrev.rcpputils.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./patches/rcpputils-ament-prefix-path.patch ];
      });
    })).overrideScope (if rosExtra == null then (_: _: { }) else import ./ros-extra.nix { inherit lib; sources = rosExtra; });
  };
}

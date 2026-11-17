# darwin fixes for upstream ros (and python) packages, plus ros-extra (ros packages not in rosdistro)
{ rosDistro ? "humble", sipFixes ? true, rosExtra ? null }:
final: prev:
let
  lib = prev.lib;
  darwin = prev.stdenv.hostPlatform.isDarwin;
in {
  # mac builds aren't sandboxed, so test_data_utils really downloads coco8-pose.zip, which 404s now.
  # hydra has no darwin build of ultralytics to fetch instead
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ lib.optional darwin (pyFinal: pyPrev: {
    ultralytics = pyPrev.ultralytics.overridePythonAttrs (old: {
      disabledTests = (old.disabledTests or [ ]) ++ [ "test_data_utils" ];
    });
  });

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

      # Blackboard::setPortInfo compares type_info pointers. on mac each dylib has its own hidden std::string
      # typeinfo, so doTask's plugins fail "once declared, the type of a port shall not change". compare the types
      behaviortree-cpp-v3 = rosPrev.behaviortree-cpp-v3.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./patches/behaviortree-cpp-v3-typeinfo.patch ];
      });

      # camera_ros is only for apriltag_ros' example launch and needs libcamera (linux only).
      # apple's ld has no -z (release's vendored copy has the same fix, apriltag_ros 253cd93)
      apriltag-ros = rosPrev.apriltag-ros.overrideAttrs (old: {
        propagatedBuildInputs = lib.filter (p: (p.pname or "") != "ros-${rosDistro}-camera-ros") old.propagatedBuildInputs;
        postPatch = (old.postPatch or "") + ''
          substituteInPlace CMakeLists.txt --replace-fail 'add_link_options("-Wl,-z,relro,-z,now,-z,defs")' ""
        '';
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
    } // lib.optionalAttrs (!darwin) {
      # finds libcamera through pkg-config, but the overlay doesn't give it one (apriltag-ros propagates it)
      camera-ros = rosPrev.camera-ros.overrideAttrs (old: {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.pkg-config ];
      });
    })).overrideScope (if rosExtra == null then (_: _: { }) else import ./ros-extra.nix { inherit lib darwin; sources = rosExtra; });
  };
}

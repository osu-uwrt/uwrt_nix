{
  inputs = {
    # both pinned to develop (cached on ros + ros-darwin), bump on purpose.
    # release only supplies release's ros deps, cut a release with `nix flake update nix-ros-overlay-release`
    nix-ros-overlay.url = "github:lopsided98/nix-ros-overlay/84ede7becd81f206251f4cd709c551f43c3eb376";
    nix-ros-overlay-release.url = "github:lopsided98/nix-ros-overlay/84ede7becd81f206251f4cd709c551f43c3eb376";
    nixpkgs.follows = "nix-ros-overlay/nixpkgs";  # IMPORTANT!!!

    riptide_setup = { url = "github:osu-uwrt/riptide_setup/matlab-install"; flake = false; };

    # riptide-tools sources: the local, unpushed nix-macos branches for now. once they're pushed, back to
    #   git+https://github.com/osu-uwrt/nereus?ref=<branch>  and  git+ssh://git@github.com/osu-uwrt/notgroot?ref=<branch>
    # test uncommitted edits with --override-input notgroot git+file://$HOME/osu-uwrt/notgroot
    nereus = { url = "git+file:///Users/ethan/osu-uwrt/development/software/src/nereus?ref=nix-macos"; flake = false; };
    notgroot = { url = "git+file:///Users/ethan/osu-uwrt/notgroot?ref=nix-macos"; flake = false; };

    # gl for nix programs on non-nixos linux
    nixgl = { url = "github:nix-community/nixGL"; inputs.nixpkgs.follows = "nixpkgs"; inputs.flake-utils.follows = "nix-ros-overlay/flake-utils"; };

    # ros-extra, the commits development/dependencies used. no vectornav, the fork is deprecated
    chameleon_tf = { url = "github:coalman321/chameleon_tf/fe161bf96970e52b29fa8a39a256958fbe1f4065"; flake = false; };
    nortek_dvl = { url = "github:osu-uwrt/nortek_dvl/be21db9ffc60f040b2c0287a60ec43423da80d0f"; flake = false; };
    zed_interfaces = { url = "github:stereolabs/zed-ros2-interfaces/f7f90f11f818c3dda23219cd05d8c854a569fc85"; flake = false; };
  };

  outputs = { self, nix-ros-overlay, nix-ros-overlay-release, nixpkgs, ... }@inputs:
    let
      rosDistro = "humble";
      rosExtra = { inherit (inputs) chameleon_tf nortek_dvl zed_interfaces; };
    in
    nix-ros-overlay.inputs.flake-utils.lib.eachSystem [ "aarch64-darwin" "x86_64-linux" "aarch64-linux" ] (system:
      let
        pkgsFor = overlay: import overlay.inputs.nixpkgs {
          inherit system;
          overlays = [
            overlay.overlays.default
            (import ./nix/overlay.nix { inherit rosDistro rosExtra; })
          ];
        };
        pkgs = pkgsFor nix-ros-overlay;
        pkgsRelease = pkgsFor nix-ros-overlay-release;
        lib = pkgs.lib;

        skip = import ./nix/skip.nix { inherit lib; inherit (pkgs) stdenv; };

        # one colcon and one uwrt for both shells, from the dev pin (user, 2026-11-15). colcon runs
        # ament_python setup.py builds with its own python, so once the release pin's python differs
        # from the dev pin's, release python packages may need their own colcon again
        colcon = import ./nix/colcon.nix { inherit lib pkgs skip; inherit (inputs) riptide_setup; };
        # the uwrt_nix commit goes in uwrt's version, so doctor can spot a stale profile copy
        uwrt = pkgs.callPackage ./nix/uwrt.nix { rev = self.shortRev or self.dirtyShortRev or "dirty"; };
        mkShell = p: args: import ./nix/riptide-shell.nix ({
          inherit (p) lib;
          pkgs = p;
          ros = p.rosPackages.${rosDistro};
          inherit colcon skip uwrt tools;
        } // args);
        ros = pkgs.rosPackages.${rosDistro};

        # nereus + notgroot, one build from the dev pin for both shells
        tools = import ./nix/riptide-tools.nix {
          inherit lib pkgs;
          inherit (inputs) nereus notgroot;
          nixgl = if pkgs.stdenv.hostPlatform.isLinux then inputs.nixgl.packages.${system} else null;
        };
      in {
        devShells = rec {
          riptide-dev = mkShell pkgs {
            name = "riptide-dev";
            defaultWorkspace = "osu-uwrt/development/software";
            # release vendors these as submodules, dev gets them from here
            extraRos = with ros; [ chameleon-tf chameleon-tf-msgs nortek-dvl nortek-dvl-msgs zed-interfaces ];
            nereusBuild = true;
          };
          riptide-release = mkShell pkgsRelease {
            name = "riptide-release";
            defaultWorkspace = "osu-uwrt/release";
          };
          default = riptide-dev;
        };

        packages = {
          inherit (colcon) colcon colcon-riptide;
          inherit uwrt;
          inherit (tools) riptide-tools;
          nereus = tools.nereus-tool;
          notgroot = tools.notgroot-tool;
        };

        checks = { inherit (tools) notgroot-tests nereus-tests; };

        apps.deps-update = {
          type = "app";
          program = toString (pkgs.writeShellScript "uwrt-deps-update" ''
            exec ${pkgs.python3.withPackages (ps: [ ps.pyyaml ])}/bin/python3 -I ${./scripts/update-system-keys.py} \
              ${nix-ros-overlay.inputs.rosdistro} "''${1:-deps/system-keys.json}"
          '');
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

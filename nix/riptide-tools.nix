# riptide-tools: notgroot and nereus' ros-free parts (pack/dataset tools, headless dataset renderer), built once
# from the dev pin so both riptide shells get the same store paths. nereus' ros bridge and viewer need the
# workspace's riptide_msgs2, so those build in the dev workspace with nereus' own build.sh (see buildInputs below).
# linux: the gui programs go through nixGL unless on nixos (UWRT_NIXGL picks another wrapper, or none)
{ lib, pkgs, nereus, notgroot, nixgl ? null }:
let
  inherit (pkgs) stdenv;
  darwin = stdenv.hostPlatform.isDarwin;
  linux = stdenv.hostPlatform.isLinux;

  # notgroot-check builds the robot's BT.CPP 4.10.0 (not riptide's BT v3), cmake fetched it at configure
  btcpp = pkgs.fetchFromGitHub {
    owner = "BehaviorTree";
    repo = "BehaviorTree.CPP";
    rev = "4.10.0";
    hash = "sha256-i+zoJaWHebiPzRqZVY67mArmOOJJn7i8pL67FxGwATI=";
  };

  # nixpkgs' fontconfig only knows its own dejavu. add the desktop's fonts (themes ask for the Qt font)
  fontsConf = pkgs.writeText "uwrt-fonts.conf" ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
    <fontconfig>
      <include ignore_missing="yes">${pkgs.fontconfig.out}/etc/fonts/fonts.conf</include>
      <dir>${pkgs.dejavu_fonts}/share/fonts</dir>
      ${if darwin then ''
      <dir>/System/Library/Fonts</dir>
      <dir>/Library/Fonts</dir>
      <dir>~/Library/Fonts</dir>
      '' else ''
      <dir>/usr/share/fonts</dir>
      <dir>/usr/local/share/fonts</dir>
      <dir>~/.local/share/fonts</dir>
      <dir>~/.fonts</dir>
      ''}
    </fontconfig>
  '';

  # nereus' prop world links Debian's double-precision bullet (libBullet*-float64). same here
  bullet-float64 = pkgs.bullet.overrideAttrs (old: {
    pname = "bullet-float64";
    cmakeFlags = old.cmakeFlags ++ [ "-DUSE_DOUBLE_PRECISION=ON" ];
    postInstall = (old.postInstall or "") + ''
      for l in BulletDynamics BulletCollision LinearMath; do
        ln -s lib$l${stdenv.hostPlatform.extensions.sharedLibrary} $out/lib/lib$l-float64${stdenv.hostPlatform.extensions.sharedLibrary}
      done
    '';
  });

  # assimp 6 (nixpkgs) orders mesh indices differently from 5.x, so nereus' recorded mesh references (made on
  # jammy's 5.2) don't match. 5.2.5 does. nereus builds against both
  assimp5 = pkgs.assimp.overrideAttrs (old: rec {
    version = "5.2.5";
    src = pkgs.fetchFromGitHub {
      owner = "assimp";
      repo = "assimp";
      rev = "v${version}";
      hash = "sha256-vQx+PaET5mlvvIGHk6pEnZvM3qw8DiC3hd1Po6OAHxQ=";
    };
    patches = [ ];
    postPatch = "";  # nixpkgs' substitutions are for 6.x test files
    # the mmd importer doesn't build with gcc 15, and nereus has no mmd models
    cmakeFlags = (old.cmakeFlags or [ ]) ++ [
      "-DASSIMP_WARNINGS_AS_ERRORS=OFF" "-DASSIMP_BUILD_TESTS=OFF" "-DASSIMP_BUILD_MMD_IMPORTER=OFF"
    ];
    doCheck = false;
  });

  gl = lib.optionals linux [ pkgs.libGL pkgs.libglvnd ];
  # glfw3native.h's x11 part includes Xrandr too
  x11 = lib.optionals linux [ pkgs.libX11 pkgs.libXrandr ];

  # what nereus' ros-viewer preset needs besides ros. the dev shell gets these too, for build.sh
  nereusDeps = with pkgs; [
    eigen yaml-cpp nlohmann_json gtest glfw glew libpng libjpeg opencv fontconfig
  ] ++ [ assimp5 bullet-float64 ] ++ gl ++ x11;

  notgrootDeps = with pkgs; [ yaml-cpp tinyxml-2 zeromq zlib glfw glew libpng fontconfig freetype ]
    ++ gl ++ x11 ++ lib.optionals linux [ pkgs.libXi ];

  notgroot-unwrapped = stdenv.mkDerivation {
    pname = "notgroot";
    version = "0.1.0-${notgroot.shortRev or "dirty"}";
    src = notgroot;
    nativeBuildInputs = with pkgs; [ cmake ninja pkg-config ];
    buildInputs = notgrootDeps;
    cmakeFlags = [
      "-DBUILD_TESTING=OFF"
      "-DFETCHCONTENT_FULLY_DISCONNECTED=ON"
    ];
    # a writable copy: BT.CPP's cmake writes a .clangd into its source
    preConfigure = ''
      cp -r ${btcpp} $NIX_BUILD_TOP/btcpp && chmod -R u+w $NIX_BUILD_TOP/btcpp
      cmakeFlagsArray+=("-DFETCHCONTENT_SOURCE_DIR_BEHAVIORTREE_CPP=$NIX_BUILD_TOP/btcpp")
    '';
    meta.mainProgram = "notgroot";
  };

  nereus-unwrapped = stdenv.mkDerivation {
    pname = "nereus";
    version = "0.1.0-${nereus.shortRev or "dirty"}";
    src = nereus;
    nativeBuildInputs = with pkgs; [ cmake ninja pkg-config ];
    buildInputs = nereusDeps;
    # the datasets preset without tests: renderer, offscreen cameras, dataset generator. no ros
    cmakeFlags = map (o: "-DNEREUS_BUILD_${o}=ON") [
      "SIMULATION" "SCENE_RENDERER" "OFFSCREEN_RENDERER" "MESH_ASSETS" "CAMERAS" "SESSION" "PACK_SCENE" "DATASETS"
    ] ++ [ "-DBUILD_TESTING=OFF" ];
    meta.mainProgram = "nereus-dataset-render";
  };

  # nereus-packs and nereus-dataset, deps from nixpkgs instead of uv.lock
  nereus-python = pkgs.python3Packages.buildPythonApplication {
    pname = "nereus-tools";
    version = "0.1.0";
    src = nereus;
    pyproject = true;
    build-system = [ pkgs.python3Packages.setuptools ];
    dependencies = with pkgs.python3Packages; [ numpy ruamel-yaml jsonschema referencing opencv4 pillow scipy ];
    pythonRemoveDeps = [ "opencv-python-headless" ];
    doCheck = false;
    pythonImportsCheck = [ "nereus.packs" "nereus.datasets" ];
  };

  nixGLIntel = if linux && nixgl != null then nixgl.nixGLIntel else null;

  # fonts everywhere, nixGL on non-nixos linux
  wrap = name: target: extra: pkgs.writeShellScriptBin name (''
    export FONTCONFIG_FILE=''${FONTCONFIG_FILE:-${fontsConf}}
    ${extra}
  '' + lib.optionalString (nixGLIntel != null) ''
    gl=''${UWRT_NIXGL:-${lib.getExe nixGLIntel}}
    if [ "$gl" != none ] && [ ! -e /etc/NIXOS ]; then exec "$gl" ${target} "$@"; fi
  '' + ''
    exec ${target} "$@"
  '');
  renderWrapper = wrap "nereus-dataset-render" (lib.getExe nereus-unwrapped) ''
    export NEREUS_SHADER_DIR=''${NEREUS_SHADER_DIR:-${nereus-unwrapped}/share/nereus/shaders}
  '';
  # the projects' own test suites (ctest), built the same way. window tests skip without a display. on linux
  # the sandbox has no gl driver, so egl gets mesa's software one (llvmpipe, surfaceless) and the offscreen tests run
  withTests = drv: drv.overrideAttrs (old: {
    pname = "${old.pname}-tests";
    buildInputs = old.buildInputs ++ [ pkgs.gtest ];
    cmakeFlags = lib.remove "-DBUILD_TESTING=OFF" old.cmakeFlags ++ [ "-DBUILD_TESTING=ON" ];
    doCheck = true;
    preCheck = lib.optionalString linux ''
      export __EGL_VENDOR_LIBRARY_FILENAMES=${pkgs.mesa}/share/glvnd/egl_vendor.d/50_mesa.json
      export LIBGL_DRIVERS_PATH=${pkgs.mesa}/lib/dri LIBGL_ALWAYS_SOFTWARE=1
    '';
    checkPhase = ''
      runHook preCheck
      ctest --output-on-failure -LE live -j$NIX_BUILD_CORES
      runHook postCheck
    '';
    installPhase = "touch $out";
  });
in rec {
  notgroot-tests = withTests notgroot-unwrapped;
  nereus-tests = withTests nereus-unwrapped;
  inherit assimp5 fontsConf nereusDeps notgrootDeps notgroot-unwrapped nereus-unwrapped nereus-python nixGLIntel;

  notgroot-tool = pkgs.symlinkJoin {
    name = "notgroot-${notgroot-unwrapped.version}";
    paths = [ notgroot-unwrapped ];
    postBuild = "rm $out/bin/notgroot && cp ${wrap "notgroot" (lib.getExe notgroot-unwrapped) ""}/bin/notgroot $out/bin/";
    meta.mainProgram = "notgroot";
  };

  nereus-tool = pkgs.symlinkJoin {
    name = "nereus-${nereus-unwrapped.version}";
    paths = [ nereus-python nereus-unwrapped ];
    postBuild = ''
      rm $out/bin/nereus-dataset-render
      cp ${renderWrapper}/bin/nereus-dataset-render $out/bin/
    '';
    meta.mainProgram = "nereus-packs";
  };

  riptide-tools = pkgs.symlinkJoin {
    name = "riptide-tools";
    paths = [ nereus-tool notgroot-tool ] ++ lib.optional (nixGLIntel != null) nixGLIntel;
  };
}

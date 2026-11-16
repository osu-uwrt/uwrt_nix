# the uwrt command and uwrt-env. built from the dev pin only, so every shell and
# `nix profile add .#uwrt` get the same store path. git, nix and direnv come from the user's PATH
{ lib, stdenvNoCC, bash, python3, rev ? "dirty" }:
stdenvNoCC.mkDerivation {
  pname = "uwrt";
  version = "0.2.0";
  src = ../uwrt;
  buildInputs = [ bash ];  # for patchShebangs: macos /bin/bash is 3.2

  dontConfigure = true;
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    install -Dm755 uwrt $out/bin/uwrt
    install -Dm755 uwrt-env $out/bin/uwrt-env
    install -Dm644 patch-bashrc.py $out/share/uwrt/patch-bashrc.py
    install -Dm644 zenoh_client.json5 $out/share/uwrt/zenoh_client.json5
    install -Dm644 fastdds_local.xml $out/share/uwrt/fastdds_local.xml
    # zsh completion. _ros2 calls whatever ros2/colcon is on PATH, so it only answers in a workspace
    install -Dm644 _uwrt $out/share/zsh/site-functions/_uwrt
    ${python3.pkgs.argcomplete}/bin/register-python-argcomplete --shell zsh ros2 colcon > $out/share/zsh/site-functions/_ros2
    substituteInPlace $out/bin/uwrt $out/bin/uwrt-env \
      --replace-fail @share@ $out/share/uwrt --replace-quiet @version@ "$version+${rev}" --replace-quiet @python@ ${python3}/bin/python3
    # the patcher asks bash itself where statements end
    substituteInPlace $out/share/uwrt/patch-bashrc.py --replace-fail "'UWRT_BASH', 'bash'" "'UWRT_BASH', '${bash}/bin/bash'"
    runHook postInstall
  '';

  meta = {
    description = "uwrt workspace helper: dev/release envs, build, rmw, setup, doctor";
    mainProgram = "uwrt";
    platforms = lib.platforms.unix;
  };
}

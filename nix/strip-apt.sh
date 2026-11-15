# sourced by the riptide shells' shellHook. drops apt ros (/opt/ros) and every colcon workspace
# the outer shell had sourced (e.g. ~/.bashrc's apt-built dependencies, software, release, mercury)
# from the path variables. those link against /opt/ros, and the nix env sits behind them
# (underlay = true), so leftovers would win. the .envrc sources this workspace's install after.

# a colcon install prefix (or /opt/ros/<distro>) has one of these at its root
_uwrt_ws_prefix() {
  local d=$1
  while [ -n "$d" ] && [ "$d" != / ]; do
    if [ -e "$d/.colcon_install_layout" ] || [ -e "$d/_local_setup_util_sh.py" ]; then return 0; fi
    d=${d%/*}
  done
  return 1
}

_uwrt_strip() {
  local var=$1 out= e parts
  IFS=: read -ra parts <<< "${!var-}"
  for e in "${parts[@]}"; do
    case $e in
      '') continue ;;
      # another riptide shell's env (a nix develop nested in one): only ours stays
      /nix/store/*-ros-env|/nix/store/*-ros-env/*|/nix/store/*-dyld-wrappers/*)
        case $e in "$_uwrt_own_env"|"$_uwrt_own_env"/*|"$_uwrt_own_wrap"/*) ;; *) continue ;; esac ;;
      /nix/store/*) ;;
      /opt/ros/*) continue ;;
      *) _uwrt_ws_prefix "$e" && continue ;;
    esac
    out=${out:+$out:}$e
  done
  if [ -n "$out" ]; then export "$var=$out"; else unset "$var"; fi
}

for _uwrt_v in PATH LD_LIBRARY_PATH DYLD_LIBRARY_PATH PYTHONPATH CMAKE_PREFIX_PATH AMENT_PREFIX_PATH \
  PKG_CONFIG_PATH ROS_PACKAGE_PATH; do
  [ -n "${!_uwrt_v+x}" ] && _uwrt_strip "$_uwrt_v"
done
unset -f _uwrt_strip _uwrt_ws_prefix
# ROS_DISTRO/VERSION/PYTHON_VERSION are already the env's own by now, nix sets them before this
unset _uwrt_v _uwrt_own_env _uwrt_own_wrap COLCON_PREFIX_PATH AMENT_CURRENT_PREFIX

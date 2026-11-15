#!/usr/bin/env bash
# macos SIP check: starts ros programs through /bin/sh with an otherwise empty env (so no DYLD_*)
# and checks a C++ talker reaches a python listener on fastdds (localhost, domain 93) and on
# zenoh (a 127.0.0.1-only router). usage: sip-dlopen.sh <ros env or install prefix> [extra AMENT_PREFIX_PATH]
set -u
E=$1
APP=${2:+$2:}$E
T=$(mktemp -d)
pids=()
stop() { for p in ${pids[@]+"${pids[@]}"}; do kill "$p" 2>/dev/null; done; sleep 1; for p in ${pids[@]+"${pids[@]}"}; do kill -9 "$p" 2>/dev/null; done; pids=(); }
cleanup() { stop; rm -rf "$T"; }
trap cleanup EXIT

run() {  # run <rmw> <log> <cmd...>, through /bin/sh, no DYLD
  local rmw=$1 log=$2; shift 2
  env -i HOME="$HOME" PATH="$E/bin:/usr/bin:/bin" AMENT_PREFIX_PATH="$APP" ROS_DOMAIN_ID=93 ROS_LOCALHOST_ONLY=1 \
    RCUTILS_LOGGING_BUFFERED_STREAM=0 PYTHONUNBUFFERED=1 RMW_IMPLEMENTATION="$rmw" \
    ZENOH_ROUTER_CONFIG_URI="$T/router.json5" ZENOH_ROUTER_CHECK_ATTEMPTS=10 \
    /bin/sh -c "exec $*" > "$log" 2>&1 &
  pids+=($!)
}

sed 's|tcp/\[::\]:7447|tcp/127.0.0.1:7447|' "$E/share/rmw_zenoh_cpp/config/DEFAULT_RMW_ZENOH_ROUTER_CONFIG.json5" > "$T/router.json5"
grep -q 'tcp/127.0.0.1:7447' "$T/router.json5" || { echo "router config: no listen line"; exit 1; }
cat > "$T/listener.py" <<'PY'
import rclpy
from std_msgs.msg import String
rclpy.init()
n = rclpy.create_node('sip_listener')
n.create_subscription(String, 'chatter', lambda m: print('I heard', m.data, flush=True), 10)
rclpy.spin(n)
PY

fail=0
for rmw in rmw_fastrtps_cpp rmw_zenoh_cpp; do
  [ $rmw = rmw_zenoh_cpp ] && { run $rmw "$T/router.log" "$E/lib/rmw_zenoh_cpp/rmw_zenohd"; sleep 2; }
  run $rmw "$T/talker.log" "$E/lib/demo_nodes_cpp/talker"
  # python3 from PATH, like a #!/usr/bin/env python3 script would get
  run $rmw "$T/listener.log" "python3 $T/listener.py"
  for _ in $(seq 20); do grep -q 'I heard' "$T/listener.log" && break; sleep 1; done
  if grep -q 'I heard' "$T/listener.log"; then echo "PASS $rmw: $(grep -m1 'I heard' "$T/listener.log")"
  else echo "FAIL $rmw"; tail -5 "$T/talker.log" "$T/listener.log" "$T/router.log" 2>/dev/null; fail=1; fi
  stop
done
exit $fail

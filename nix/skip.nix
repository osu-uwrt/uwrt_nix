# packages colcon ignores, and whose deps the shells don't pull in
{ lib, stdenv }:
[
  "zed_ros2_wrapper"
  "zed_components"
  "riptide_rviz"        # rviz is out of scope
  "c_simulator"         # deprecated
  "camera_faker"
]

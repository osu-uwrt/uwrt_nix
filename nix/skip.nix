# packages colcon ignores, and whose deps the shells don't pull in
{ lib, stdenv }:
[
  "tensor_detector"     # invalid rosdep keys, needs CUDA
  "zed_ros2_wrapper"
  "zed_components"
  "riptide_rviz"        # rviz is out of scope
  "c_simulator"         # deprecated
  "camera_faker"
] ++ lib.optionals stdenv.hostPlatform.isDarwin [
  "opbox_software"
]

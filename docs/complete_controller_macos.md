# complete_controller on macOS

complete_controller is a legacy Simulink-generated controller. It's kept building on macOS as a check that a
generated package with handwritten custom code works there. Its generated package is never committed or
published, and it drives thrusters, so it isn't run off the robot.

## The SocketCAN guard

The model links handwritten C through its configuration: `CustomSource` / `SimUserSources` =
`complete_system/send_thruster_cmd_canbus.c` in `riptide_controllers/models/{x86,arm}_cfg.m` (the generator is
`riptide_simulink/matlab/riptide_generate.m`). That file talks SocketCAN (`linux/can.h`, `PF_CAN`), which macOS
doesn't have.

On riptide_control's `nix-macos` branch the SocketCAN code sits under `#ifdef __linux__`. Elsewhere
`send_thruster_cmd_canbus()` reports once and returns `ENOTSUP`, then returns 0, the same as a failed CAN init on
Linux. Linux behavior is unchanged. The guard matters beyond complete_controller: riptide_mpc builds the same file
into `thruster_can` and calls it.

The model, its config and the generated code need no edits: generation copies the custom source into the
generated package, guard included. The x86_64 generation uses SSE intrinsics, so only the arm64 one builds on
Apple silicon.

## Regenerating

With MATLAB R2023a on Linux, headless (no `DISPLAY`), in a copy of the workspace rather than the live tree, driven
by the system Python outside the Nix shell:

```
cp riptide_simulink/examples/riptide_control.simulink.yaml riptide_control/riptide_controllers/models/simulink.yaml   # copy only
model_manager.py build complete_controller --workspace src/riptide_control/riptide_controllers/models \
  --source local --arch x86_64 arm64 --local-dir <copy>/software/src/simulink_models \
  --archives-dir <copy>/simulink_model_archives --deploy-dir <copy>/deploy_unused/src/simulink_models \
  --no-process-deploy --no-build --no-publish --yes
```

Both arches take about 8 minutes. MATLAB may print `Error in indexing … LibDictionaryDependencyInfo/cleanupLibraryInfo`
from a destructor during cleanup. It's harmless: generation finishes and the exit status is 0.

## What builds

| Generation | Builds in riptide-dev on |
|---|---|
| x86_64 | Linux (riptide_controllers2 compiles the guarded file as `thruster_test_canbus`) |
| arm64 ("ARM 64-bit (LP64)", the robot's codegen target) | macOS |

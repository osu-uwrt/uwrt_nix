# complete_controller on macOS (legacy portability test)

complete_controller is legacy. It was only used to check that a Simulink-generated package with handwritten custom code builds on macOS. Its generated package is never committed or published. Done 2026-11-15.

## What blocked it

The model links handwritten C through its configuration: `CustomSource` / `SimUserSources` = `complete_system/send_thruster_cmd_canbus.c` in `riptide_controllers/models/{x86,arm}_cfg.m`. That file talks SocketCAN (`linux/can.h`, `PF_CAN`), so the generated package didn't build on macOS. The old x86 generation also used SSE intrinsics, so it couldn't build on Apple Silicon either way.

(The plan pointed at `CustomInclude` in `riptide_generate.m`. That's stale: the generator moved to `riptide_simulink/matlab/riptide_generate.m`, and the custom code comes in through `CustomSource` in the config factories.)

## What changed

- **`send_thruster_cmd_canbus.c` is guarded, committed** (riptide_control `nix-macos` `36cf038`, which the dev workspace gets through a merge). It isn't legacy-only: riptide_mpc builds it into `thruster_can` and calls it. The SocketCAN code sits under `#ifdef __linux__`. Elsewhere `send_thruster_cmd_canbus()` reports once and returns `ENOTSUP`, then returns 0, the same as a failed CAN init on Linux. Linux behavior is unchanged.
- **No model, config or generated-code edits.** The guard reaches the generated package because generation copies the custom source in.

## How it was regenerated

On ethan-XPS, in a copy (`~/osu-uwrt/nix_test/software/src`), never the live tree. MATLAB R2023a ran headless (no `DISPLAY`) and alone, driven by the system Python outside the Nix shell, with FastDDS localhost on domain 93:

```
cp riptide_simulink/examples/riptide_control.simulink.yaml riptide_control/riptide_controllers/models/simulink.yaml   # copy only
model_manager.py build complete_controller --workspace src/riptide_control/riptide_controllers/models \
  --source local --arch x86_64 arm64 --local-dir <nix_test>/software/src/simulink_models \
  --archives-dir <nix_test>/simulink_model_archives --deploy-dir <nix_test>/deploy_unused/src/simulink_models \
  --no-process-deploy --no-build --no-publish --yes
```

It took 8 min 14 s for both arches. MATLAB printed `Error in indexing … LibDictionaryDependencyInfo/cleanupLibraryInfo` from a destructor during cleanup; generation finished and the exit status was 0.

## Results

| | Package | Result |
|---|---|---|
| Linux (xps, riptide-dev) | x86_64 generation | builds (with riptide_controllers2, which compiles the guarded file as `thruster_test_canbus`) |
| macOS (riptide-dev) | arm64 generation ("ARM 64-bit (LP64)", the robot's codegen target) | builds |

The arm64 archive used on the Mac is `~/osu-uwrt/mac_handoff/phase1/simulink_model_archives/`. The Mac's previous `simulink_models/` is backed up in `~/osu-uwrt/mac_handoff/phase1/simulink_models_backup_2026-11-14.tgz`.

The node wasn't run: it's legacy and drives thrusters.

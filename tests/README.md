# Local regression checks

Run from PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1
```

The runner uses an existing Lua 5.1/LuaJIT DLL, syntax-checks every addon Lua file,
then executes `*_test.lua` files. It defaults to
`C:\Program Files\bin\64bit\lua51.dll`; use `-LuaDll <path>` or `LUA51_DLL` for
another installation. The DLL architecture must match PowerShell. Nothing is
installed and no game/server files are modified. `-SyntaxOnly` skips execution.

The tests load the actual addon functions with deterministic engine API mocks:

- `deployment_test.lua` checks stationary grounded deployment and rejects motion,
  airborne players (including the jump apex), ladders, and noclip before spawning.
- `zoom_test.lua` checks LMB zoom cycling, release handling, optical magnification,
  aiming sensitivity, stereo audio, full-clip input cooldown, asynchronous loading,
  stale audio callbacks, new-flight reset, and normal controls outside a flight.
- `exit_hold_test.lua` checks the two-second exit hold through client/server
  input, release cancellation, interrupted input, stale commands, and new flights.
- `npc_targeting_test.lua` checks hostile/friendly targeting, visibility, stealth
  memory cleanup, reacquisition, right-click input through client and server
  command processing, damage forwarding, and removal.
- `range_test.lua` checks the one-time saved-range upgrade and custom settings.
- `stealth_test.lua` checks doubled battery drain, mode transitions, depletion,
  model opacity, draw passes, and blend restoration.
- `sensor_battery_test.lua` checks thermal/night-vision drain, combined stealth
  costs, transition accounting, and sensor synchronization for the current pilot.
- `sensor_reset_test.lua` checks optical defaults on every deployment before
  rendering/battery sync, while preserving sensor toggles during a flight.
- `nightvision_test.lua` checks the imported NVG Night preset, bloom order, light
  adaptation, red static, drone illuminator, thermal exclusion, cleanup and
  a red fallback when the static material is missing.
- `hud_scan_test.lua` checks per-refresh trace limits, cadence, coherent sample
  positions, invalid contacts, flight resets, and completion at low frame rates.
- `thermal_test.lua` checks the replacement Splinter Cell NVG preset's processing
  order, actor filtering, drone illuminator, scan cadence, material/colour/render
  mode restoration, missing-asset fallback, and native texture assets.
  It reproduces multiplayer material getters hiding client overrides and checks
  immediate toggle cleanup plus recovery of already stuck character materials.

These checks measure Lua control flow and work counts. They cannot measure GPU
frame time or verify actual Source-engine occlusion, stencil pixels, or colors;
those require an in-game test.

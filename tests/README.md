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
  aiming sensitivity, new-flight reset, and normal controls outside a flight.
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
- `hud_scan_test.lua` checks per-refresh trace limits, cadence, coherent sample
  positions, invalid contacts, flight resets, and completion at low frame rates.
- `thermal_test.lua` checks draw submissions for visible and engine-culled NPCs,
  custom/translucent renderers, fallback views, draw failures, render-state cleanup,
  override restoration, and the framebuffer tint's blend factors.

To check the thermal regression against an earlier autorun file, set
`PROBE_DROID_THERMAL_TEST_SOURCE` to that file's path for the test process.

These checks measure Lua control flow and work counts. They cannot measure GPU
frame time or verify actual Source-engine occlusion, stencil pixels, or colors;
those require an in-game test.

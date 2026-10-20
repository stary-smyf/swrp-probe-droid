# Live debugger test results

Night vision now uses the supplied Splinter Cell NVG Night preset. Local checks
cover its green static, bloom, adaptation, projected illuminator and cleanup.
This replacement has not yet been verified live; older night-vision captures and
performance notes below describe the previous implementation.

The thermal renderer has been replaced with the supplied Splinter Cell NVG
Thermal preset. Its local regression checks pass, but the new effect has not
been verified live. Thermal screenshots, timings, and rendering observations
below refer to the previous implementation.

Manual exit now requires a continuous two-second hold of E, with a countdown
and release-to-cancel behavior. Local input regression checks pass; the historical
instant-exit result below predates this change.

Thermal/night-vision battery costs and their combination with stealth are
covered by local tests, including client/server sensor synchronization. The
new sensor costs have not yet been verified in a live game.

The NPC targeting and stealth feature added on 2026-10-19 has passed local Lua
regression tests with engine mocks. It has not yet been verified in a live game;
the results below describe the earlier build.
Local checks also cover stealth sound selection, doubled battery drain, and
model drawing at half opacity. The HUD fade and in-game appearance/audio remain
to be verified.
The M2 fix preserves secondary attack through client command processing so the
server can read the stealth toggle. A regression check reproduced the stripped
input before the fix and now covers client-to-server press, hold, and release.

Tested on 2026-10-18 with a dedicated server and connected client on
`gm_construct`, using the supplied probe model.

| Check | Result |
| --- | --- |
| SWEP deployment | Probe spawns; pilot immediately receives the drone view and stops moving. |
| Client camera | First-person view hook returns the drone camera position and player look angles; controller viewmodel is hidden. |
| Flight input | Real client user commands move the server-side drone. |
| Normal / boosted speed | Observed approximately 349 / 629 Source units per second. |
| Altitude controls | Space ascends; Ctrl descends. |
| Body position | Remained at the launch point throughout flights. |
| Wall collision | Forward flight stopped at a solid wall without entering it. |
| E exit | Drone removed; player view and walking movement restored. |
| Battery expiry | Shortened the active probe's deadline; expiry destroyed it and restored control. |
| Range loss | Set the active probe's range to 200 units, then flew upward; crossing the limit destroyed it and restored control. |
| Damage | Engine damage reduced health from 60 to 40; lethal damage destroyed the probe and restored control. |
| Direct entity removal | Removed the drone; player view, movement, and control reference restored. |
| Controller removal | Stripped the SWEP during flight; drone removed and player control restored. |

The first deployment exposed a client initialization race: the networked probe
reference could become available before its camera methods/data table accessors.
The control lookup now waits for those methods and verifies the pilot. Repeated
deployments and flight checks after reloading the fix produced no addon errors.

Camera/HUD verification was performed through runtime state and hook execution.
Image captures were obscured and do not establish visual layout quality.
Pilot death/disconnect, whole-map cleanup, and two simultaneous pilots were not
exercised in this live session.

Temporary input, sampling, error, and capture hooks were removed after testing.
The original player weapon and eye angles were restored; server convars were
unchanged.

A follow-up regression check verified the control lookup with `nil`, `NULL`, and
the live `LocalPlayer()`. Invalid players now return before `GetNW2Entity` is
called. The drone draw function also checks player validity before reading that
reference. Both guards were loaded into the live session.

Another follow-up reproduced the reported movement failure using the normal
`+forward` command. The client saw forward buttons and movement, but the server
received cleared input and the probe travelled zero units in open space. The
earlier motion tests injected user commands and missed this transport failure.

The shared input hook now preserves client flight buttons and movement until
the server consumes them. It clears body inputs on the server and suppresses
predicted weapon attacks/reload on the client. Retesting with `+forward`,
`+speed`, `+jump`, `+duck`, and `+use` confirmed normal/boost speeds of approximately
349/629 units per second, ascent/descent, and exit with restored player control.
The fix was loaded in both realms, and all test inputs were released afterward.

The pilot rotation regression now keeps server command angles at the launch
orientation after reading drone steering. The client camera retains its own
command angle, and the pilot's local render orientation/aim pose stay fixed
during drawing. The previous render angle is restored after drawing.

Live turning through `+right` moved the camera and drone yaw from approximately
93 degrees to -117 degrees while the pilot's server eye yaw and local rendered
body yaw remained at 93 degrees. Normal forward input then moved the probe
approximately 241 units. Exiting with E restored walking and the player view;
normal player turning worked again and the temporary render marker was cleared.
The final turning, movement, and exit checks produced no runtime errors.

The immersive optical HUD was visually inspected in the live client at
2560 x 1440. Normal and simultaneous low-battery/weak-signal states rendered
without errors. Verified the compass, annular reticle, pitch scale, depth profile,
proximity radar/home marker, power/link meters, hidden default health display,
and the camera-effects console toggle. Complete screenshots are stored in
`artifacts/probe-hud.jpg` and `artifacts/probe-hud-warning.jpg`; these artifacts
are excluded from Workshop packaging. This supersedes the earlier limitation
on visual inspection. The HUD is contained in the existing autorun file so
clients can receive it through live reload without downloading a new Lua file.

Responsive HUD sizing was checked with 30 combinations of resolution and size
preference, from 640 x 360 through 7680 x 4320, including 4:3 and ultrawide.
Layout checks confirmed side instruments stay inside the screen and clear of
the reticle. Font measurements at six resolutions confirmed control labels and
panel titles fit. Resolution-change invalidation was also exercised. The updated
HUD was loaded into both live realms without errors; alternate resolutions were
checked through layout calculations/font metrics, without changing the user's
display mode.

Metric readouts now convert distance and velocity using 0.01905 meters per
Source unit. Live client checks verified 1000 units = 19.05 m, 350 units/s =
6.6675 m/s, and signed altitude conversion. Enlarged/bolder text, brighter
instrument colors, stronger outlines, dark radar/flight-readout backings, and
darker panels improve contrast. Font measurements for metric telemetry and
control labels passed at six resolutions from 640 x 360 to 7680 x 4320.
The update loaded live without errors; server flight settings retain their
original Source-unit values.

HUD performance was profiled in the live client: the previous renderer averaged
30.39 ms per active frame (38.86 ms peak). After caching static instruments and
camera effects into small transparent textures and replacing repeated text
outline passes with a two-pass shadow, 60 warm frames averaged 4.00 ms (5.18 ms
peak), approximately 87% less HUD CPU time in this session. Initial texture
creation was measured separately at 26.45 ms; it happens once per graphic size.
Radar visibility work is now capped at 16 candidates per scan and runs at most
twice per second. The scene, transparency, cached instruments, and dynamic text
were visually checked with a one-frame client-only preview, which cleaned itself
up without changing the player's flight/body state. The final renderer produced
no addon errors during these checks.

Red-hot thermovision was added as a reload-key toggle with a persistent client
preference. Live visual checks used temporary client-only characters and an
occluding wall: the scene was dark red, exposed character surfaces rendered
orange/yellow/white, and the wall blocked the heat overlay. Preview entities and
callbacks were removed and the original mode preference restored. In an active
flight, 30 warm thermal frames averaged 0.68 ms for the thermal rendering hook
(4.25 ms peak in that scene), excluding initial texture generation. The renderer
limits heat draws to 24 nearby living actors and refreshes candidates at 2 Hz.
Runtime guards and the reload-key toggle were also exercised without errors.

Thermal silhouette alignment was corrected to inherit the actual world camera
with `cam.Start3D()` rather than rebuilding its projection from the player's base
FOV. In the live widescreen session, the player FOV was 100 while the rendered
world FOV was 115.63, explaining the displaced/oversized overlay. Culling now
also uses the current rendered view's origin/angles. A live screenshot of the
existing NPC group showed aligned silhouettes without duplicate bodies; the
capture is `artifacts/probe-thermal-aligned.jpg`. No runtime errors occurred.

Night vision was added on N with image gain, a client-only illuminator, a HUD
mode indicator, and a bindable `probe_droid_toggle_nightvision` command. Live
checks passed for thermal/night-vision mutual exclusion and illuminator cleanup
when switching modes. An active flight screenshot verified the initial green
rendering (`artifacts/probe-nightvision.jpg`); the subsequent tint edit in the
working file was preserved and loaded. The flight then ended through normal
battery depletion; cleanup was checked outside drone control. No new runtime
errors occurred. No performance timing is claimed for the final night-vision
shader because the flight ended before the profiling sample completed.

Flight inertia and camera sway were loaded through the live server/client
debugger. The server now uses exponential acceleration (0.55-second response)
and coasting/braking (0.8-second response), retaining the swept hull collision
and immediate stop on stale commands. Simulated one-second acceleration at
33, 66, and 100 Hz reached 293.188 units/s in each case; release preserved a
short glide, settled below 1 unit/s, and opposite input reversed velocity.
The live entity exposed the updated movement method successfully.

The actual camera callback was also exercised in an isolated client harness
at 30, 60, and 144 FPS. Checks passed for bounded banking, identical results
on repeated calls within one frame, unchanged camera origin, settling at rest,
immediate removal with `probe_droid_camera_sway 0`, and no view override outside
control. No runtime errors occurred. A full manual flight/collision check was
not performed for this update; these checks validate movement response and
camera logic rather than the subjective flight feel.

Thermal targeting now includes visible non-prop model entities, such as items,
weapons, scripted entities, and other drones, alongside living players and NPCs.
Prop classes (including camera props), brush/sprite/logic entities, viewmodels,
hands, and the controlled drone are excluded. The existing 24-target limit,
2 Hz candidate refresh, inherited camera projection, and wall occlusion remain.
The update loaded into the live client without errors; a live entity scan
confirmed scripted supply packs and weapons were eligible and prop classes
were excluded. Isolated predicate checks also passed for the supported classes,
hidden/dormant entities, dead players, and self-exclusion. A visual flight check
of the expanded highlights was not performed.

Thermal highlight dropouts were traced to the nearest-24 shortlist: weapons,
occluded entities, and entities behind the camera consumed slots, and distance
sorting changed which targets received highlights. Removed the cap and sorting;
all cached eligible models are now range-checked every frame. Removed the
centre-only forward test, which could reject partly visible large models.
Individual model-draw errors are isolated so one addon cannot abort highlights
for the rest of the list; repeated errors are logged at most every five seconds
per entity. Wall occlusion and prop exclusions are unchanged.

The fix loaded into the live client without errors. An isolated execution of
the actual draw loop passed with 80 candidates across repeated frames, including
targets beyond index 24 and behind the camera centre plane. Removed/out-of-range
targets were skipped, and an injected model-draw failure did not prevent later
targets from drawing. No live drone flight was active for visual verification.

Performance update: the full HUD is now cached in a transparent texture and
refreshed at 20 Hz, with immediate invalidation for control/mode/scale/effects
changes. World/camera rendering remains uncapped by this setting. Thermal
eligibility, bounds, and draw methods are cached; conservative sphere/frustum
checks skip off-screen models without reintroducing a target-count limit.
Heat colors are baked into an unlit material instead of recalculating model
lighting. Night vision's illuminator radius was reduced from 800 to 384 units,
model lighting was disabled for that light, and updates are limited to 20 Hz.
The filter itself retains the user's red tint. Flight response was shortened
from 0.55/0.8 to 0.22/0.35 seconds (acceleration/braking); stationary flight no
longer performs zero-distance collision sweeps.

Live 2560 x 1440 client previews measured 30 warm frames per mode. Before this
update, HUD hook CPU time averaged 3.83–3.88 ms and thermal averaged 5.01 ms.
After caching metadata, HUD averaged 1.38–1.65 ms and thermal 3.00 ms. A later
view averaged 0.97–1.31 ms for HUD and 1.89 ms for thermal; these are indicative
addon CPU timings, not total FPS/GPU benchmarks, and the user moved between
views during testing. Night filter submission remained approximately 0.09 ms;
the illuminator's GPU saving was not separately measured. Cached HUD alpha and
the optimized thermal material were visually checked in live preview captures
(`artifacts/probe-performance-hud.jpg`, `artifacts/probe-fast-thermal.jpg`).

Regression checks passed with 80 candidate targets: off-screen models were
rejected, partly visible bounds and targets beyond index 24 were retained, and
one draw failure did not abort subsequent targets. A 120-frame illuminator
harness verified throttling, world-only lighting, and immediate cleanup when
disabled. Flight simulations at 33/66/100 Hz reached the same 346.285 units/s
after one second and settled below 1 unit/s after release. Updated server and
client code loaded live without addon errors. Previews removed their temporary
entities and hooks; no player position, weapon, or vision preference was changed.

Crowd follow-up: the client had 109 entities, including many inventory weapons.
The previous thermal pass considered weapons with valid models even when their
owner had holstered them: normal engine rendering can hide those world models
without setting GetNoDraw. The heat pass now checks each owned weapon against
its character owner's active weapon every frame. Dropped weapons, active
weapons, and weapons owned by non-character entities remain eligible; there is
no target-count cap or delayed refresh when switching an already cached weapon.
The heat pass also requests STUDIO_NOSHADOWS and, when supported by the engine,
STUDIO_SKIP_FLEXES and STUDIO_SKIP_DECALS to avoid redundant rendering work.

Diagnostics also found an external debug hook with the `crl` mask (calls,
returns, and lines). Its performance impact was not measured or changed. The
initial flight expired before the passive hook profile completed, so those
inactive-hook timings do not measure crowded flight performance. The server
debugger then reset its connection and refused reconnection; client-side direct
execution did not respond. Consequently the final crowd changes were checked
with source inspection and `git diff --check`, but were not injected or verified
in a live Lua runtime. No crowded-scene FPS improvement is claimed yet.

NPC crowd rendering was reworked after the debugger became available again.
During thermal vision, eligible opaque NPCs/NextBots now use the existing unlit
heat material in their normal engine draw and write a stencil mask. The cold
scene filter excludes those pixels, removing the second NPC model submission
and avoiding the original skin-material shading. Stencil depth testing retains
occlusion. The existing extra model pass remains for other entity types and for
custom/translucent NPCs that did not contribute to the mask in that frame. No
target-count cap was reintroduced. NPC render overrides are cached across scans
and restored when thermal/control ends, on shutdown, and before hot reload;
original scripted draws and overrides are chained rather than discarded.

Live checks used the existing crowd of 54 NPCs, later enlarged to 75. The initial
mask version was visually checked for alignment and all crowd silhouettes
highlighted (`artifacts/probe-npc-single-pass.jpg`). After the material was moved
into the normal draw, runtime checks confirmed that all 75 tracked NPCs had
contributed to the mask and that their original callbacks restored successfully.
Later screenshot attempts returned nil from render.Capture, so the final
material/filter variant did not receive an additional image-based visual check.

Thirty warm frames per version measured the former thermal screen-effects hook
at approximately 7.6–9.1 ms and the replacement at 1.1–1.3 ms, with approximately
1.1–1.2 ms in mask setup/teardown hooks. These hook timings exclude NPC callbacks
executed within normal engine drawing and do not represent full rendering cost.
Total frame time remained approximately 50 ms in the preview comparison: an
overall FPS increase has not been demonstrated. Optical and night-vision logic
was not changed in this update. The user clarified that the reported drop is
specific to thermal vision.

Temporary preview hooks/models were removed, vision preferences restored, and
the final source loaded live. Runtime mask/restoration checks and
`git diff --check` passed without addon Lua errors. One oversized test upload
hit the debugger transport's net-message limit; splitting the upload resolved it.

Stationary hover bob was added to server movement: a continuous sinusoidal
vertical offset of up to three Source units either side of the hover centre
(approximately 11.4 cm total travel, one cycle every 3.49 seconds). The blend
fades out with movement input or propulsion velocity. Body and first-person
camera share the actual entity position, requiring no extra rendering effect.
The bob has its own swept hull collision and tracks only displacement actually
applied, avoiding accumulated height drift when blocked by floors or ceilings.

The updated entity methods loaded into the live server without Lua errors.
Runtime simulations using the actual hover helper and movement block passed
at 33, 66, and 100 Hz: position stayed within the expected +/-3-unit envelope,
movement faded the offset back to zero, repeated clipped cycles retained the
same hover centre, and a start-solid trace did not move the entity. The collision
checks used a simulated floor/ceiling trace; they are not a manual map-collision
flight test. `git diff --check` passed.

Pilot background audio was added in `lua/autorun/client/probe_droid_audio.lua`.
The supplied files are named `probedroidhover.wav` and
`probedroidspeak1.wav`–`probedroidspeak3.wav` (with the `r` in "droid"). All
four are stereo, 44.1 kHz, 16-bit PCM WAVs. Hover duration is 18.533 seconds;
the speech clips are approximately 1.602, 1.034, and 1.515 seconds. The hover
file has no embedded loop markers, so the client uses a native looping BASS
channel (`sound.PlayFile` with `noplay noblock` and `EnableLooping(true)`).
Separate non-looping channels play speech over the hover, starting after a
random 3–7 seconds and leaving a random 5–12 seconds after each finished clip.
Consecutive repetitions and overlapping speech are avoided. Hover/speech
volumes default to 0.3/0.7 and have separate client convars. Channels stop on
control exit, death, redeployment, shutdown, and hot reload; late asynchronous
loads are stopped rather than starting stale audio. Playback is pilot-only.

Actual WAV headers and paths were checked. A runtime harness using the real
audio controller passed checks for one hover load, loop configuration,
independent speech, timing, non-repetition, live volume changes, exit/shutdown
cleanup, late callbacks, and bounded retries after load errors. The client
compiled the new script successfully, and its Lua file plus all four assets
were registered with the live server for client download. The current live
client reported all four sound assets absent, so audible playback and looping
across the 18.533-second boundary could not be verified before reconnecting.
No audio assets were rewritten. `git diff --check` passed.

Observer audio was added after the pilot-only implementation. Clients now keep
one audio session per nearby drone, using distance fading and left/right pan
for observers and a centered background mix for their own controlled drone.
Discovery runs at 4 Hz, with 1600-unit entry and 1800-unit exit ranges to avoid
reloading channels repeatedly near the boundary. Existing volume convars affect
each listener's mix. The server now chooses random non-repeating speech and
publishes a timestamped NW2 cue per drone; clients seek past delivery latency
and ignore stale cues, rather than choosing different speech independently.

Native 3D playback of the supplied stereo hover WAV was attempted with
`3d mono noplay noblock`; BASS rejected it with BASS_ERROR_NO3D (21). Therefore
the implementation retains the original files and uses their working 2D native
loop channels with distance/pan mixing. It does not implement wall occlusion or
Doppler effects. No additional audio conversion or asset download was required.

Runtime harnesses passed for pilot/observer sessions, distance fading, left/right
pan, shared speech indices, latency seeking, old-cue suppression, range-boundary
hysteresis, exit/removal cleanup, stale asynchronous callbacks, and server speech
scheduling. Both live clients reported all four WAV assets available. A temporary
drone was placed near the second player without taking control of either player:
that observer client reported one observer session, a playing hover channel, and
a playing speech channel. The test drone was removed after 2.5 seconds. Updated
server and client code loaded live without addon Lua errors.

### Datapad controller models

Replaced the SLAM viewmodel/worldmodel with `sw_datapad_v.mdl` and
`sw_datapad.mdl` under `models/swcw_items/`. Inspected the mounted original
`weapon_sw_datapad` source: it uses `slam`, `UseHands = true`, and viewmodel
FOV 54; the controller matches those settings. Live server and client confirmed
both model files are mounted. A temporary newly spawned controller passed
worldmodel, viewmodel property, and hold type assertions and was removed.
No controller was held during the check, so the equipped first-person appearance
was not visually verified.

### Drone lag follow-up (automated checks only)

The thermal fallback was resubmitting native opaque NPCs when the engine had
skipped their normal draw through visibility/occlusion culling. The fallback
now respects those culling decisions while retaining custom/translucent models,
externally replaced draw callbacks, and views without an opaque heat mask.
Depth/shadow passes keep their original materials and flags. Thermal and night
tints now multiply the existing framebuffer directly, removing a second screen
copy and texture sample while preserving framebuffer alpha.

HUD sensor work is spread across updates: at most one aiming trace, six depth
traces and four radar traces per update, versus the former burst of up to 34.
Completed depth/radar sweeps replace the previous data together. Depth sweeps
use a consistent camera snapshot, and repeated paints in the same frame do not
repeat the scan work.

The actual Lua source passed the offline regression suites in `tests/`, using a
local Lua 5.1-compatible runtime. Eighty visible native NPCs each submitted one
normal draw; eighty engine-culled native NPCs submitted no fallback draws. The
same culling check failed against the pre-fix source with an extra draw per NPC.
Custom/translucent/BOTH fallbacks, externally replaced overrides, missing mask
setup, shadow/SSAO passes, range/frustum checks, inventory weapon filtering,
draw-error isolation, and cleanup on sensor exit/control exit/reload/shutdown
passed. The tint check verified one screen copy (inside the color-modify pass),
the blend factors that preserve alpha, and blend/material/stencil cleanup.

HUD tests passed for the 11-trace ceiling, scan cadence, all 17 depth samples,
16 radar candidates, coherent snapshots, removed/dead/out-of-range targets,
occlusion, slow-frame completion, and control changes. All six addon Lua files
passed syntax checks. Run `powershell -NoProfile -ExecutionPolicy Bypass -File
tests/run.ps1`; see `tests/README.md` for runtime selection. Tests are excluded
from Workshop packaging.

These tests simulate engine callbacks and validate work submission and cleanup;
they do not measure GPU rendering or game FPS. This follow-up was not injected
or visually checked in a live client. A fixed-camera comparison in a crowded
scene, including NPCs behind walls, remains necessary to measure total frame
time and confirm the tint on the user's renderer.

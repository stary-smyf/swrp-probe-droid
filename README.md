# Controllable Probe Droid

Place this folder in `garrysmod/addons/probe_droid`, then restart the map/server.
Install and mount the model addon on the server **and every client**:
`models/starwars/syphadias/ships/probe_droid/probe_droid.mdl`.
The model and its materials are not included here. If using Workshop distribution,
add the original model addon's Workshop ID to your server collection/download setup.

The controller uses the Star Wars Datapad models. Mount their original addon on
the server and every client as well: `models/swcw_items/sw_datapad_v.mdl` and
`models/swcw_items/sw_datapad.mdl`. It uses the original datapad's `slam` hold type
and viewmodel FOV of 54.

In Sandbox, open **Weapons > Star Wars > Probe Droid Controller**.
Alternatively, use `give weapon_probe_droid` in the console where permitted.
Left click in an open area to spawn the probe and immediately enter its camera.
Deployment requires standing still on the ground. Moving, jumping, falling,
and noclip block deployment until you stop and land.
Successful deployment plays a mechanical startup sound from the drone, audible
to its pilot and nearby players.

| Control | Action |
| --- | --- |
| Mouse | Look/steer |
| Left click (in flight) | Cycle zoom: 1x / 3x / 6x / 1x |
| W / S | Fly forward/back along the camera direction |
| A / D | Strafe |
| Space / Ctrl | Ascend / descend |
| Shift | Boost (1.8x speed) |
| R (reload binding) | Toggle Splinter Cell thermal vision |
| N | Toggle night vision |
| Right click (secondary attack binding) | Toggle stealth |
| Hold E for 2 seconds | Destroy the probe and return to your body |

Your body stays at the launch point and remains vulnerable. The drone settles
into a hover after releasing the controls and collides with the map, props, and
other players. Holding E shows an exit countdown and progress bar; releasing
it before two seconds cancels the exit.
Zoom starts at 1x for each flight. The HUD shows the current magnification;
mouse sensitivity scales down at 3x and 6x for precise aiming.
Flight accelerates smoothly and glides briefly when you release movement;
reverse thrust brakes the drift. The first-person camera banks and sways with
motion. Set `probe_droid_camera_sway 0` to disable camera movement, or choose a
strength between `0` and `1`. Steering remains immediate.
While stationary, the drone gently bobs up and down continuously (six Source
units peak to peak, about an 11 cm total rise/fall). The body and first-person
camera move together; the bob fades out during flight and respects collisions.
While piloting, `probedroidhover.wav` loops as background audio. The three
`probedroidspeak1.wav`–`probedroidspeak3.wav` clips play over it, with a random
5–12 second pause after each clip and no consecutive repeat. Nearby players also
hear the drone, with distance fading and left/right panning; the pilot keeps a
centered background mix. The server chooses the speech clip and timing for all
listeners. Observers begin hearing drones within about 30 m and audio fades out
fully by about 34 m. Audio stops when the drone is removed or leaves hearing
range. Set `probe_droid_hover_volume` (default
`0.3`) and `probe_droid_speech_volume` (default `0.7`) between `0` and `1` to mix
the sounds on each listener's client. The WAV files live in `sound/probe_droid/`; native audio looping
handles the hover file without requiring embedded loop markers. Clients need
the sound assets installed through Workshop or the server's download setup.
Range is a straight-line distance from your body's launch position, not distance
travelled. Battery drains continuously during flight, including while hovering.
Battery depletion, exceeding range, or taking lethal damage destroys the probe
and returns your view. Its destruction effect does not cause explosion damage.
Pilot death, disconnect, controller removal, and map cleanup also end control.
You can deploy another probe after the controller's two-second cooldown.

NPCs hostile to the pilot can target and shoot the probe when it enters their
view with line of sight within 2000 Source units (about 38 m). Friendly NPCs
remain friendly. Right click during flight to toggle stealth; the HUD shows
its current state. Stealth immediately clears NPC aggression toward the probe
and prevents reacquisition until switched off. It does not protect your body
or prevent damage from stray bullets, explosions, or players. Each new probe
starts with stealth off. This uses Source NPC relationships; custom NextBot
or NPC addons with their own targeting systems may need separate integration.
Entering and exiting stealth play different electronic sounds. While stealth
is active, hover and speech sounds play at 25% of their configured volume for
both the pilot and nearby listeners, returning to normal when stealth ends.
During stealth, the HUD and the drone's visible model use 50% of normal opacity,
and the battery drains twice as fast. A subtle blur softens the camera view
while keeping HUD text sharp. The blur ends, and opacity and normal drain
return, when stealth is switched off.
While active, a large, bright `STEALTH ACTIVE [M2]` banner remains at full
opacity above the faded HUD, with a dark background for contrast.

Thermal imaging drains the battery at 2x the normal rate; night vision uses
1.25x. Sensor costs add to stealth's extra drain: stealth with thermal uses
3x, and stealth with night vision uses 2.25x. Switching sensors off restores
the optical rate (1x normally, 2x in stealth).

Press R while piloting to switch between optical view and the Splinter Cell NVG
**Thermal** preset. This replaces the previous red thermal effect with the
supplied NVG heat animation, colour lookup, bloom, motion blur and animated noise.
Living players, NPCs and NextBots receive the preset's heat material; props,
vehicles and weapons retain their scene materials. Models use the normal engine
rendering path and occlusion rather than an extra through-wall heat pass.
A broad client-only illuminator follows the drone camera, including when zoomed.
Entity materials, colours and render modes are restored when thermal mode or
flight ends, and the illuminator is removed. Your preferred mode is remembered.
Turning thermal off immediately restores character materials, colours and render
modes. Loading the renderer also clears heat materials left by older versions.
You can also set `probe_droid_thermal 1` or `0` in the client console. Thermal
rendering is independent of the HUD camera-effects setting. The NVG framework
does not need to be installed separately: the required native VTF/VMT assets are
included and registered for client download. Reconnect clients after installing
this update so they receive the new materials. Source attribution is recorded in
`THIRD_PARTY_NOTICES.md`. The new effect still needs live visual verification;
historical thermal screenshots and performance results describe the old renderer.

Press N to toggle night vision. Image gain and a short-range, client-only
illuminator help reveal unlit surroundings. Thermal and night vision disable
each other; switching off the selected mode returns to optical view. Night
vision and its illuminator stop when drone control ends. Use
`probe_droid_nightvision 1` or `0` to set the preference, or bind another key to
`probe_droid_toggle_nightvision`. N is ignored while typing or using menus.
The illuminator uses a small world-only light, updated at 20 Hz. Set
`probe_droid_nightvision_light 0` to disable it while retaining the image filter.

The optical HUD includes an amber reticle, heading compass, pitch scale, flight
telemetry, battery/signal meters, and a live surface-depth profile. Its proximity
radar shows nearby visible players/NPCs and an `H` marker pointing to the launch
point (the marker stays on the edge when the launch point is beyond radar range).
Contacts require line of sight and available client entity data. The surface
profile samples collision depth ahead, rather than displaying a map.
Depth and radar sweeps are spread over HUD updates, with at most 11 collision
traces in one update to avoid periodic scan bursts. A completed sweep replaces
the previous profile/contact list; the aiming readout updates five times a second.
All HUD distances use meters (`m`) and velocity uses `m/s`, with a display
conversion of 1 Source unit = 0.01905 m. For example, the default 5000-unit range
reads 95.3 m. Server range/speed settings still use Source units.
Set `probe_droid_hud_effects 0` in the client console to disable scanlines, edge
shading, and weak-signal interference while retaining all instruments.
Instruments are cached and refresh at 20 Hz by default; the world, camera, and
heat highlights still render every frame. Use `probe_droid_hud_fps 30` for faster
instrument updates, or `15` to reduce HUD work further (supported range 15–60).
HUD dimensions and fonts update automatically when the resolution/window size
changes. Smaller screens use shorter labels and two control rows. Use
`probe_droid_hud_scale 1.2` to enlarge the instruments (`1` is the default;
supported preference range is `0.6` to `1.5`). The layout limits enlargement when
necessary to keep instruments on screen, including on 4:3 and ultrawide displays.

Server console settings (also usable in `server.cfg`):

```cfg
probe_droid_battery 120
probe_droid_range 5000
probe_droid_speed 350
probe_droid_health 60
```

Battery is in seconds; range and speed use Source units. Battery, range, and health
are captured when a probe launches; speed changes affect active flights.
The old saved 3000-unit range is upgraded to 5000 once, including deployed
probes using that range. Other configured ranges are preserved. Restart the
server or reload the addon to apply the upgrade.
The supplied model is automatically scaled to fit a 56-unit-wide, 72-unit-tall
envelope while preserving its proportions. No model physics mesh is required.

## In-game verification

With armed Combine NPCs hostile to you, deploy into their line of sight within
2000 units. Confirm they aim at and damage the probe. Right click: confirm
`STEALTH ACTIVE` appears and they stop targeting the drone. Hold the button to
check it does not toggle repeatedly, then release and click again to reveal the
probe and allow reacquisition. Repeat behind a wall and with friendly citizens;
neither should start shooting the probe. Your exposed body can still be attacked.

1. Deploy in an open area. Confirm immediate first-person control, hidden controller,
   working movement/boost, and a stationary player body (inspect with another player).
2. Fly into walls, floors, ceilings, props, and players; verify collisions block flight.
3. Set `probe_droid_battery 5`, deploy, and hover. Confirm destruction and restored
   body movement/view when the timer runs out.
4. Set `probe_droid_range 200`, deploy, and fly away. Confirm signal warning and
   destruction beyond the limit. Restore defaults after checking.
5. End flight with E, shoot the drone, kill its pilot, remove the controller, and run
   map cleanup during separate flights. Confirm control always ends cleanly.
6. Test with two players piloting separate drones and verify camera visibility across
   map areas. Confirm each player's controls and telemetry remain independent.

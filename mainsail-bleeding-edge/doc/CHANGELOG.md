# Changelog

## 0.2.3-experiment

- Fluidd comes back on port 80 when Mainsail is moved off it. Until now Mainsail pushed Fluidd to
  port 81 when it took port 80 and never gave port 80 back, so a printer whose Mainsail was moved
  again ended up with both interfaces on the same port, and the one the web server dropped answered
  nowhere. The rule the plugin now keeps at every start and stop: whichever interface is set to port
  80 holds it, the other one is on 81.
- The port is written into the Fluidd site file the web server actually serves. On a printer where
  that file is a plain copy rather than the stock link, the change used to go into the copy nobody
  reads, so Fluidd stayed on the same port as Mainsail and disappeared.

## 0.2.2-experiment

- The remote screen, and any other plugin that adds a page to the printer, now opens when Mainsail
  is set to port 80. Until now Mainsail answered those addresses with its own page and an empty
  panel, because its web server did not know where plugins put their pages. Updating this plugin
  fixes it; nothing else needs reinstalling. On a printer where Mainsail is on port 81, the plugin
  pages worked already and now work on both ports.

## 0.2.1-experiment

- The Extruder panel no longer disappears from the dashboard and from Interface Settings when the
  printer is open in a second browser or a second tab. Snapmaker's firmware was answering Mainsail
  out of another tab's cached status, and that cache never holds the printer's configuration, so
  Mainsail found no extruders in it. Mainsail now asks in a way the firmware cannot answer from
  that cache.

## 0.1.3

- AFC panel fix for toolchangers: the lane Eject button now enables only when
  that lane's tool is mounted on the carrier (`laneActive`) instead of on
  filament state (`tool_loaded`). On a toolchanger the upstream behavior greyed
  Eject out exactly when a tool was mounted and loaded. Paired with afc-lite,
  Eject docks (parks) the mounted tool.

## 0.1.2

- Declares its Klipper restart and the restart permission explicitly, matching
  the intent-based install schema.

## 0.1.1

- Configurable HTTP port. Runs on port 81 by default so Fluidd keeps port 80;
  set port 80 to make Mainsail primary and Fluidd shifts to 81 automatically.

## 0.1.0

- First release. Installs Mainsail v2.17.0 as a second web frontend.

# Changelog

## 0.1.5

- AFC panel: the lane Eject button is now also disabled while the printer is
  actively printing, reusing Mainsail's own `printerIsPrintingOnly` state so it
  matches the Load/Unload buttons. Eject stays available while the print is
  paused, so filament can still be swapped mid-print. Extends the existing
  `laneActive` eject patch in the vendored bundle (no re-vendor; Mainsail stays
  v2.18.0).

## 0.1.4

- Vendored Mainsail bumped v2.17.0 to v2.18.0.
- Re-applied the toolchanger Eject gating patch (`laneActive`) from 0.1.3 to
  the new bundle; behavior unchanged.

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

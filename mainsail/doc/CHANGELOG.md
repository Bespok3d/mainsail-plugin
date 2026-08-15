# Changelog

## 0.1.9

- The AFC lane card shows the filament name the printer put in the lane: the brand, the material and
  the sub-type, "SUNLU PETG Basic", the same name you read on the slot in the slicer. The card used to
  read the name out of the spool list the browser had loaded, so a lane whose spool was not in that
  list showed "--", and Mainsail and Fluidd disagreed on every lane. They say the same thing now.
- The lane's spool picker lists what Spoolman has now. A spool you added or edited in Spoolman while
  the page was open used to be missing from it, and the only way to see it was to reload the page.
- Three buttons in the AFC panel header, next to the unit name: "Clear all spools", "Detect spools"
  and "Clear active". They fix what the printer thinks is loaded without typing gcode. "Clear all
  spools" asks before it clears.
- A bar of three buttons under every lane: add spool, write the tag onto a spool, link the tag to a
  spool. Add spool makes a new Spoolman spool out of the tag on the lane and puts it on the lane. The
  other two ask you to pick a spool from Mainsail's own spool list, then write the tag's data onto it
  or tie the tag to it. Only the button you pressed acts. The bar opens itself on a lane whose spool
  Spoolman does not know, and sits collapsed as a thin strip otherwise; click the strip to open or
  close it, and the arrow on it points the way the bar will move.
- Add spool tells you when the new spool has no weight in Spoolman, and asks you to open that filament
  in Spoolman and give it one. Without a weight nothing can track what is left on the spool.
- The header buttons and the lane bar show up only on a printer running the Bespok3d Spoolman plugin,
  because they are its commands. Without it the panel looks exactly as it did. Same buttons, same
  order, as in Fluidd.
- A lane's filament dialog asks for a weight only when the lane is on a Spoolman spool, which is where
  the weight comes from. The printer does not take a weight typed by hand, so on a lane without a
  spool the box is gone and you can set the colour and the material on their own, on a printer with no
  Spoolman at all.

## 0.1.8

- Fluidd comes back on port 80 when Mainsail is moved off it. Until now Mainsail pushed Fluidd to
  port 81 when it took port 80 and never gave port 80 back, so a printer whose Mainsail was moved
  again ended up with both interfaces on the same port, and the one the web server dropped answered
  nowhere. The rule the plugin now keeps at every start and stop: whichever interface is set to port
  80 holds it, the other one is on 81.
- The port is written into the Fluidd site file the web server actually serves. On a printer where
  that file is a plain copy rather than the stock link, the change used to go into the copy nobody
  reads, so Fluidd stayed on the same port as Mainsail and disappeared.

## 0.1.7

- The remote screen, and any other plugin that adds a page to the printer, now opens when Mainsail
  is set to port 80. Until now Mainsail answered those addresses with its own page and an empty
  panel, because its web server did not know where plugins put their pages. Updating this plugin
  fixes it; nothing else needs reinstalling. On a printer where Mainsail is on port 81, the plugin
  pages worked already and now work on both ports.

## 0.1.6

- A print sent straight from a slicer with "start printing after upload" now stops and asks which
  lane feeds which tool, in Mainsail's own start-print dialog, before it runs. It needs the
  `u1-afc-lite` plugin 0.1.10 or newer with its hold setting turned on: that plugin holds the print
  back, and this makes Mainsail notice. Without it nothing here does anything.
- The dialog opens whatever page the browser is showing, not only the file list, because it is
  Mainsail's own dialog mounted by us for a held print. Dismissing it drops the held print, printing
  releases it, and every other browser with Mainsail open clears its own dialog when any one of them
  answers.
- The dialog lists the file's tools on a Snapmaker printer, each in the colour the file was sliced
  with. Snapmaker's Moonraker publishes the per-tool weight list under `filament_weight` where
  Mainsail reads `filament_weights`, so the dialog offered nothing at all; the swatches used to show
  the spools sitting in the printer's lanes, which matched the file only by luck.
- A tool no longer shows NO LANE after it has been assigned on a file with more tools than the
  printer has lanes. Several tools drawing from one lane is the U1's own design; the start-print
  dialog was the last place still assuming one.
- The AFC panel no longer lists T0 through T30 on the first lane. The printer keeps room for 32
  logical tools and every one your file does not use reads as fed by lane E0, so the dialog now
  tells the printer how many tools the file uses. That part needs AFC Lite 0.1.10 or newer; with an
  older one the panel keeps listing the unused tools.
- The Extruder panel no longer disappears from the dashboard and from Interface Settings when the
  printer is open in a second browser or a second tab. Snapmaker's firmware was answering Mainsail
  out of another tab's cached status, and that cache never holds the printer's configuration, so
  Mainsail found no extruders in it. Mainsail now asks in a way the firmware cannot answer from
  that cache.
- New **Hide unused tool buttons** setting, off by default. The printer's firmware keeps room for 32
  logical tools and registers a macro for each, and the printer saves a copy of each next to it, so
  the Extruder panel listed all of them on a 4 lane machine. With the setting on the panel shows one
  button per lane the printer actually has, and the saved copies are gone. The tools are still there
  and a macro can still call them, and the count comes from the printer rather than from a number
  written into the plugin. Reload the page after changing it.
- The vendored bundle's Bespok3d modifications now live in `scripts/patch-mainsail.sh`, which
  `scripts/fetch-mainsail.sh` runs after a re-vendor and the gate re-checks with `--verify`.
  Re-vendoring used to drop the Eject patch and it was put back by hand. Mainsail stays v2.18.0.

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

# Mainsail

Installs the [Mainsail](https://docs.mainsail.xyz/) web interface as a second frontend
alongside Fluidd, on a port you choose.

## What it does

- Serves Mainsail v2.18.0.
- Runs on port 81 by default, so Fluidd stays on port 80.
- Set the port to 80 to make Mainsail primary; Fluidd then moves to 81 automatically. Move
  Mainsail off 80 again and Fluidd goes back to it: whichever interface is set to 80 holds it,
  the other one is on 81.
- A print-start dialog that maps the file's tools onto your AFC lanes before the print begins.

## Mapping lanes for a print sent from the slicer

The lane assignment dialog opens when you start a print from the file list. A print sent from the
slicer with "start printing after upload" begins on the printer with no browser involved, so nothing
opened it and the file ran with whatever map was left over.

Install the AFC Lite plugin and turn on its **Filament to tools mapper** setting, and the printer
keeps that print from starting. Mainsail then opens the same dialog on the
file being held back, whatever page you are on, and its print button sets the map and starts it. The
print waits as long as it takes, and dismissing the dialog drops it instead of starting it.

Nothing changes without AFC Lite and that setting: the printer never holds a print, and starting one
from the file list works exactly as before.

## Hiding the tool buttons your printer has no lane for

The U1's firmware keeps room for 32 logical tools and registers a macro for every one of them, plus a
saved copy of each, so the Extruder panel lists them all on a printer with 4 lanes.

Turn on the plugin's **Hide unused tool buttons** setting and the panel shows one button per lane the
printer actually has, with the saved copies gone. Nothing is removed from the printer: the tools are
still there and a macro can still call them. The count comes from the printer, so a machine with a
different number of lanes shows its own. Reload the page after changing the setting.

## The spool bar under a lane

On a printer running the Bespok3d Spoolman plugin, every lane in the AFC panel carries a small bar
with three buttons:

- **Add spool**: makes a new Spoolman spool from the tag on the lane, ties the tag to it, and puts
  it on the lane.
- **Update spool data**: pick a spool, and the tag's data is written onto it.
- **Link spool**: pick a spool, and the tag is tied to it.

Picking a spool uses Mainsail's own spool list, the same one the lane's reel opens.

The bar opens itself on a lane whose spool Spoolman does not know, and sits collapsed as a thin
strip otherwise. Click the strip to open or close it.

Without the Spoolman plugin there is no bar and no buttons in the panel header: those are its
commands, and the panel looks exactly as upstream draws it.

## Configuration

- **Mainsail port** (default `81`): the port Mainsail listens on.
- **Hide unused tool buttons** (default `off`): see above.

## Access

`http://<printer-ip>:81/` (or `:80` if you made it primary).

## Notes

- Snapmaker U1.
- Use it instead of, or alongside, the **Fluidd** plugin; both can run at once on different
  ports.

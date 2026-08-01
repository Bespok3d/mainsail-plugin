# Mainsail

Installs the [Mainsail](https://docs.mainsail.xyz/) web interface as a second frontend
alongside Fluidd, on a port you choose.

## What it does

- Serves Mainsail v2.18.0.
- Runs on port 81 by default, so Fluidd stays on port 80.
- Set the port to 80 to make Mainsail primary; Fluidd then moves to 81 automatically.
- A print-start dialog that maps the file's tools onto your AFC lanes before the print begins.

## Mapping lanes for a print sent from the slicer

The lane assignment dialog opens when you start a print from the file list. A print sent from the
slicer with "start printing after upload" begins on the printer with no browser involved, so nothing
opened it and the file ran with whatever map was left over.

Install the AFC Lite plugin and turn on its **Hold a print until the lane-to-tool map is made**
setting, and the printer keeps that print from starting. Mainsail then opens the same dialog on the
file being held back, whatever page you are on, and its print button sets the map and starts it. The
print waits as long as it takes, and dismissing the dialog drops it instead of starting it.

Nothing changes without AFC Lite and that setting: the printer never holds a print, and starting one
from the file list works exactly as before.

## Configuration

- **Mainsail port** (default `81`): the port Mainsail listens on.

## Access

`http://<printer-ip>:81/` (or `:80` if you made it primary).

## Notes

- Snapmaker U1.
- Use it instead of, or alongside, the **Fluidd** plugin; both can run at once on different
  ports.

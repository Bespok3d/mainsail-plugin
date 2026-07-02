# Mainsail

Installs the [Mainsail](https://docs.mainsail.xyz/) web interface as a second frontend
alongside Fluidd, on a port you choose.

## What it does

- Serves Mainsail v2.18.0.
- Runs on port 81 by default, so Fluidd stays on port 80.
- Set the port to 80 to make Mainsail primary; Fluidd then moves to 81 automatically.

## Configuration

- **Mainsail port** (default `81`): the port Mainsail listens on.

## Access

`http://<printer-ip>:81/` (or `:80` if you made it primary).

## Notes

- Snapmaker U1.
- Use it instead of, or alongside, the **Fluidd** plugin; both can run at once on different
  ports.

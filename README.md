# mainsail-plugin

Mainsail web interface alongside Fluidd, on your chosen port.

A solo Bespok3d plugin repo: it ships one plugin (`mainsail`) and publishes a single index atom into `Bespok3d/main-index/atoms/`.

## Layout

```text
mainsail-plugin/
  mainsail/                  # the plugin; its dir name is the manifest .name
    manifest.json
    files/              # payload the daemon places on the printer
    doc/README.md       # rendered in-app; not deployed
  scripts/{pack.sh,generate-atom.mjs}
  .github/workflows/release.yml
  dist/                 # build output (gitignored)
```

The plugin declares WHAT (destination classes + restart hooks), never paths or raw commands; the
printer-side adapter realizes it. See `Bespok3d/doc/anatomy-of-a-plugin.md`.

## Build locally

```sh
sh scripts/pack.sh                              # -> dist/mainsail-<ver>.b3
node scripts/generate-atom.mjs --plugin mainsail     # -> dist/mainsail.atom.json
```

## Releasing

Bump `mainsail/manifest.json` `version` and push to `main`. CI packs the `.b3`, cuts a release, and
commits the atom into `Bespok3d/main-index/atoms/mainsail.atom.json`. Secret: `MAIN_INDEX_TOKEN`
(contents:write on main-index). Signing deferred.

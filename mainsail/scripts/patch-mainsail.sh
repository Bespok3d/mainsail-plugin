#!/bin/sh
# Apply every Bespok3d modification to the vendored upstream Mainsail bundle.
#
# The bundle in files/html/ is upstream's own build. These are the only edits
# this plugin makes to it, and each one exists because upstream has not taken
# the change yet. Every patch is literal text, idempotent, and fails loudly if
# its upstream text is gone: a minified chunk that changed shape must be
# re-derived by hand, never skipped silently.
#
# fetch-mainsail.sh runs this automatically after extracting a new release, so a
# re-vendor never loses a patch. Run it directly to re-check an existing tree.
#
# Usage: ./scripts/patch-mainsail.sh            apply (and re-check) every patch
#        ./scripts/patch-mainsail.sh --verify   check only, change nothing
#
# The gate runs --verify, so a vendored bundle that lost a patch fails the build.
#
# Upstream builds this bundle for browsers without optional chaining or the
# nullish operator, so every patched text stays in that dialect.

set -eu

VERIFY_ONLY=""
if [ "${1:-}" = "--verify" ]; then
  VERIFY_ONLY="yes"
fi

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HTML_DIR="$PLUGIN_DIR/files/html"
# A patch that does not depend on the Mainsail version is applied to every channel this repo
# vendors, not only to the one this script sits in.
REPO_ROOT="$(cd "$PLUGIN_DIR/.." && pwd)"
ASSETS_DIR="$HTML_DIR/assets"

if [ ! -d "$ASSETS_DIR" ]; then
  echo "ERROR: $ASSETS_DIR not found; run ./scripts/fetch-mainsail.sh first" >&2
  exit 1
fi

# Upstream chunk filenames carry a content hash that changes every release, so
# each chunk is found by its stable prefix and must resolve to exactly one file.
resolve_chunk() {
  prefix="$1"
  # shellcheck disable=SC2086 # the glob is the point: it resolves the hashed chunk name
  set -- $ASSETS_DIR/$prefix-*.js
  if [ ! -f "$1" ]; then
    echo "ERROR: no chunk matching $prefix-*.js in $ASSETS_DIR" >&2
    exit 1
  fi
  if [ "$#" -ne 1 ]; then
    echo "ERROR: $# chunks match $prefix-*.js; expected exactly one" >&2
    exit 1
  fi
  echo "$1"
}

# A file this plugin adds to the bundle, rather than an edit to upstream's own text. The vendored
# tree is deleted and re-extracted on a re-vendor, so the file has to be put back the same way a
# patch is.
install_file() {
  label="$1"
  source_file="$2"
  destination="$3"

  if cmp -s "$source_file" "$destination"; then
    echo "  $label: present"
    return 0
  fi

  if [ -n "$VERIFY_ONLY" ]; then
    echo "ERROR: $label: $(basename "$destination") is missing or out of date" >&2
    echo "  Run ./scripts/patch-mainsail.sh to install it." >&2
    exit 1
  fi

  cp "$source_file" "$destination"
  echo "  $label: installed"
}

apply_patch() {
  label="$1"
  chunk="$2"
  upstream_text="$3"
  patched_text="$4"

  # grep -F reads a newline as the start of another pattern, so a two-line patched_text matches
  # when only its first line is there and the patch silently reports itself present.
  case "$upstream_text$patched_text" in
    *"
"*)
      echo "ERROR: $label: a patch's text must be one line" >&2
      exit 1
      ;;
  esac

  if grep -qF "$patched_text" "$chunk"; then
    echo "  $label: present"
    return 0
  fi

  if [ -n "$VERIFY_ONLY" ]; then
    echo "ERROR: $label: missing from $(basename "$chunk")" >&2
    echo "  Run ./scripts/patch-mainsail.sh to apply it." >&2
    exit 1
  fi

  if ! grep -qF "$upstream_text" "$chunk"; then
    echo "ERROR: $label: upstream text not found in $(basename "$chunk")" >&2
    echo "  Upstream changed this code. Re-derive the patch by hand, then" >&2
    echo "  update this script. Do not skip it." >&2
    exit 1
  fi

  UPSTREAM_TEXT="$upstream_text" PATCHED_TEXT="$patched_text" \
    perl -0777 -i -pe 's/\Q$ENV{UPSTREAM_TEXT}\E/$ENV{PATCHED_TEXT}/g' "$chunk"

  if ! grep -qF "$patched_text" "$chunk"; then
    echo "ERROR: $label: replacement did not land in $(basename "$chunk")" >&2
    exit 1
  fi
  echo "  $label: applied"
}

APP_CHUNK="$(resolve_chunk index)"

echo "Checking Bespok3d patches in $HTML_DIR..."

# 1. AFC lane Eject gating. Upstream enables Eject only when the lane's tool is
#    NOT loaded, which is backwards for a toolchanger: on the U1 a lane can only
#    be ejected while its tool is mounted. Ours also locks Eject while a print
#    is running, matching Load/Unload, and stays usable while paused.
#    See doc/CHANGELOG.md 0.1.3, 0.1.4 and 0.1.5.
apply_patch "AFC eject gating" "$APP_CHUNK" \
  'disabled:e.toolLoaded||!e.laneRunout&&e.toolLoaded' \
  'disabled:!e.laneActive||e.printerIsPrintingOnly'

# 2. Which tools the start-print dialog offers a lane for. Upstream reads the
#    per-tool weight list under the name `filament_weights`; Snapmaker's
#    Moonraker publishes the same list as `filament_weight`, so the dialog
#    listed no tools at all on a U1. Accept either name.
#
#    This is also the one place that knows both which tools the file uses and
#    how to talk to the printer, so it is where the count is declared. The U1
#    keeps room for 32 logical tools and every entry no file ever set reads as
#    fed by the first lane, so without the count the AFC panel lists T0 through
#    T30 on lane one. The watcher returns an empty command when the printer has
#    no afc-lite or already holds the right count, so nothing is sent twice and
#    a printer without the plugin is never sent a command it would reject.
# shellcheck disable=SC2016 # $socket is a Vue property name in the bundle, not a shell variable
apply_patch "AFC dialog tool list" "$APP_CHUNK" \
  'get usedTools(){var e;let t=(e=this.file.filament_weights)==null?[]:e,n=[];return t.forEach((e,t)=>{e>0&&n.push(t)}),n}' \
  'get usedTools(){var e;let t=(e=this.file.filament_weights||this.file.filament_weight)==null?[]:e,n=[];t.forEach((e,t)=>{e>0&&n.push(t)});var b3dToolsInPlay=window.b3dAfcToolmap&&this.$socket?window.b3dAfcToolmap.toolsInPlayDeclaration(n):"";return b3dToolsInPlay&&this.$socket.emit("printer.gcode.script",{script:b3dToolsInPlay}),n}'

# 3. The weight shown on a per-tool row inside that dialog, same field-name
#    reason as 2. Upstream already splits the semicolon-joined name and type
#    Snapmaker publishes, so only the weight needs a second name here.
apply_patch "AFC dialog tool row" "$APP_CHUNK" \
  'u=(r=this.file.filament_weights)==null?[]:r;' \
  'u=(r=this.file.filament_weights||this.file.filament_weight)==null?[]:r;'

# 3b. The colour shown for each tool in that dialog. Upstream reads
#    `filament_colors`, which on a U1 is not the file's colours at all: the
#    printer builds that list from the spools sitting in its own lanes, so the
#    dialog showed the lane colours and not the ones the file was sliced with.
#    The slicer's own per-filament colours arrive as `filament_colour`, one
#    semicolon-joined string, which the bundle already knows how to split. Fall
#    back to the old field, which is all a non-Snapmaker Moonraker publishes.
apply_patch "AFC dialog tool colour" "$APP_CHUNK" \
  'let s=(e=this.file.filament_colors)==null?[]:e,' \
  'let s=this.file.filament_colour?Zc(this.file.filament_colour):(e=this.file.filament_colors)==null?[]:e,'

# 4. Hand the start-print dialog out. Upstream opens it from a file-list row,
#    which owns its own copy, so a browser sitting on any other page has no
#    dialog at all. The watcher below mounts one of its own instead, and this is
#    how it gets hold of upstream's component to mount.
apply_patch "Start-print dialog handed out" "$APP_CHUNK" \
  'var qh=W(Kh,function(){' \
  'var qh=window.b3dStartPrintDialog=W(Kh,function(){'

# 5. Open that dialog for a print the printer is already holding. A print sent from a slicer with
#    "start printing after upload" never reaches a browser, so upstream's trigger (opening the
#    dialog from the file list) never fires and the file runs with whatever map was left over. The
#    afc-lite plugin keeps such a print from starting and raises a flag; the watcher below opens
#    the dialog on it. Inert on a printer without afc-lite, which never raises the flag.
install_file "AFC toolmap watcher" \
  "$PLUGIN_DIR/patches/afc-toolmap.js" \
  "$HTML_DIR/b3d-afc-toolmap.js"

apply_patch "AFC toolmap watcher loaded" "$HTML_DIR/index.html" \
  '<div id="app"></div>' \
  '<div id="app"></div><script src="/b3d-afc-toolmap.js"></script>'

# 6. Mainsail installs a service worker that serves index.html from its own cache and only refetches
#    it when the revision string next to it changes. Without this the browsers that already have
#    Mainsail keep the page without the script tag, and the watcher never loads for them.
apply_patch "AFC toolmap watcher cached" "$HTML_DIR/sw.js" \
  '{url:"index.html",revision:"ec818674470b1a5a042b3c94b6a3f05e"}' \
  '{url:"index.html",revision:"b3d-afc-toolmap-5"}'

# 7. The dialog's print button. A held print has not started yet and its file has not been
#    selected, so upstream's call would start it without the map that was just made; releasing the
#    hold is what starts it. With no print held, and on a bundle where the watcher never loaded,
#    this is upstream's own behaviour.
# shellcheck disable=SC2016 # $socket is a Vue property name in the bundle, not a shell variable
apply_patch "AFC toolmap release" "$APP_CHUNK" \
  'startPrint(e=``){e=(this.currentPath+`/`+e).substring(1),this.closeDialog(),this.$socket.emit(`printer.print.start`,{filename:e},{action:`switchToDashboard`})}' \
  'startPrint(e=``){if(window.b3dAfcToolmap&&window.b3dAfcToolmap.releaseHeldPrint()){this.closeDialog(),this.$socket.emit("printer.gcode.script",{script:"AFC_TOOLMAP_GO"});return}e=(this.currentPath+`/`+e).substring(1),this.closeDialog(),this.$socket.emit(`printer.print.start`,{filename:e},{action:`switchToDashboard`})}'

# 8. Moonraker's subscription cache. Snapmaker's firmware answers printer.objects.subscribe out of
#    another connection's cached status whenever every object asked for is already covered, and
#    Moonraker never caches configfile.settings. The second browser to open the page, and every
#    later subscribe the first one makes, therefore gets a configfile with the settings stripped
#    out: Mainsail reads no extruders from it and drops the Extruder panel from the dashboard and
#    from the interface settings. Asking as well for one object name the printer has never heard
#    of, different on every call, means no other subscription can cover the request and the printer
#    is asked for real. Klipper answers an unknown object with nothing and logs nothing, so this
#    costs one empty entry in the reply.
#
#    The name has to be new on every call, not once per page load: the connection's own previous
#    subscription counts as covering it, so a page that reused one name lost its settings again on
#    its second subscribe. Measured on the bench printer.
CACHE_BUST_KEY='{["b3d_cachebust_"+Math.random().toString(36).slice(2,10)]:null}'

channels_cache_busted=0
for app_chunk in "$REPO_ROOT"/*/files/html/assets/index-*.js; do
  [ -f "$app_chunk" ] || continue

  channel_path="${app_chunk#"$REPO_ROOT"/}"
  channel="${channel_path%%/*}"

  # The subscribe Mainsail makes when it has found new printer objects to watch.
  # shellcheck disable=SC2016 # the backticks are a JavaScript string literal in the bundle, not shell
  apply_patch "Moonraker cache bust on new objects ($channel)" "$app_chunk" \
    'e(`sendObj`,{method:`printer.objects.subscribe`,params:{objects:i},action:`getData`})' \
    'e(`sendObj`,{method:`printer.objects.subscribe`,params:{objects:Object.assign({},i,'"$CACHE_BUST_KEY"')},action:`getData`})'

  # The one it waits on a reply for, which is where it reads the bed screw positions.
  # shellcheck disable=SC2016 # the backticks are a JavaScript string literal in the bundle, not shell
  apply_patch "Moonraker cache bust on a waited reply ($channel)" "$app_chunk" \
    'emitAndWait(`printer.objects.subscribe`,{objects:n},{})' \
    'emitAndWait(`printer.objects.subscribe`,{objects:Object.assign({},n,'"$CACHE_BUST_KEY"')},{})'

  # The same cache answers printer.objects.query. Mainsail waits on both of these before it will
  # draw anything, so an answer the firmware already gave another connection leaves the page on its
  # loading screen for good.
  # shellcheck disable=SC2016 # the backticks are a JavaScript string literal in the bundle, not shell
  apply_patch "Moonraker cache bust on the gcode command list ($channel)" "$app_chunk" \
    'emitAndWait(`printer.objects.query`,{objects:{gcode:[`commands`]}},{})' \
    'emitAndWait(`printer.objects.query`,{objects:Object.assign({gcode:[`commands`]},'"$CACHE_BUST_KEY"')},{})'

  # shellcheck disable=SC2016 # the backticks are a JavaScript string literal in the bundle, not shell
  apply_patch "Moonraker cache bust on the extruder query ($channel)" "$app_chunk" \
    'emitAndWait(`printer.objects.query`,{objects:r},{})' \
    'emitAndWait(`printer.objects.query`,{objects:Object.assign({},r,'"$CACHE_BUST_KEY"')},{})'

  # printer.objects.list carries no objects, so there is nothing inside it to vary. Moonraker
  # ignores a parameter it does not know, checked on the bench printer, so a throwaway parameter
  # makes the request new without changing the answer.
  # shellcheck disable=SC2016 # the backticks are a JavaScript string literal in the bundle, not shell
  apply_patch "Moonraker cache bust on the waited object list ($channel)" "$app_chunk" \
    'emitAndWait(`printer.objects.list`)' \
    'emitAndWait(`printer.objects.list`,'"$CACHE_BUST_KEY"',{})'

  # shellcheck disable=SC2016 # the backticks are a JavaScript string literal in the bundle, not shell
  apply_patch "Moonraker cache bust on the object list ($channel)" "$app_chunk" \
    '{method:`printer.objects.list`,action:`getObjectsList`}' \
    '{method:`printer.objects.list`,params:'"$CACHE_BUST_KEY"',action:`getObjectsList`}'

  # Mainsail's service worker precaches the hashed chunk with a null revision, which tells it the
  # URL can never change its contents. A browser that already holds this build would go on serving
  # the unpatched chunk from its own cache forever; giving the entry a revision is what makes it
  # fetch ours. Bump the revision string whenever the patches above change.
  apply_patch "Moonraker cache bust served fresh ($channel)" "${app_chunk%/assets/*}/sw.js" \
    "{url:\"assets/$(basename "$app_chunk")\",revision:null}" \
    "{url:\"assets/$(basename "$app_chunk")\",revision:\"b3d-cachebust-11\"}"

  channels_cache_busted=$((channels_cache_busted + 1))
done

if [ "$channels_cache_busted" -eq 0 ]; then
  echo "ERROR: Moonraker cache bust: no vendored Mainsail bundle found under $REPO_ROOT" >&2
  exit 1
fi

# 9. The Extruder panel's tool buttons. The U1 registers a T0 to T31 gcode macro whatever it has
#     lanes for, and the printer saves a T0.10001 style macro next to each, so the panel lists them
#     all on a 4 lane printer. The settings file the daemon renders at install says whether the
#     plugin's "Hide unused tool buttons" setting is on and holds the rule; the panel asks it,
#     passing the printer's own objects so the lane count comes from the printer and never from a
#     number written here. With the setting off, and on a bundle where the settings file never
#     loaded, every tool is kept, which is upstream's own behaviour.
install_file "Tool button rule" \
  "$PLUGIN_DIR/files/b3d-tool-buttons.js.tmpl" \
  "$HTML_DIR/b3d-tool-buttons.js"

apply_patch "Tool button rule loaded" "$HTML_DIR/index.html" \
  '<script src="/b3d-afc-toolmap.js"></script>' \
  '<script src="/b3d-afc-toolmap.js"></script><script src="/b3d-tool-buttons.js"></script>'

# shellcheck disable=SC2016 # $store is a Vue property name in the bundle, not a shell variable
apply_patch "Extruder panel hides unused tools" "$APP_CHUNK" \
  'Object.keys(r).filter(e=>e.match(/^T\d+/)).sort(n)' \
  'Object.keys(r).filter(e=>e.match(/^T\d+/)&&(!window.b3dToolButtons||window.b3dToolButtons.keepsToolButton(e,this.$store.state.printer))).sort(n)'

# 10. Which name the AFC tool map shows. Upstream reads the name off the Spoolman record the
#     browser has cached and shows "--" when that record is missing, so the description the printer
#     pushes into the lane never reaches it at all. The Bespok3d Spoolman helper pushes the filament
#     description the printer publishes to the slicer into that lane field on purpose, because the
#     card already prints the material and the colour on their own lines. Read the lane first and
#     keep upstream's Spoolman name as the fallback, so a printer without the helper shows exactly
#     what it showed before.
# shellcheck disable=SC2016 # the backticks are a JavaScript string literal in the bundle, not shell
apply_patch "AFC lane name" "$APP_CHUNK" \
  'name:(i=u==null||(a=u.filament)==null?void 0:a.name)==null?`--`:i,' \
  'name:(c==null?void 0:c.filament_name)||(u==null||(a=u.filament)==null?void 0:a.name)||`--`,'

# 11. The name on the AFC lane CARD, which is a different getter from the tool map above and was
#     left behind by 10. Upstream already falls back to the lane field, but only when the browser
#     cannot resolve the Spoolman record, so a printer that resolves it showed Spoolman's own
#     filament name while Fluidd showed the pushed description. Same order as Fluidd now: the lane
#     first, Spoolman's name as the fallback.
# shellcheck disable=SC2016 # the backticks are a JavaScript string literal in the bundle, not shell
apply_patch "AFC lane card name" "$APP_CHUNK" \
  'get spoolFilamentName(){var e;return((e=this.spool)==null||(e=e.filament)==null?void 0:e.name)||this.lane.filament_name||`Unknown`}' \
  'get spoolFilamentName(){var e;return this.lane.filament_name||((e=this.spool)==null||(e=e.filament)==null?void 0:e.name)||`Unknown`}'

# 12. The Bespok3d Spoolman buttons in the AFC unit header. The Spoolman Klipper helper registers
#     the SH_ gcode commands and Klipper publishes every command it has registered, so the rule file
#     below draws a button only for a command this printer actually answers. On a printer without
#     that plugin, and on a bundle where the rule file never loaded, the header is upstream's own.
install_file "AFC Spoolman header buttons" \
  "$PLUGIN_DIR/patches/afc-spoolman-header.js" \
  "$HTML_DIR/b3d-afc-spoolman-header.js"

apply_patch "AFC Spoolman header buttons loaded" "$HTML_DIR/index.html" \
  '<script src="/b3d-tool-buttons.js"></script>' \
  '<script src="/b3d-tool-buttons.js"></script><script src="/b3d-afc-spoolman-header.js"></script>'

apply_patch "AFC Spoolman header" "$APP_CHUNK" \
  't(F),e._l(e.hubs,function(e){return t(Ug,{key:e,attrs:{name:e}})})' \
  't(F),window.b3dAfcSpoolmanHeader?window.b3dAfcSpoolmanHeader.headerButtons(t,e):[],e._l(e.hubs,function(e){return t(Ug,{key:e,attrs:{name:e}})})'

# 13. The Bespok3d Spoolman bar under every AFC lane, the same bar the Fluidd plugin draws. Same
#     rule as the header above: a button appears only for a command this printer answers, so a
#     printer without the Spoolman helper keeps upstream's lane card exactly as it is.
install_file "AFC lane toolbar" \
  "$PLUGIN_DIR/patches/afc-lane-toolbar.js" \
  "$HTML_DIR/b3d-afc-lane-toolbar.js"

apply_patch "AFC lane toolbar loaded" "$HTML_DIR/index.html" \
  '<script src="/b3d-afc-spoolman-header.js"></script>' \
  '<script src="/b3d-afc-spoolman-header.js"></script><script src="/b3d-afc-lane-toolbar.js"></script>'

#     The two buttons that need a spool open Mainsail's own spool chooser, which the bundle keeps to
#     itself. Handing the component out is what lets the bar render an instance of it in the mode
#     that reports the pick back instead of putting it on the lane.
apply_patch "Spool chooser reachable" "$APP_CHUNK" \
  'var th=W(eh,function(){' \
  'var th=window.b3dSpoolChooser=W(eh,function(){'

# shellcheck disable=SC2016 # the backticks are a JavaScript string literal in the bundle, not shell
apply_patch "AFC lane toolbar" "$APP_CHUNK" \
  ':e._e()],1)},[],!1,null,`9b0342d1`' \
  ':e._e(),window.b3dAfcLaneToolbar?window.b3dAfcLaneToolbar.laneToolbar(t,e):null],1)},[],!1,null,`9b0342d1`'

# 14. The lane filament dialog offers a weight box, and AFC Lite refuses SET_WEIGHT outright, so
#     typing in it can only ever produce an error. A lane on a Spoolman spool keeps the box, because
#     Spoolman is what owns that number; a lane without one loses it, and the dialog then sends only
#     the colour and the material the user came to set. Same behaviour as the Fluidd plugin, which
#     has upstream's own hasSpoolId getter to lean on where this bundle has none. The divider above
#     the box goes with it so the dialog has no gap where it was.
# shellcheck disable=SC2016 # $t is a Vue translation method in the bundle, not a shell variable
apply_patch "Weight box only on a Spoolman spool" "$APP_CHUNK" \
  't(c,{staticClass:`my-3`}),t(q,{attrs:{title:e.$t(`Panels.AfcPanel.Weight`),"sub-title":e.$t(`Panels.AfcPanel.WeightSubtitle`)}},[t(o,{attrs:{placeholder:`1000`,dense:``,outlined:``,type:`number`,min:0,step:1,"hide-details":``},model:{value:e.weight,callback:function(t){e.weight=t},expression:`weight`}})],1),' \
  'e.lane&&e.lane.spool_id!=null?[t(c,{staticClass:`my-3`}),t(q,{attrs:{title:e.$t(`Panels.AfcPanel.Weight`),"sub-title":e.$t(`Panels.AfcPanel.WeightSubtitle`)}},[t(o,{attrs:{placeholder:`1000`,dense:``,outlined:``,type:`number`,min:0,step:1,"hide-details":``},model:{value:e.weight,callback:function(t){e.weight=t},expression:`weight`}})],1)]:e._e(),'

#     Upstream will not let Set be pressed until a weight is typed. AFC Lite reports no lane weight,
#     so the box always opens at 0, and it refuses any weight typed in; a lane without a spool has
#     no box at all. Set therefore goes back to not waiting for a weight, as it did before this
#     version, and the dialog still sends SET_WEIGHT only once something is typed in the box.
apply_patch "Set button does not wait for a weight" "$APP_CHUNK" \
  'get disableSetBtn(){return!this.material||!this.weight||!this.color}' \
  'get disableSetBtn(){return!this.material||!this.color}'

# 15. The lane's spool picker lists what the browser fetched from Spoolman when the page loaded, so
#     a spool added or changed in Spoolman since is not in it and the only way to see it is to
#     reload the page. Re-reading Spoolman as the picker opens is what keeps the list current. Same
#     behaviour as the Fluidd plugin, whose store calls that read by another name.
# shellcheck disable=SC2016 # $store is a Vue property in the bundle, not a shell variable
apply_patch "Spool picker lists what Spoolman has now" "$APP_CHUNK" \
  'onFilamentClick(){if(this.afcExistsSpoolman){this.showSpoolmanDialog=!0;return}' \
  'onFilamentClick(){if(this.afcExistsSpoolman){this.$store.dispatch("server/spoolman/refreshSpools"),this.showSpoolmanDialog=!0;return}'

echo "Done. All Bespok3d patches are present."

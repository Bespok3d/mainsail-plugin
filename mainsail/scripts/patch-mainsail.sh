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
  'get usedTools(){var t;const s=(t=this.file.filament_weights)!=null?t:[],e=[];return s.forEach((r,i)=>{r>0&&e.push(i)}),e}' \
  'get usedTools(){var t;const s=(t=this.file.filament_weights||this.file.filament_weight)!=null?t:[],e=[];s.forEach((r,i)=>{r>0&&e.push(i)});var b3dToolsInPlay=window.b3dAfcToolmap&&this.$socket?window.b3dAfcToolmap.toolsInPlayDeclaration(e):"";return b3dToolsInPlay&&this.$socket.emit("printer.gcode.script",{script:b3dToolsInPlay}),e}'

# 3. The weight shown on a per-tool row inside that dialog, same field-name
#    reason as 2. Upstream already splits the semicolon-joined name and type
#    Snapmaker publishes, so only the weight needs a second name here.
apply_patch "AFC dialog tool row" "$APP_CHUNK" \
  'i=(l=this.file.filament_weights)!=null?l:[];' \
  'i=(l=this.file.filament_weights||this.file.filament_weight)!=null?l:[];'

# 3b. The colour shown for each tool in that dialog. Upstream reads
#    `filament_colors`, which on a U1 is not the file's colours at all: the
#    printer builds that list from the spools sitting in its own lanes, so the
#    dialog showed the lane colours and not the ones the file was sliced with.
#    The slicer's own per-filament colours arrive as `filament_colour`, one
#    semicolon-joined string, which the bundle already knows how to split. Fall
#    back to the old field, which is all a non-Snapmaker Moonraker publishes.
apply_patch "AFC dialog tool colour" "$APP_CHUNK" \
  'const e=(n=this.file.filament_colors)!=null?n:[],' \
  'const e=this.file.filament_colour?bi(this.file.filament_colour):(n=this.file.filament_colors)!=null?n:[],'

# 4. Which lane the dialog says a tool is fed from. The U1 lets many logical
#    tools draw from one lane, which the u1-afc-lite plugin reports as a list of
#    tools on the lane. Upstream's own AFC panel already reads that list; this
#    one getter still assumed a single tool, so every tool past the first showed
#    NO LANE after it had been assigned.
apply_patch "AFC lane lookup" "$APP_CHUNK" \
  'get laneName(){var t,r;return((r=(t=this.afc)==null?void 0:t.lanes)!=null?r:[]).find(i=>{var o;const n=this.getAfcLaneObject(i);return((o=n==null?void 0:n.map)==null?void 0:o.toLowerCase())===this.toolName.toLowerCase()})}' \
  'get laneName(){var t,r;return((r=(t=this.afc)==null?void 0:t.lanes)!=null?r:[]).find(i=>{const n=this.getAfcLaneObject(i),o=n==null?void 0:n.map,c=Array.isArray(o)?o:[o];return c.some(u=>u!=null&&u.toLowerCase()===this.toolName.toLowerCase())})}'

# 5. Hand the start-print dialog out. Upstream opens it from a file-list row,
#    which owns its own copy, so a browser sitting on any other page has no
#    dialog at all. The watcher below mounts one of its own instead, and this is
#    how it gets hold of upstream's component to mount.
apply_patch "Start-print dialog handed out" "$APP_CHUNK" \
  'const Ji=Ek.exports' \
  'const Ji=Ek.exports;window.b3dStartPrintDialog=Ji'

# 6. Open that dialog for a print the printer is already holding. A print sent from a slicer with
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

# 7. Mainsail installs a service worker that serves index.html from its own cache and only refetches
#    it when the revision string next to it changes. Without this the browsers that already have
#    Mainsail keep the page without the script tag, and the watcher never loads for them.
apply_patch "AFC toolmap watcher cached" "$HTML_DIR/sw.js" \
  '{url:"index.html",revision:"371e714ce82cccb77331ff4a06d1e3e1"}' \
  '{url:"index.html",revision:"b3d-afc-toolmap-1"}'

# 8. The dialog's print button. A held print has not started yet and its file has not been
#    selected, so upstream's call would start it without the map that was just made; releasing the
#    hold is what starts it. With no print held, and on a bundle where the watcher never loaded,
#    this is upstream's own behaviour.
# shellcheck disable=SC2016 # $socket is a Vue property name in the bundle, not a shell variable
apply_patch "AFC toolmap release" "$APP_CHUNK" \
  'startPrint(s=""){s=(this.currentPath+"/"+s).substring(1),this.closeDialog(),this.$socket.emit("printer.print.start",{filename:s},{action:"switchToDashboard"})}' \
  'startPrint(s=""){if(window.b3dAfcToolmap&&window.b3dAfcToolmap.releaseHeldPrint()){this.closeDialog(),this.$socket.emit("printer.gcode.script",{script:"AFC_TOOLMAP_GO"});return}s=(this.currentPath+"/"+s).substring(1),this.closeDialog(),this.$socket.emit("printer.print.start",{filename:s},{action:"switchToDashboard"})}'

# 9. Moonraker's subscription cache. Snapmaker's firmware answers printer.objects.subscribe out of
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
  apply_patch "Moonraker cache bust on new objects ($channel)" "$app_chunk" \
    's("sendObj",{method:"printer.objects.subscribe",params:{objects:r},action:"getData"})' \
    "s(\"sendObj\",{method:\"printer.objects.subscribe\",params:{objects:Object.assign({},r,$CACHE_BUST_KEY)},action:\"getData\"})"

  # The one it waits on a reply for, which is where it reads the bed screw positions.
  apply_patch "Moonraker cache bust on a waited reply ($channel)" "$app_chunk" \
    'emitAndWait("printer.objects.subscribe",{objects:t},{})' \
    "emitAndWait(\"printer.objects.subscribe\",{objects:Object.assign({},t,$CACHE_BUST_KEY)},{})"

  # Mainsail's service worker precaches the hashed chunk with a null revision, which tells it the
  # URL can never change its contents. A browser that already holds this build would go on serving
  # the unpatched chunk from its own cache forever; giving the entry a revision is what makes it
  # fetch ours. Bump the revision string whenever the patches above change.
  apply_patch "Moonraker cache bust served fresh ($channel)" "${app_chunk%/assets/*}/sw.js" \
    "{url:\"assets/$(basename "$app_chunk")\",revision:null}" \
    "{url:\"assets/$(basename "$app_chunk")\",revision:\"b3d-cachebust-1\"}"

  channels_cache_busted=$((channels_cache_busted + 1))
done

if [ "$channels_cache_busted" -eq 0 ]; then
  echo "ERROR: Moonraker cache bust: no vendored Mainsail bundle found under $REPO_ROOT" >&2
  exit 1
fi

echo "Done. All Bespok3d patches are present."

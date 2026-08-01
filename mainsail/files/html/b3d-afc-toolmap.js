// Open Mainsail's own start-print dialog when the printer is holding a print for its lane map.
//
// A print sent from a slicer with "start printing after upload" begins on the printer with no
// browser in the loop, so nothing opens that dialog and the file runs with whatever lane-to-tool
// map was left over. The afc-lite plugin keeps such a print from starting and raises
// holding_for_map on its _AFC_TOOLMAP macro. This watches for that flag, opens the dialog on the
// file being held back, lets the dialog's print button start it, and tells the printer to drop the
// print when the dialog is dismissed. Every browser that has Mainsail open gets the dialog, and
// every one of them clears it when any one of them answers.
//
// Mainsail differs from Fluidd in two ways that shape this file. Its dialog has no shared state to
// poke: each file-list row owns a boolean and mounts its own dialog, so a browser that is not on
// the Files page has no dialog to open. This mounts one instance of upstream's own dialog component
// instead, which scripts/patch-mainsail.sh exposes as window.b3dStartPrintDialog. And its file
// metadata store refuses a file whose directory the browser has never listed, which is exactly what
// a print sent straight from a slicer is, so the metadata is asked for and kept here.
//
// Nothing happens unless the printer raises the flag, which it only does when the owner turns the
// afc-lite setting on. Without afc-lite the macro does not exist and this stays inert.
//
// This file is copied into the vendored bundle by scripts/patch-mainsail.sh, which also adds the
// script tag that loads it, hands out the dialog component and re-points the dialog's print button.
// Re-vendoring re-applies all of them.
//
// Mainsail's bundle is built for browsers without optional chaining or the nullish operator, so the
// patches that go into it stay in that dialect. This file is ours and is loaded on its own, but it
// keeps the same dialect so both halves run on the same browsers.

(function bespok3dAfcToolmap() {
  var TOOLMAP_MACRO = 'gcode_macro _afc_toolmap'
  var TOOL_COUNT_MACRO = 'gcode_macro afc_tools_in_play'
  var WAIT_FOR_MAINSAIL_MS = 250
  var HELD_FILE_MODULE = 'b3dAfcToolmap'

  function mainsailRoot() {
    var appElement = document.querySelector('[data-app]')
    return appElement && appElement.__vue__ ? appElement.__vue__.$root : null
  }

  // Klipper reports a macro under the case its own config file declares, so the key is matched
  // without it rather than assumed.
  function printerObjectNamed(store, objectNameInLowercase) {
    var printerObjects = store.state.printer
    var objectName = Object.keys(printerObjects).find(function hasThatName(candidate) {
      return candidate.toLowerCase() === objectNameInLowercase
    })
    return objectName ? printerObjects[objectName] : null
  }

  function toolmapMacro(store) {
    return printerObjectNamed(store, TOOLMAP_MACRO)
  }

  function printerIsHoldingForMap(store) {
    var toolmap = toolmapMacro(store)
    return !!toolmap && Number(toolmap.holding_for_map) === 1
  }

  // Nothing has been selected while the print is held back, so print_stats.filename is empty. The
  // held request is the whole SDCARD_PRINT_FILE argument line, quoted or not.
  function fileBeingHeld(store) {
    var toolmap = toolmapMacro(store)
    var request = toolmap && toolmap.held_print ? String(toolmap.held_print) : ''
    var filename = request.match(/FILENAME\s*=\s*"?([^"]*)"?/i)
    return filename ? filename[1].trim() : ''
  }

  // A file-list row hands the dialog the file on its own and the directory it is sitting in, so a
  // held print, which is one path relative to the gcode root, is split the same way.
  function directoryHolding(gcodePath) {
    var lastSeparator = gcodePath.lastIndexOf('/')
    return lastSeparator === -1 ? '' : '/' + gcodePath.slice(0, lastSeparator)
  }

  function filenameWithoutDirectory(gcodePath) {
    return gcodePath.slice(gcodePath.lastIndexOf('/') + 1)
  }

  // Mainsail lands every socket answer in its store, and its own files/getMetadata drops one for a
  // file that is not already in the browser's file tree, so the held file gets a slot of its own.
  function registerHeldFileStore(store) {
    store.registerModule(HELD_FILE_MODULE, {
      namespaced: true,
      state: { heldFile: null },
      mutations: {
        setHeldFile: function setHeldFile(heldFileState, metadata) {
          var gcodePath = metadata && metadata.filename ? String(metadata.filename) : ''
          heldFileState.heldFile = gcodePath
            ? Object.assign({}, metadata, { filename: filenameWithoutDirectory(gcodePath) })
            : null
        }
      },
      actions: {
        heldFileMetadata: function heldFileMetadata(context, metadata) {
          context.commit('setHeldFile', metadata)
        }
      }
    })
  }

  function askPrinterForHeldFile(root, gcodePath) {
    root.$socket.emit(
      'server.files.metadata',
      { filename: gcodePath },
      { action: HELD_FILE_MODULE + '/heldFileMetadata' }
    )
  }

  // Upstream's dialog, mounted by us rather than by a file-list row, so it is there whatever page
  // the browser is showing. It renders nothing until the printer has answered with the metadata.
  //
  // A held print waits for an answer and never starts by itself, so a dialog that goes away without
  // printing has to tell the printer to drop the print, or the file stays held and the dialog comes
  // back on the next browser reload. Every way of closing it, the print button, the close button,
  // the escape key, a click outside, and the printer itself answering another browser, arrives here.
  function mountLaneAssignmentDialog(root, releaser) {
    var VueConstructor = root.$options._base
    var dialogHost = new VueConstructor({
      parent: root,
      data: function heldPrintState() {
        return { heldPath: '', dialogIsOpen: false }
      },
      computed: {
        heldFile: function heldFile() {
          return this.$store.state[HELD_FILE_MODULE].heldFile
        }
      },
      methods: {
        onDialogClosed: function onDialogClosed(isOpen) {
          this.dialogIsOpen = isOpen
          if (isOpen || !releaser.heldPrintWasAbandoned()) return
          root.$socket.emit('printer.gcode.script', { script: 'AFC_TOOLMAP_CANCEL' })
        }
      },
      render: function renderLaneAssignmentDialog(createElement) {
        if (!this.dialogIsOpen || !this.heldFile) return createElement()
        return createElement(window.b3dStartPrintDialog, {
          props: { file: this.heldFile, currentPath: directoryHolding(this.heldPath) },
          model: { value: this.dialogIsOpen, callback: this.onDialogClosed }
        })
      }
    })
    dialogHost.$mount()
    document.body.appendChild(dialogHost.$el)
    return dialogHost
  }

  // The dialog closes for three reasons: this browser answered it, another browser answered it, or
  // somebody dismissed it. Only the last one is a dismissal the printer has to be told about, and
  // the print button is the one caller of releaseHeldPrint, so it is what tells the other two apart.
  // The printer keeps room for 32 logical tools and every entry no file ever set still reads as fed
  // by the first lane, so on its own a lane cannot tell a tool this print does not use from one
  // mapped to it, and the panel lists T0 through T30 on lane one. Only the browser has the file, so
  // it says how far into that table the print about to start reaches.
  //
  // Empty when the printer has no afc-lite, which would reject the command, and empty when the
  // printer already holds the right count, so the dialog re-rendering does not re-send it.
  function toolsInPlayDeclaration(store, usedTools) {
    var toolCount = printerObjectNamed(store, TOOL_COUNT_MACRO)
    var toolsInPlay = usedTools.length ? Math.max.apply(null, usedTools) + 1 : 0
    if (!toolCount || Number(toolCount.count) === toolsInPlay) return ''
    return 'AFC_TOOLS_IN_PLAY COUNT=' + toolsInPlay
  }

  function heldPrintReleaser(store) {
    var released = false
    return {
      toolsInPlayDeclaration: function declareToolsInPlay(usedTools) {
        return toolsInPlayDeclaration(store, usedTools)
      },
      releaseHeldPrint: function releaseHeldPrint() {
        released = printerIsHoldingForMap(store)
        return released
      },
      heldPrintWasAbandoned: function heldPrintWasAbandoned() {
        return printerIsHoldingForMap(store) && !released
      },
      forgetRelease: function forgetRelease() {
        released = false
      }
    }
  }

  function watchForHeldPrints(root) {
    var store = root.$store
    registerHeldFileStore(store)
    window.b3dAfcToolmap = heldPrintReleaser(store)
    var dialogHost = mountLaneAssignmentDialog(root, window.b3dAfcToolmap)
    store.watch(
      function heldPrint() {
        return printerIsHoldingForMap(store)
      },
      function onHeldPrint(isHolding) {
        var heldPath = isHolding ? fileBeingHeld(store) : ''
        if (!heldPath) {
          dialogHost.dialogIsOpen = false
          return
        }
        window.b3dAfcToolmap.forgetRelease()
        dialogHost.heldPath = heldPath
        askPrinterForHeldFile(root, heldPath)
        dialogHost.dialogIsOpen = true
      },
      { immediate: true }
    )
  }

  function whenMainsailIsReady() {
    var root = mainsailRoot()
    if (root && root.$store && root.$socket && window.b3dStartPrintDialog) {
      watchForHeldPrints(root)
      return
    }
    window.setTimeout(whenMainsailIsReady, WAIT_FOR_MAINSAIL_MS)
  }

  whenMainsailIsReady()
})()

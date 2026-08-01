// Which tool buttons Mainsail's Extruder panel keeps.
//
// The U1 keeps room for 32 logical tools and registers a T0 to T31 gcode macro for every one of
// them, plus a saved T0.10001 style macro next to each, so the panel lists them all on a printer
// with 4 lanes. With the setting on, a saved macro and a tool whose number is past the printer's
// own extruder count are dropped from the panel. Nothing else changes: the tools are still there
// and a macro can still call them.
//
// The value below is written when the plugin is installed, from the plugin's
// "Hide unused tool buttons" setting, and rewritten when that setting is changed.

window.b3dToolButtons = {
  hideVirtualTools: "$MAINSAIL_HIDE_VIRTUAL_TOOLS" === "on",

  keepsToolButton: function keepsToolButton(toolCommand, printerObjects) {
    if (!window.b3dToolButtons.hideVirtualTools) {
      return true;
    }
    var lanesOnPrinter = Object.keys(printerObjects || {}).filter(function isExtruder(printerObject) {
      return /^extruder\d{0,2}$/.test(printerObject);
    }).length;
    if (lanesOnPrinter === 0) {
      return true;
    }
    return /^T\d+$/i.test(toolCommand) && Number(toolCommand.substring(1)) < lanesOnPrinter;
  }
};

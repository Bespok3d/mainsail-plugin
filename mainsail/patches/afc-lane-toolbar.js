// The Bespok3d Spoolman bar under every AFC lane, the same bar the Fluidd plugin draws. The Spoolman
// Klipper helper registers the SH_ gcode commands, and Klipper publishes every registered command in
// its gcode object, so a printer without that plugin gets no bar at all and the lane stays exactly as
// upstream drew it. The two buttons that need a spool open Mainsail's own spool chooser in its
// give-me-a-spool mode, the mode that reports the pick back instead of putting it on the lane.
(function attachAfcLaneToolbar() {
  var ICON_PATHS = {
    addSpool: 'M19,13H13V19H11V13H5V11H11V5H13V11H19V13Z',
    updateSpoolData: 'M9,16V10H5L12,3L19,10H15V16H9M5,20V18H19V20H5Z',
    linkSpool: 'M10.59,13.41C11,13.8 11,14.44 10.59,14.83C10.2,15.22 9.56,15.22 9.17,14.83C7.22,12.88 7.22,9.71 9.17,7.76V7.76L12.71,4.22C14.66,2.27 17.83,2.27 19.78,4.22C21.73,6.17 21.73,9.34 19.78,11.29L18.29,12.78C18.3,11.96 18.17,11.14 17.89,10.36L18.36,9.88C19.54,8.71 19.54,6.81 18.36,5.64C17.19,4.46 15.29,4.46 14.12,5.64L10.59,9.17C9.41,10.34 9.41,12.24 10.59,13.41M13.41,9.17C13.8,8.78 14.44,8.78 14.83,9.17C16.78,11.12 16.78,14.29 14.83,16.24V16.24L11.29,19.78C9.34,21.73 6.17,21.73 4.22,19.78C2.27,17.83 2.27,14.66 4.22,12.71L5.71,11.22C5.7,12.04 5.83,12.86 6.11,13.65L5.64,14.12C4.46,15.29 4.46,17.19 5.64,18.36C6.81,19.54 8.71,19.54 9.88,18.36L13.41,14.83C14.59,13.66 14.59,11.76 13.41,10.59C13,10.2 13,9.56 13.41,9.17Z',
    collapse: 'M7.41,15.41L12,10.83L16.59,15.41L18,14L12,8L6,14L7.41,15.41Z'
  }

  var LANE_ACTIONS = [
    { command: 'SH_ADD_SPOOL_FROM_TAG', label: 'Add spool', iconPath: ICON_PATHS.addSpool, picksSpool: false, addsSpool: true, offWhenSpoolIsKnown: 'This lane is already on a Spoolman spool' },
    { command: 'SH_APPLY_TAG_TO_SPOOL', label: 'Update spool data', iconPath: ICON_PATHS.updateSpoolData, picksSpool: true },
    { command: 'SH_BIND_CARD_UID', label: 'Link spool', iconPath: ICON_PATHS.linkSpool, picksSpool: true }
  ]

  // The bar remembers whether a person opened or closed it, per lane. The moment the lane's spool
  // stops or starts being one Spoolman knows, the memory is dropped and the bar goes back to its
  // own answer: open when the spool is unknown, because that is when there is something to do.
  var openBarByLaneName = {}
  var spoolPickerByLaneName = {}

  // The add is a gcode command and answers nothing. The lane carrying a spool id is the answer, and
  // a lane that never carries one was never added to, so the wait is given up on after this long
  // rather than left to greet a spool someone puts on that lane much later.
  var ADD_ANSWER_WAIT_MS = 30000

  // The refreshed spool list is a question to the printer's own Spoolman, answered in a moment or
  // not at all. Waiting the whole add wait for it would leave the message long after the click.
  var SPOOL_LIST_WAIT_MS = 5000

  var SPOOL_ADDED = 'Spool added'
  var SPOOL_ADDED_WITH_NO_WEIGHT = 'Spool added. Its filament has no weight in Spoolman, ' +
    'so what is left on the spool cannot be tracked. Open that filament in Spoolman and give it a weight.'

  function spoolmanKnowsTheSpool(laneCard) {
    return !!laneCard.spool
  }

  function barIsOpen(laneCard) {
    var spoolIsKnown = spoolmanKnowsTheSpool(laneCard)
    var remembered = openBarByLaneName[laneCard.name]
    if (remembered && remembered.spoolWasKnown === spoolIsKnown) return remembered.open
    openBarByLaneName[laneCard.name] = { open: !spoolIsKnown, spoolWasKnown: spoolIsKnown }
    return !spoolIsKnown
  }

  function toggleBar(laneCard) {
    var remembered = openBarByLaneName[laneCard.name]
    openBarByLaneName[laneCard.name] = { open: !remembered.open, spoolWasKnown: remembered.spoolWasKnown }
    laneCard.$forceUpdate()
  }

  function closeBar(laneCard) {
    openBarByLaneName[laneCard.name] = { open: false, spoolWasKnown: spoolmanKnowsTheSpool(laneCard) }
    laneCard.$forceUpdate()
  }

  // The helper addresses a lane by the printer's own channel number, which the lane publishes as
  // `lane`. A lane that does not publish one cannot be addressed, so it gets no bar.
  function laneChannel(laneCard) {
    var published = laneCard.lane ? laneCard.lane.lane : null
    return typeof published === 'number' ? published : null
  }

  function commandsThePrinterKnows(laneCard) {
    var gcodeObject = laneCard.$store.state.printer.gcode
    return (gcodeObject && gcodeObject.commands) || {}
  }

  // A button that needs a spool needs the chooser too, and the chooser reaches this file only once
  // the browser has the patched bundle. One holding the old bundle gets the buttons that ask for
  // nothing rather than buttons that answer nothing.
  function actionsThisPrinterOffers(laneCard) {
    var registered = commandsThePrinterKnows(laneCard)
    return LANE_ACTIONS.filter(function isOffered(action) {
      return action.command in registered && (!action.picksSpool || !!window.b3dSpoolChooser)
    })
  }

  function sendGcode(laneCard, script) {
    laneCard.$socket.emit('printer.gcode.script', { script: script })
  }

  function openSpoolPicker(laneCard, whenPicked) {
    spoolPickerByLaneName[laneCard.name] = { open: true, whenPicked: whenPicked }
    laneCard.$forceUpdate()
  }

  function closeSpoolPicker(laneCard) {
    spoolPickerByLaneName[laneCard.name] = { open: false, whenPicked: null }
    laneCard.$forceUpdate()
  }

  // The browser keeps its own copy of the Spoolman list, taken before the new spool existed. Until
  // that list is fetched again the lane's spool reads as unknown here: no colour, no weight, no
  // name to fall back on, and a bar that stays open because there is still something to do.
  function refreshSpoolList(laneCard) {
    laneCard.$store.dispatch('server/spoolman/refreshSpools')
  }

  // Spoolman reports what is left on a spool only when its filament carries a weight. A spool made
  // from a tag whose filament has none can never be tracked, and this message is where the user is
  // looking when it happens.
  function spoolWeightIsKnown(laneCard) {
    return spoolmanKnowsTheSpool(laneCard) && laneCard.spool.remaining_weight != null
  }

  function saySpoolWasAdded(laneCard) {
    if (!laneCard.$toast) return
    if (spoolWeightIsKnown(laneCard)) return laneCard.$toast.success(SPOOL_ADDED)
    laneCard.$toast.info(SPOOL_ADDED_WITH_NO_WEIGHT, { timeout: 12000 })
  }

  // The lane's spool arrives with the refreshed list, a moment after the printer has answered, so
  // the message waits for it instead of reading a list that is still the one from before.
  function whenSpoolmanKnowsTheSpool(laneCard, thenDo) {
    function stopWaiting() {
      window.clearTimeout(givingUp)
      stopWatching()
      thenDo()
    }
    if (spoolmanKnowsTheSpool(laneCard)) return thenDo()
    var stopWatching = laneCard.$watch('spool', function onSpool(spool) {
      if (spool) stopWaiting()
    })
    var givingUp = window.setTimeout(stopWaiting, SPOOL_LIST_WAIT_MS)
  }

  function whenLaneGetsItsSpool(laneCard, thenDo) {
    function stopWaiting() {
      window.clearTimeout(givingUp)
      stopWatching()
    }
    var stopWatching = laneCard.$watch('spoolId', function onSpoolId(spoolId) {
      if (!spoolId) return
      stopWaiting()
      thenDo()
    })
    var givingUp = window.setTimeout(stopWaiting, ADD_ANSWER_WAIT_MS)
  }

  function addSpoolFromTag(laneCard, action) {
    whenLaneGetsItsSpool(laneCard, function spoolWasAdded() {
      refreshSpoolList(laneCard)
      closeBar(laneCard)
      whenSpoolmanKnowsTheSpool(laneCard, function spoolIsOnTheLane() {
        saySpoolWasAdded(laneCard)
      })
    })
    sendGcode(laneCard, action.command + ' CHANNEL=' + laneChannel(laneCard))
  }

  function runLaneAction(laneCard, action) {
    var channel = laneChannel(laneCard)
    if (action.addsSpool) {
      addSpoolFromTag(laneCard, action)
      return
    }
    if (!action.picksSpool) {
      sendGcode(laneCard, action.command + ' CHANNEL=' + channel)
      return
    }
    openSpoolPicker(laneCard, function withPickedSpool(spoolId) {
      sendGcode(laneCard, action.command + ' CHANNEL=' + channel + ' SPOOL=' + spoolId)
    })
  }

  // Mainsail's own chooser, told not to set the spool it is given: in that mode it reports the pick
  // as `select-spool` and touches nothing. It is drawn closed at all times so that opening it is a
  // change the chooser sees, which is what makes it refresh its list of spools.
  function spoolPicker(createElement, laneCard) {
    var picker = spoolPickerByLaneName[laneCard.name] || { open: false, whenPicked: null }
    return createElement(window.b3dSpoolChooser, {
      key: 'b3d-spool-picker',
      attrs: { 'set-active-spool': false },
      model: {
        value: picker.open,
        callback: function onChooserToggled(isOpen) {
          if (!isOpen) closeSpoolPicker(laneCard)
        }
      },
      on: {
        'select-spool': function onSpoolPicked(pickedSpool) {
          var whenPicked = picker.whenPicked
          closeSpoolPicker(laneCard)
          whenPicked(pickedSpool.id)
        }
      }
    })
  }

  function themeClass(laneCard) {
    return laneCard.$vuetify.theme.dark ? 'theme--dark' : 'theme--light'
  }

  function icon(createElement, iconPath, degreesTurned) {
    return createElement('svg', {
      attrs: { viewBox: '0 0 24 24', width: '18', height: '18' },
      style: { fill: 'currentColor', transform: 'rotate(' + degreesTurned + 'deg)' }
    }, [createElement('path', { attrs: { d: iconPath } })])
  }

  // A lane already on a spool Spoolman knows has nothing to add, so the add button is drawn off and
  // says why, instead of making a second spool for a reel that already has one.
  function buttonIsOff(laneCard, action) {
    return !!action.offWhenSpoolIsKnown && spoolmanKnowsTheSpool(laneCard)
  }

  function laneButton(createElement, laneCard, action) {
    var isOff = buttonIsOff(laneCard, action)
    return createElement('button', {
      class: 'v-btn v-btn--icon v-btn--round v-size--small mx-1 ' + themeClass(laneCard) + (isOff ? ' v-btn--disabled' : ''),
      attrs: {
        type: 'button',
        disabled: isOff,
        title: isOff ? action.offWhenSpoolIsKnown : action.label,
        'aria-label': action.label
      },
      on: {
        click: function onLaneButtonClick() {
          if (isOff) return
          runLaneAction(laneCard, action)
        }
      }
    }, [createElement('span', { class: 'v-btn__content' }, [icon(createElement, action.iconPath, 0)])])
  }

  function buttonRow(createElement, laneCard, actions) {
    return createElement('div', {
      key: 'b3d-lane-buttons',
      class: 'd-flex justify-center align-center flex-wrap px-2'
    }, actions.map(function drawButton(action) {
      return laneButton(createElement, laneCard, action)
    }))
  }

  function collapseStrip(createElement, laneCard, isOpen) {
    return createElement('div', {
      key: 'b3d-lane-strip',
      class: 'd-flex justify-center align-center ' + themeClass(laneCard),
      style: { cursor: 'pointer', height: '16px', opacity: '0.6' },
      attrs: { title: isOpen ? 'Hide the spool buttons' : 'Show the spool buttons' },
      on: {
        click: function onStripClick() {
          toggleBar(laneCard)
        }
      }
    }, [icon(createElement, ICON_PATHS.collapse, isOpen ? 0 : 180)])
  }

  function laneToolbar(createElement, laneCard) {
    var actions = actionsThisPrinterOffers(laneCard)
    // Nothing to draw is an empty placeholder node, never null: the card hands its children to the
    // bundle's render helper without full normalization, so a null sitting in that list is treated
    // as a node and throws, taking the whole page down. createElement with no tag is Vue's own
    // placeholder, which is what upstream puts there when it has nothing to show.
    if (actions.length === 0 || laneChannel(laneCard) === null) return createElement()
    var isOpen = barIsOpen(laneCard)
    var rows = isOpen ? [buttonRow(createElement, laneCard, actions)] : []
    return createElement('div', { class: 'b3d-afc-lane-bar' },
      rows.concat([collapseStrip(createElement, laneCard, isOpen), spoolPicker(createElement, laneCard)]))
  }

  window.b3dAfcLaneToolbar = { laneToolbar: laneToolbar }
})()

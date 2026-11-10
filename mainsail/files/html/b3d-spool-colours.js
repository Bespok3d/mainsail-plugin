// Every colour of a spool, in Mainsail's spool views. A dual, tri colour or gradient spool carries
// several colours: Spoolman files them as a list and leaves the single colour empty, and the printer
// reads them off an RFID tag. Upstream draws the AFC lane reel and the tool dots in one colour only,
// so a multi colour spool came out black, and its spool icons know only Spoolman's list. Here the
// reel and the dots are painted in stripes, one per colour, and the icons get the richest list.
//
// The richest record wins. A spool's colours come from Spoolman and from the lane it sits on, which
// holds what the tag said; whichever names more colours is the one drawn, so a multi colour spool is
// never flattened to one colour by the other source. A tie keeps Spoolman's colours.
(function attachSpoolColours() {
  var SVG_NAMESPACE = 'http://www.w3.org/2000/svg'
  // The two names AFC gives a lane, looked up in the order Mainsail itself looks them up.
  var LANE_OBJECT_PREFIXES = ['AFC_stepper ', 'AFC_lane ']
  var PAINT_NAME_PREFIX = 'b3d-spool-colours-'
  // Spoolman keeps a colour as six hex digits, or eight with transparency; a tag gives six.
  var HEX_COLOUR = /^#?([0-9a-f]{6}|[0-9a-f]{8})$/i

  // A stripe pattern is drawn into the page once and reused by every reel that shows the same
  // colours, so it is remembered by its name.
  var paintedNames = {}
  var paintStore = null

  function isHexColour(colour) {
    return HEX_COLOUR.test(String(colour))
  }

  function hexDigitsOf(colour) {
    return String(colour).replace('#', '').toLowerCase()
  }

  // Every view takes a spool's colours as '#' and lower case hex, so the icon, the dot and the reel
  // of one spool always show the same colours, and a colour is safe in a style. A colour that is not hex is left
  // out, never drawn as some other colour.
  function hexColours(colours) {
    return colours.filter(isHexColour).map(function withHash(colour) {
      return '#' + hexDigitsOf(colour)
    })
  }

  // Spoolman files a multi colour filament as a comma separated list and a one colour filament as
  // its single colour, so the list comes first and the single colour stands in when there is none.
  function spoolmanColourList(filament) {
    if (!filament) return []
    if (filament.multi_color_hexes) {
      return String(filament.multi_color_hexes).split(',').map(function trimmed(colour) {
        return colour.trim()
      })
    }
    return filament.color_hex ? [filament.color_hex] : []
  }

  function spoolmanColours(spool) {
    return hexColours(spoolmanColourList(spool && spool.filament))
  }

  function laneColours(lane) {
    return hexColours((lane && lane.colors) || [])
  }

  function richestColours(spoolColours, coloursOnLane) {
    return coloursOnLane.length > spoolColours.length ? coloursOnLane : spoolColours
  }

  function isLaneObjectName(objectName) {
    return LANE_OBJECT_PREFIXES.some(function startsTheName(prefix) {
      return objectName.indexOf(prefix) === 0
    })
  }

  // AFC may report the spool id as text, so it is compared as a number, as Mainsail does.
  function holdsSpool(lane, spoolId) {
    return Boolean(lane) && lane.spool_id != null && Number(lane.spool_id) === spoolId
  }

  function laneHoldingSpool(printerObjects, spoolId) {
    var objects = printerObjects || {}
    var laneObjectName = Object.keys(objects).filter(isLaneObjectName).find(function holdsTheSpool(objectName) {
      return holdsSpool(objects[objectName], spoolId)
    })
    return laneObjectName ? objects[laneObjectName] : null
  }

  function coloursOfSpool(printerObjects, spool) {
    if (!spool) return []
    var lane = laneHoldingSpool(printerObjects, spool.id)
    return richestColours(spoolmanColours(spool), laneColours(lane))
  }

  function paintName(colours) {
    return PAINT_NAME_PREFIX + colours.map(hexDigitsOf).join('-')
  }

  // Two stops per colour at the same edges give hard stripes instead of a blend between colours.
  function stripeStops(colours) {
    var stripeWidth = 100 / colours.length
    return colours.reduce(function addStripeEdges(stops, colour, position) {
      return stops.concat([
        { offset: position * stripeWidth + '%', colour: colour },
        { offset: (position + 1) * stripeWidth + '%', colour: colour }
      ])
    }, [])
  }

  // Not display:none: a gradient inside a hidden svg is not painted by every browser.
  function createPaintStore() {
    var store = document.createElementNS(SVG_NAMESPACE, 'svg')
    store.setAttribute('width', '0')
    store.setAttribute('height', '0')
    store.setAttribute('aria-hidden', 'true')
    store.setAttribute('style', 'position:absolute')
    var gradients = document.createElementNS(SVG_NAMESPACE, 'defs')
    store.appendChild(gradients)
    document.body.appendChild(store)
    return { gradients: gradients }
  }

  function stripeGradient(name, colours) {
    var gradient = document.createElementNS(SVG_NAMESPACE, 'linearGradient')
    gradient.setAttribute('id', name)
    stripeStops(colours).forEach(function addStop(stripeStop) {
      var stop = document.createElementNS(SVG_NAMESPACE, 'stop')
      stop.setAttribute('offset', stripeStop.offset)
      stop.setAttribute('stop-color', stripeStop.colour)
      gradient.appendChild(stop)
    })
    return gradient
  }

  function paintStripes(colours) {
    var name = paintName(colours)
    if (paintedNames[name]) return name
    paintStore = paintStore || createPaintStore()
    paintStore.gradients.appendChild(stripeGradient(name, colours))
    paintedNames[name] = true
    return name
  }

  // A tool dot is an html box, which an svg gradient cannot fill, so it takes the same stripes as a
  // css gradient.
  function cssStripes(colours) {
    var cssStops = stripeStops(colours).map(function cssStop(stripeStop) {
      return stripeStop.colour + ' ' + stripeStop.offset
    })
    return 'linear-gradient(to right,' + cssStops.join(',') + ')'
  }

  // Mainsail's spool icon draws a list of colours itself, in the direction Spoolman gives, so it
  // only needs the richest list. A spool of one colour keeps upstream's own value.
  function multiColourHexes(upstreamHexes, printerObjects, spool) {
    var colours = coloursOfSpool(printerObjects, spool)
    if (colours.length < 2) return upstreamHexes
    return colours.join(',')
  }

  // The stripes lie over upstream's single colour, which stays as the dot's ground.
  function toolDotStyle(upstreamStyle, printerObjects, spool) {
    var colours = coloursOfSpool(printerObjects, spool)
    if (colours.length < 2) return upstreamStyle
    return Object.assign({}, upstreamStyle, { 'background-image': cssStripes(colours) })
  }

  // The reel fills its filament with the colour it is given, so the stripes go in as the fill.
  function laneReelFill(upstreamColour, spool, lane) {
    var colours = richestColours(spoolmanColours(spool), laneColours(lane))
    if (colours.length < 2) return upstreamColour
    return 'url(#' + paintStripes(colours) + ')'
  }

  window.b3dSpoolColours = {
    coloursOfSpool: coloursOfSpool,
    multiColourHexes: multiColourHexes,
    toolDotStyle: toolDotStyle,
    laneReelFill: laneReelFill
  }
})()

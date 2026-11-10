// SPDX-FileCopyrightText: Copyright (C) 2026 unlucio and the Bespok3d contributors
// SPDX-License-Identifier: GPL-3.0-only
// Every colour of a multi colour spool, in the Mainsail the plugin ships. This runs the shipped spool
// colours rule against a stand-in page and proves what a user sees: a multi colour spool is drawn in
// stripes on the AFC lane reel and the tool dots, the spool icons get every colour, the source naming
// more colours wins whichever it is, a one colour spool keeps upstream's look, and the bundle actually
// calls the rule from every spool view it was written for.
import { readdirSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import vm from 'node:vm'

const pluginDir = process.argv[2]
if (!pluginDir) {
  console.error('usage: test-spool-colours.mjs <plugin-dir>')
  process.exit(2)
}

// The app chunk is named after a hash of its content, which changes with every Mainsail release.
function appChunkPath(assetsDir) {
  const [appChunkName] = readdirSync(assetsDir).filter((assetName) => /^index-.*\.js$/.test(assetName))
  return join(assetsDir, appChunkName)
}

const authoredRule = readFileSync(join(pluginDir, 'patches/spool-colours.js'), 'utf8')
const shippedRule = readFileSync(join(pluginDir, 'files/html/b3d-spool-colours.js'), 'utf8')
const shippedPage = readFileSync(join(pluginDir, 'files/html/index.html'), 'utf8')
const shippedAppChunk = readFileSync(appChunkPath(join(pluginDir, 'files/html/assets')), 'utf8')

const TAG_SPOOL_ID = 89
const UPSTREAM_COLOUR = '#000000'
const UPSTREAM_HEXES = 'upstream hexes'
const UPSTREAM_DOT_STYLE = { 'border-color': '', 'background-color': '#000000' }

// What upstream wrote in each spool view, and what the view asks the rule for instead.
const SPOOL_VIEWS = [
  {
    view: 'the active spool icon',
    upstream: 'get multi_color_hexes(){var e;return(e=this.active_spool)==null||(e=e.filament)==null?void 0:e.multi_color_hexes}',
    asksTheRule: 'return window.b3dSpoolColours?window.b3dSpoolColours.multiColourHexes(b3dUpstreamHexes,this.$store.state.printer,this.active_spool):b3dUpstreamHexes}'
  },
  {
    view: 'a change spool dialog row icon',
    upstream: 'get multi_color_hexes(){var e;return(e=this.spool.filament)==null?void 0:e.multi_color_hexes}',
    asksTheRule: 'return window.b3dSpoolColours?window.b3dSpoolColours.multiColourHexes(b3dUpstreamHexes,this.$store.state.printer,this.spool):b3dUpstreamHexes}'
  },
  {
    view: 'an extruder tool button dot',
    upstream: 'get dotStyle(){return{"border-color":this.active?this.primaryTextColor:``,"background-color":`#`+this.color}}',
    asksTheRule: 'get dotStyle(){var b3dUpstreamStyle={"border-color":this.active?this.primaryTextColor:``,"background-color":`#`+this.color};return window.b3dSpoolColours?window.b3dSpoolColours.toolDotStyle(b3dUpstreamStyle,this.$store.state.printer,this.spool):b3dUpstreamStyle}'
  },
  {
    view: 'a Spoolman tools list dot',
    upstream: 'get dotStyle(){return{"background-color":`#`+this.color}}',
    asksTheRule: 'get dotStyle(){var b3dUpstreamStyle={"background-color":`#`+this.color};return window.b3dSpoolColours?window.b3dSpoolColours.toolDotStyle(b3dUpstreamStyle,this.$store.state.printer,this.spool):b3dUpstreamStyle}'
  },
  {
    view: 'the AFC lane reel',
    upstream: 'get spoolColor(){return this.hasTd&&this.showTd1Color?`#${this.tdColor}`:this.lane.color||`#000000`}',
    asksTheRule: 'window.b3dSpoolColours?window.b3dSpoolColours.laneReelFill(b3dUpstreamColour,this.spool,this.lane):b3dUpstreamColour}'
  }
]

const failures = []

function fail(reason) {
  failures.push(reason)
}

function expect(holds, reason) {
  if (!holds) fail(reason)
}

function standInElement(tagName) {
  return {
    tagName,
    attributes: {},
    children: [],
    setAttribute(attributeName, attributeValue) {
      this.attributes[attributeName] = attributeValue
    },
    appendChild(child) {
      this.children.push(child)
      return child
    }
  }
}

function standInPage() {
  return {
    head: standInElement('head'),
    body: standInElement('body'),
    createElement: standInElement,
    createElementNS(namespace, tagName) {
      return standInElement(tagName)
    }
  }
}

function loadShippedRule() {
  const page = standInPage()
  const browserWindow = {}
  vm.runInNewContext(shippedRule, { window: browserWindow, document: page })
  return { spoolColours: browserWindow.b3dSpoolColours, page }
}

// Mainsail keeps Spoolman's own record: a multi colour filament as a comma separated list with no
// single colour, a one colour filament as its single colour, both without a hash.
function multiColourSpool(multiColourHexes) {
  return { id: TAG_SPOOL_ID, filament: { color_hex: null, multi_color_hexes: multiColourHexes } }
}

function oneColourSpool(colourHex) {
  return { id: TAG_SPOOL_ID, filament: { color_hex: colourHex, multi_color_hexes: null } }
}

function laneWithTag(colours) {
  return { spool_id: TAG_SPOOL_ID, colors: colours }
}

function printerWithLane(lane, laneObjectName = 'AFC_lane E0') {
  return { extruder: { temperature: 0 }, [laneObjectName]: lane }
}

function paintedGradients(page) {
  const paintStore = page.body.children[0]
  return paintStore ? paintStore.children[0].children : []
}

function stripeColoursOf(gradient) {
  return gradient.children.map((stripeStop) => stripeStop.attributes['stop-color'])
}

function dotStripes(dotStyle) {
  return dotStyle['background-image']
}

function checkTagSingleSpoolmanMulti() {
  const { spoolColours, page } = loadShippedRule()
  const spool = multiColourSpool('FF0000, 00FF00,0000FF')
  const lane = laneWithTag(['#FFFFFF'])
  const printer = printerWithLane(lane)
  expect(spoolColours.multiColourHexes(UPSTREAM_HEXES, printer, spool) === '#ff0000,#00ff00,#0000ff',
    'a single colour tag flattens a three colour Spoolman spool on its icon')
  expect(spoolColours.laneReelFill(UPSTREAM_COLOUR, spool, lane) === 'url(#b3d-spool-colours-ff0000-00ff00-0000ff)',
    'a single colour tag flattens a three colour Spoolman spool on its lane reel')
  const [gradient] = paintedGradients(page)
  expect(gradient && JSON.stringify(stripeColoursOf(gradient)) ===
    JSON.stringify(['#ff0000', '#ff0000', '#00ff00', '#00ff00', '#0000ff', '#0000ff']),
    'the reel stripes are not one hard edged band per Spoolman colour')
  spoolColours.laneReelFill(UPSTREAM_COLOUR, spool, lane)
  expect(paintedGradients(page).length === 1, 'the same colours are painted into the page more than once')
}

function checkTagMultiSpoolmanSingle() {
  const { spoolColours } = loadShippedRule()
  const spool = oneColourSpool('FF0000')
  const lane = laneWithTag(['#112233', '#445566'])
  const printer = printerWithLane(lane)
  expect(spoolColours.multiColourHexes(UPSTREAM_HEXES, printer, spool) === '#112233,#445566',
    'a single colour Spoolman spool flattens a two colour tag on its icon')
  expect(dotStripes(spoolColours.toolDotStyle(UPSTREAM_DOT_STYLE, printer, spool)) ===
    'linear-gradient(to right,#112233 0%,#112233 50%,#445566 50%,#445566 100%)',
    'a single colour Spoolman spool flattens a two colour tag on its tool dot')
  expect(spoolColours.laneReelFill(UPSTREAM_COLOUR, spool, lane) === 'url(#b3d-spool-colours-112233-445566)',
    'a single colour Spoolman spool flattens a two colour tag on its lane reel')
}

function checkTieKeepsSpoolman() {
  const { spoolColours } = loadShippedRule()
  const spool = multiColourSpool('FF0000,00FF00')
  const lane = laneWithTag(['#112233', '#445566'])
  expect(spoolColours.multiColourHexes(UPSTREAM_HEXES, printerWithLane(lane), spool) === '#ff0000,#00ff00',
    'a tag naming as many colours as Spoolman replaces Spoolman colours')
}

function checkOneColourKeepsUpstream() {
  const { spoolColours, page } = loadShippedRule()
  const spool = oneColourSpool('FF0000')
  const lane = laneWithTag(['#FF0000'])
  const printer = printerWithLane(lane)
  expect(spoolColours.multiColourHexes(UPSTREAM_HEXES, printer, spool) === UPSTREAM_HEXES,
    'a one colour spool icon does not keep upstream colours')
  expect(spoolColours.toolDotStyle(UPSTREAM_DOT_STYLE, printer, spool) === UPSTREAM_DOT_STYLE,
    'a one colour tool dot does not keep upstream look')
  expect(spoolColours.laneReelFill(UPSTREAM_COLOUR, spool, lane) === UPSTREAM_COLOUR,
    'a one colour lane reel does not keep upstream colour')
  expect(page.body.children.length === 0, 'a page with one colour spools only is painted on')
}

function checkNoSpoolKeepsUpstream() {
  const { spoolColours } = loadShippedRule()
  const printer = printerWithLane(laneWithTag(['#112233', '#445566']))
  expect(spoolColours.toolDotStyle(UPSTREAM_DOT_STYLE, printer, null) === UPSTREAM_DOT_STYLE,
    'a tool with no spool is given stripes')
  expect(spoolColours.multiColourHexes(UPSTREAM_HEXES, printer, null) === UPSTREAM_HEXES,
    'no active spool is given colours')
  expect(spoolColours.laneReelFill(UPSTREAM_COLOUR, null, laneWithTag(['#112233', '#445566'])) ===
    'url(#b3d-spool-colours-112233-445566)',
    'a lane with no Spoolman spool loses the colours its tag names')
}

function checkDotStripesOverUpstream() {
  const { spoolColours } = loadShippedRule()
  const spool = multiColourSpool('FF0000,00FF00,0000FF')
  const dotStyle = spoolColours.toolDotStyle(UPSTREAM_DOT_STYLE, printerWithLane(laneWithTag([])), spool)
  const firstEdge = `${100 / 3}%`
  const secondEdge = `${200 / 3}%`
  expect(dotStripes(dotStyle) === `linear-gradient(to right,#ff0000 0%,#ff0000 ${firstEdge},#00ff00 ${firstEdge},` +
    `#00ff00 ${secondEdge},#0000ff ${secondEdge},#0000ff 100%)`,
    'a three colour tool dot is not one hard edged band per colour')
  expect(dotStyle['border-color'] === '' && dotStyle['background-color'] === '#000000',
    'the striped tool dot loses its upstream border or ground colour')
  expect(UPSTREAM_DOT_STYLE['background-image'] === undefined, 'the striped tool dot rewrites upstream style')
}

function checkColoursStayColours() {
  const { spoolColours } = loadShippedRule()
  const printer = printerWithLane(laneWithTag([]))
  const injectedColour = multiColourSpool('ff0000);display:none;(,00FF00')
  expect(spoolColours.toolDotStyle(UPSTREAM_DOT_STYLE, printer, injectedColour) === UPSTREAM_DOT_STYLE,
    'a spool colour that is not hex writes its own text into a tool dot style')
  const oneBadColourOfThree = multiColourSpool('FF0000,rgb(0 0 255),00FF00')
  expect(spoolColours.multiColourHexes(UPSTREAM_HEXES, printer, oneBadColourOfThree) === '#ff0000,#00ff00',
    'one colour that is not hex takes the stripes off the colours that are')
}

function checkViewsAgree() {
  const { spoolColours } = loadShippedRule()
  const spool = oneColourSpool('FF0000')
  const tagWithoutHash = laneWithTag(['FF0000', '00ff0080'])
  const printer = printerWithLane(tagWithoutHash)
  expect(spoolColours.multiColourHexes(UPSTREAM_HEXES, printer, spool) === '#ff0000,#00ff0080',
    'a tag colour written without a hash, or with transparency, is not given to the spool icon')
  expect(spoolColours.laneReelFill(UPSTREAM_COLOUR, spool, tagWithoutHash) === 'url(#b3d-spool-colours-ff0000-00ff0080)',
    'the lane reel is filled with colours the spool icon does not show')
}

function checkEitherLaneNameAndTextId() {
  const { spoolColours } = loadShippedRule()
  const spool = oneColourSpool('FF0000')
  const stepperLane = printerWithLane(laneWithTag(['#112233', '#445566']), 'AFC_stepper E1')
  expect(spoolColours.multiColourHexes(UPSTREAM_HEXES, stepperLane, spool) === '#112233,#445566',
    'a lane AFC names AFC_stepper says nothing about its spool')
  const textIdLane = printerWithLane({ spool_id: String(TAG_SPOOL_ID), colors: ['#112233', '#445566'] })
  expect(spoolColours.multiColourHexes(UPSTREAM_HEXES, textIdLane, spool) === '#112233,#445566',
    'a lane reporting its spool id as text says nothing about its spool')
  const notALane = { 'extruder E0': laneWithTag(['#112233', '#445566']) }
  expect(spoolColours.multiColourHexes(UPSTREAM_HEXES, notALane, spool) === UPSTREAM_HEXES,
    'a printer object that is not a lane is read as one')
}

function checkOtherLaneSaysNothing() {
  const { spoolColours } = loadShippedRule()
  const spool = oneColourSpool('FF0000')
  const laneWithAnotherSpool = { spool_id: TAG_SPOOL_ID + 1, colors: ['#112233', '#445566'] }
  const emptyLane = { spool_id: null, colors: ['#112233', '#445566'] }
  expect(spoolColours.multiColourHexes(UPSTREAM_HEXES, printerWithLane(laneWithAnotherSpool), spool) === UPSTREAM_HEXES,
    'the tag of a lane holding another spool paints this spool')
  expect(spoolColours.multiColourHexes(UPSTREAM_HEXES, printerWithLane(emptyLane), spool) === UPSTREAM_HEXES,
    'the tag of a lane holding no spool paints this spool')
}

function occurrences(text, fragment) {
  return text.split(fragment).length - 1
}

function checkTheBundleCallsTheRule() {
  expect(authoredRule === shippedRule, 'the bundle carries an older spool colours rule than this repo wrote')
  expect(shippedPage.includes('<script src="/b3d-afc-lane-toolbar.js"></script><script src="/b3d-spool-colours.js"></script>'),
    'the page never loads the spool colours rule')
  SPOOL_VIEWS.forEach(function checkSpoolView(spoolView) {
    expect(!shippedAppChunk.includes(spoolView.upstream), `${spoolView.view} still draws upstream single colour`)
    expect(occurrences(shippedAppChunk, spoolView.asksTheRule) === 1, `${spoolView.view} does not ask for its colours, or breaks when the rule did not load`)
  })
  expect(shippedAppChunk.includes('`#${this.tdColor}`:window.b3dSpoolColours?'),
    'the colour a TD-1 measured no longer wins on the AFC lane reel')
}

checkTagSingleSpoolmanMulti()
checkTagMultiSpoolmanSingle()
checkTieKeepsSpoolman()
checkOneColourKeepsUpstream()
checkNoSpoolKeepsUpstream()
checkDotStripesOverUpstream()
checkColoursStayColours()
checkViewsAgree()
checkEitherLaneNameAndTextId()
checkOtherLaneSaysNothing()
checkTheBundleCallsTheRule()

for (const reason of failures) console.error(`  FAIL: ${reason}`)
process.exit(failures.length === 0 ? 0 : 1)

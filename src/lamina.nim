import core

import fau/g2/imgui
import fau/assets
import fau/util/[filedialogs, bitset]
import std/[os, math, sets, sequtils, algorithm, strformat, strutils]
import pkg/[jsony]
from pkg/pixie import Image, newImage, readImage, writeFile, flipVertical, `[]`

type 
  Snapshot = object
    size: Vec2i
    selected: int
    layers: seq[Layer]
  Layer = object
    color: Color
    data: Bitset
    blend = blendNormal
    visible = true
  State = object
    zoom {.jsonSkip.}: float32 = 1f
    panPos {.jsonSkip.}: Vec2
    operations {.jsonSkip.}: seq[Snapshot]
    operationIndex {.jsonSkip.}: int
    changed {.jsonSkip.}: bool
    saved {.jsonskip.}: bool

    size: Vec2i
    layers: seq[Layer]
    selectedLayer: int
    scaling: int = 8
    
  Config = object
    lastFolder: string
    lastProjectFile: string
    grid: bool = true
    bg: bool = true

var
  state = State()

  config = Config()
  configFile = ""
  resizeVal: Vec2i

  alphaTex: Texture
  canvasBuffer: Framebuffer
  lastError: string

const
  undoSize = 300
  panSpeed = 1f
  zoomSpeed = 5f

proc canvasChanged() =
  var snapshot = Snapshot(size: state.size, selected: state.selectedLayer, layers: state.layers)

  #truncate operation stack
  if state.operationIndex > 0:
    state.operations.setLen(state.operations.len - state.operationIndex)
    state.operationIndex = 0

  state.operations.add snapshot
  state.saved = false

proc resetZoom = 
  state.zoom = (state.size.y + 2) / fau.size.y

proc restoreState(snap: Snapshot) =
  state.layers = snap.layers
  state.size = snap.size
  state.selectedLayer = snap.selected

proc canUndo(): bool = state.operations.len > state.operationIndex + 1

proc canRedo(): bool = state.operationIndex > 0

proc undo() =
  if canUndo():
    restoreState(state.operations[state.operations.len - 1 - state.operationIndex - 1])
    state.operationIndex.inc

proc redo() =
  if canRedo():
    restoreState(state.operations[state.operations.len - 1 - state.operationIndex + 1])
    state.operationIndex.dec

proc showError(err: string) =
  lastError = err

  echo "[Error] ", err

  postCallback:
    igOpenPopup("Error")

proc toCanvas(pos: Vec2): Vec2i =
  let p = (pos - (-state.size.vec2/2f))
  if p.x < 0 or p.y < 0: return vec2i(-1, -1)

  return vec2i(p.x.int, p.y.int)

proc getTopLayer(pos: Vec2i): int =
  if not pos.inBounds(state.size): return -1
  for i in countdown(state.layers.len - 1, 0, 1):
    if state.layers[i].data[pos.x + pos.y*state.size.x]: return i
  
  return -1

proc shiftLayer(layer: var Layer, dir: Vec2i) =
  let size = state.size
  let prev = layer.data
  layer.data = newBitset(size.x * size.y)
  for y in 0..<size.y:
    for x in 0..<size.x:
      let newPos = vec2i(x, y) + dir
      if newPos.inBounds(size):
        layer.data[newPos.x + newPos.y * size.x] = prev[x + y * size.x]

  canvasChanged()

proc newLayer(size: Vec2i, color: Color): Layer = 
  Layer(data: newBitset(size.x * size.y), color: color)

proc importImage(path: string, extrude = true) =

  proc fixColor(col: Color): Color {.inline.} =
    Color(rv: col.rv, gv: col.gv, bv: col.bv, av: if col.av > 128'u8: 255'u8 else: 0'u8)

  try:
    let img = readImage(path)

    var 
      colors = initHashSet[Color]()
      used = initHashSet[Color]()

    for x in 0..<img.width:
      for y in 0..<img.height:
        colors.incl fixColor(cast[Color](img[x, y]))
    
    if colors.len > 32:
      showError("Failed to import image: too many colors")
      return

    if img.width * img.height > 128*128:
      showError("Failed to import image: image too large (max size is 128x128)")
      return

    #sort colors so they have a consistent order in the output
    var ordered = colors.toSeq()
    ordered.sort do(a, b: Color) -> int:
      cmp(a.toHsv.h, b.toHsv.h)
    
    state.size = vec2i(img.width, img.height)
    state.layers.setLen(0)
    state.selectedLayer = 0

    for col in ordered:
      used.incl(col)
      if col.av > 0:
        var layer = newLayer(state.size, col)

        for x in 0..<img.width:
          for y in 0..<img.height:
            let sampled = fixColor(cast[Color](img[x, y]))

            if col == sampled:
              layer.data[x + (img.height - 1 - y) * img.width] = true

              if extrude:
                for d in d4():
                  let other = vec2i(x, y) + d
                  if other.inBounds(state.size):
                    let oc = fixColor(cast[Color](img[other.x, other.y]))
                    if oc.av > 0 and not used.contains(oc):
                      layer.data[other.x + (img.height - 1 - other.y) * img.width] = true

        state.layers.add layer
  except:
    showError(getCurrentExceptionMsg())
    return

  if state.layers.len == 0:
    state.layers.add newLayer(state.size, colorWhite)

  canvasChanged()
  resetZoom()

include project, draw

proc init() =
  configFile = getSaveDir("lamina") / "config.json"

  imguiInitFau(appName = "lamina", theme = themeComfy, font = "Ubuntu-Light.ttf")
  loadConfig()

  alphaTex = loadTexture("alpha.png", wrap = twRepeat)
  canvasBuffer = newFramebuffer()

  if config.lastProjectFile != "":
    loadProject(config.lastProjectFile)
  
  #create new canvas
  if state.size.x == 0:
    newProject()

  resetZoom()

  addFauListener(feDestroy):
    saveConfig()

proc addNewLayer =
  state.layers.insert(newLayer(state.size, color = parseColor(getClipboardString(), colorWhite)), state.selectedLayer + 1)
  state.selectedLayer.inc
  canvasChanged()

proc renderProject =
  renderToFile(if config.lastProjectFile.len == 0: "out.png" else: config.lastProjectFile.parentDir / (config.lastProjectFile.splitFile.name & ".png"), scale = state.scaling)

proc showExportFile =
  let file = saveFileDialog(patterns = @["*.png"], filterDescription = "PNG files", defaultPathAndFile = if config.lastProjectFile != "": config.lastProjectFile.replace(".json", ".png") else: config.lastFolder / "out.png")
  if file != "":
    renderToFile(file)

proc doUi =
  var windowHeight = 0f

  if not fau.captureKeyboard:
    if keyG.tapped: config.grid = not config.grid
    if keyB.tapped: config.bg = not config.bg

    for i, num in allNumberKeys.pairs:
      if num.tapped and i < state.layers.len:
        state.selectedLayer = i
    
    let dir = axisTap(keyDown, keyUp)
    if dir != 0 and not shiftDown() and state.selectedLayer + dir < state.layers.len and state.selectedLayer + dir >= 0:
      
      if ctrlDown(): 
        swap(state.layers[state.selectedLayer], state.layers[state.selectedLayer + dir])
        canvasChanged()
      state.selectedLayer += dir

    if keySpace.tapped: addNewLayer()
    if keyDelete.tapped and state.layers.len > 1:
      state.layers.delete(state.selectedLayer)
      state.selectedLayer = clamp(state.selectedLayer, 0, state.layers.len - 1)

      canvasChanged()
    
    let moveAxis = axisTap2(keyLeft, keyRight, keyDown, keyUp).vec2i
    if shiftDown() and moveAxis != vec2i():
      shiftLayer(state.layers[state.selectedLayer], moveAxis)

    if ctrlDown():
      if keyZ.tapped:
        if shiftDown():
          redo()
        else:
          undo()
      if keyE.tapped:
        if shiftDown():
          showExportFile()
        else:
          renderProject()

      if keyN.tapped: newProject()
      if keyO.tapped: showLoadFile()

      if keyS.tapped:
        if shiftDown() or config.lastProjectFile == "": 
          showSaveFile()
        else: 
          saveProject(config.lastProjectFile)
          renderProject()
          state.saved = true

  if igBeginMainMenuBar():
    windowHeight = igGetWindowHeight()

    if igBeginMenu("File"):
      if igMenuItem("New", shortcut = "Ctrl+N"): newProject()
      if igMenuItem("Open", shortcut = "Ctrl+O"): showLoadFile()
      igBeginDisabled(config.lastProjectFile == "")
      if igMenuItem("Save", shortcut = "Ctrl+S"): 
        saveProject(config.lastProjectFile)
        renderProject()
        state.saved = true
      igEndDisabled()
      if igMenuItem("Save As", shortcut = "Ctrl+Shift+S"): showSaveFile()
      igSeparator()
      if igMenuItem("Export", shortcut = "Ctrl+E"): renderProject()
      if igMenuItem("Export As", shortcut = "Ctrl+Shift+E"): showExportFile()
      igSeparator()

      if igMenuItem("Import PNG"): showImportFile(true)
      if igMenuItem("Import PNG (Raw)"): showImportFile(false)

      igEndMenu()

    if igBeginMenu("View"):

      if igMenuItem("Grid", selected = config.grid, shortcut = "G"): config.grid = not config.grid
      if igMenuItem("Background", selected = config.bg, shortcut = "B"): config.bg = not config.bg
        
      igEndMenu()

    if igBeginMenu("Edit"):
      igBeginDisabled(not canUndo())
      if igMenuItem("Undo", shortcut = "Ctrl+Z"): undo()
      igEndDisabled()

      igBeginDisabled(not canRedo())
      if igMenuItem("Redo", shortcut = "Ctrl+Shift+Z"): redo()
      igEndDisabled()

      if igMenuItem("Resize"):
        resizeVal = state.size
        postCallback:
          igOpenPopup("Resize")
        
      igEndMenu()

    igEndMainMenuBar()
  
  let w = 350f

  var r = align(fau.size, vec2(w, fau.size.y - windowHeight), daTopRight)

  igSetNextWindowPos(r.pos)
  igSetNextWindowSize(r.size)

  igPushStyleVar(ImgUiStyleVar.WindowRounding, 0f)
  igBegin("Layers", flags = ImguiWindowFlags.NoResize or ImguiWindowFlags.NoDecoration)
  igPopStyleVar()
  
  var arr = state.layers[state.selectedLayer].color.toArray

  igColorPicker4("Color", arr, flags = ImGuiColorEditFlags.NoAlpha)

  state.changed = state.changed or state.layers[state.selectedLayer].color != arr.toColor

  state.layers[state.selectedLayer].color = arr.toColor

  igInputInt("Scale", addr state.scaling)
  state.scaling = clamp(state.scaling, 1, 400)

  let blends = [
    "Normal",
    "Additive",
    "Clip",
    "Erase"
  ]

  var blendIndex = blends.find(($state.layers[state.selectedLayer].blend).capitalizeAscii)

  if igCombo("Blending", addr blendIndex, blends):
    state.changed = true
    canvasChanged()
    state.layers[state.selectedLayer].blend = blendFromString(blends[blendIndex].toLowerAscii)

  for i in countdown(state.layers.len - 1, 0, 1):
    let sel = i == state.selectedLayer
    igPushStyleColor(ImGuiCol.ButtonHovered, state.layers[i].color * 1.3f)
    igPushStyleColor(ImGuiCol.ButtonActive, state.layers[i].color)
    igPushStyleColor(ImGuiCol.Button, state.layers[i].color)

    if sel: 
      igPushStyleColor(ImGuiCol.Border, colorCoral)
      igPushStyleVar(ImgUiStyleVar.FrameBorderSize, 5f)

    if igButtonEx(("##Layer " & $i).cstring, vec2(46f), flags = ImGuiButtonFlags.PressedOnClick):
      state.selectedLayer = i
    
    igPopStyleColor()
    igPopStyleColor()
    igPopStyleColor()
    if sel: 
      igPopStyleColor()
      igPopStyleVar()
    
    igSameLine()
    igPushStyleVar(ImguiStyleVar.FramePadding, vec2(13f))
    igCheckbox(("##Show " & $i).cstring, addr state.layers[i].visible)
    igPopStyleVar()
  
  if igButton("+", size = vec2(46)):
    addNewLayer()

  igEnd()

  igSetNextWindowPos(fau.size/2f, ImGuiCond.Always, vec2(0.5f, 0.5f))

  if igBeginPopupModal("Error", nil, flags = ImGuiWindowFlags.AlwaysAutoResize or ImGuiWindowFlags.NoMove):
    igPushTextWrapPos(500f)
    igTextWrapped(lastError.cstring)
    igPopTextWrapPos()

    if igButton("Ok", vec2(160f, 50f)):
      igCloseCurrentPopup()
    
    igEndPopup()

  igSetNextWindowPos(fau.size/2f, ImGuiCond.Always, vec2(0.5f, 0.5f))

  if igBeginPopupModal("Resize", nil, flags = ImGuiWindowFlags.AlwaysAutoResize or ImGuiWindowFlags.NoMove):

    igSetNextItemWidth(240f)
    igInputInt2("Size", resizeVal)
    resizeVal.x = resizeVal.x.max(1)
    resizeVal.y = resizeVal.y.max(1)

    if igButton("Ok", vec2(120f, 0f)):
      igCloseCurrentPopup()

      let prev = state.size

      if prev != resizeVal:

        state.size = resizeVal

        let off = (resizeVal - prev) div 2
        for layer in state.layers.mitems:
          let oldData = layer.data
          layer.data = newBitset(state.size.x * state.size.y)

          for y in 0..<prev.y:
            for x in 0..<prev.x:
              let 
                oldIdx = y*prev.x + x
                newpos = off + vec2i(x, y)
                newIdx = newpos.y*state.size.x + newpos.x
              
              if newpos.inBounds(state.size):
                layer.data[newIdx] = oldData[oldIdx]
        
        canvasChanged()

    igSameLine()
    
    if igButton("Cancel", vec2(120f, 0f)):
      igCloseCurrentPopup()

    igEndPopup()

proc run =
  if isDebug and keyEscape.tapped:
    quitApp()

  if fau.frameId mod 30 == 0:
    setWindowTitle(if config.lastProjectFile == "": "Lamina (empty project)" else: "Lamina: " & $config.lastProjectFile.splitFile.name & (if state.saved: "" else: " *"))

  fau.cam.use(size = fau.size * state.zoom)

  if not fau.captureMouse:
    state.zoom = clamp(state.zoom - fau.scroll.y / zoomSpeed * state.zoom, 0.001f, 100f)

    if keyMouseLeft.down or keyMouseRight.down:
      let pos = toCanvas(fau.mouseWorld)
      if pos.inBounds(state.size):
        if keyR.down:
          if keyMouseLeft.tapped:
            let idx = getTopLayer(pos)
            if idx != -1:
              state.selectedLayer = idx
        else:
          state.layers[state.selectedLayer].data[pos.x + pos.y*state.size.x] = not keyMouseRight.down
          state.changed = true

    if keyMouseMiddle.tapped:
      state.panPos = fau.mouse
    
    if keyMouseMiddle.down:
      fau.cam.pos -= (fau.mouse - state.panPos) * state.zoom
      state.panPos = fau.mouse
  
  if (keyMouseLeft.released or keyMouseRight.released) and state.changed:
    state.changed = false
    canvasChanged()

  drawCanvas()
  
  doUi()

initFau(run, init, initParams(title = "Lamina"))
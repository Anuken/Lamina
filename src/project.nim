
proc parseHook*(s: string, i: var int, v: var Bitset) =
  var str: string
  parseHook(s, i, str)

  v = newBitset(str.len)

  for i, c in str:
    v[i] = c == 'A'
  
proc dumpHook*(s: var string, v: Bitset) =
  s.add '"'
  for b in 0..<v.len:
    s.add (if v[b]: 'A' else: 'O')
  s.add '"'

proc parseHook*(s: string, i: var int, v: var Color) =
  var str: string
  parseHook(s, i, str)

  v = parseColor str
  
proc dumpHook*(s: var string, v: Color) =
  s.add '"'
  s.add $v
  s.add '"'

proc parseHook*(s: string, i: var int, v: var Blending) =
  var str: string
  parseHook(s, i, str)

  v = blendFromString(str)
  
proc dumpHook*(s: var string, v: Blending) =
  s.add '"'
  s.add $v
  s.add '"'

proc resetState =
  state = State()
  fau.cam.pos = vec2()
  canvasChanged()

proc newProject =
  const defaultSize = vec2i(8, 8)

  config.lastProjectFile = ""
  state = State(
    size: defaultSize,
    layers: @[newLayer(defaultSize, colorWhite)]
  )

  fau.cam.pos = vec2()
  resetZoom()

  canvasChanged()
  state.saved = true
  
proc saveConfig() = 
  try:
    writeFile(configFile, config.toJson())
  except:
    echo "Failed to write config: ", getCurrentExceptionMsg()

proc loadConfig() = 

  try:
    if configFile.fileExists:
      config = readFile(configFile).fromJson(Config)
  except:
    echo "Failed to read config: ", getCurrentExceptionMsg()

proc saveProject(file: string) = 
  try:
    writeFile(file, state.toJson())
  except:
    showError(&"Failed to write project file '{file}': {getCurrentExceptionMsg()}")

proc loadProject(file: string) = 
  let oldState = state

  try:
    if file.fileExists:
      config.lastFolder = file.parentDir
      state = readFile(file).fromJson(State)

      resetZoom()

      if state.layers.len == 0:
        raise Exception.newException("Invalid JSON (no project files)")
      
      config.lastProjectFile = file
      canvasChanged()
      state.saved = true
  except:
    state = oldState
    resetZoom()

    showError(&"Failed to read project file '{file}': {getCurrentExceptionMsg()}")

proc showImportFile(extrude: bool) =
  var path = openFileDialog(patterns = @["*.png"], filterDescription = "PNG files", defaultPathAndFile = config.lastFolder / "out.png")

  if path != "":
    importImage(path, extrude)

proc showSaveFile() =
  var path = saveFileDialog(patterns = @["*.json"], filterDescription = "JSON files", defaultPathAndFile = if config.lastProjectFile != "": config.lastProjectFile else: config.lastFolder / "out.json")
  if path != "":
    if path.splitFile.ext != ".json":
      path = path.parentDir / (path.splitFile.name & ".json")
    
    config.lastProjectFile = path
    saveProject(path)

proc showLoadFile() =
  let path = openFileDialog(patterns = @["*.json"], filterDescription = "JSON files", defaultPathAndFile = if config.lastProjectFile != "": config.lastProjectFile else: config.lastFolder / "out.json")
  if path != "":
    loadProject(path)
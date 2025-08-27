proc drawLayer(layer: Layer, size: Vec2i, offset: Vec2, scl: float32, color = layer.color) =
  template get(xc, yc: int): bool = inBounds(vec2i(xc, yc), size) and layer.data[xc + yc*size.x]

  proc tri(x1, y1, x2, y2, x3, y3: float32) =
    fillTri(vec2(x1, y1), vec2(x2, y2), vec2(x3, y3), color = color, blend = layer.blend)
  
  proc rect(x, y, w, h: float32) = 
    fillRect(x, y, w, h, color = color, blend = layer.blend)

  proc square(x, y, size: float32) = rect(x - 0.5f * scl, y - 0.5f * scl, size, size)

  proc index(x, y: int): int =
    let 
      botleft = get(x, y)
      botright = get(x + 1, y)
      topright = get(x + 1, y + 1)
      topleft = get(x, y + 1)
    return (botleft.int shl 3) or (botright.int shl 2) or (topright.int shl 1) or topleft.int;
  
  for y in -1..<size.y:
    for x in -1..<size.x:
      let index = index(x, y)

      let 
        xscl = 1f
        yscl = 1f
        ox = -size.x/2f + 0.5f
        oy = -size.y/2f + 0.5f
        leftx = x * xscl + ox
        boty = y * yscl + oy
        rightx = x * xscl + xscl + ox
        topy = y * xscl + yscl + oy
        midx = x * xscl + xscl / 2f + ox
        midy = y * yscl + yscl / 2f + oy

      case index:
      of 0: discard
      of 1:
        tri(
        leftx, midy,
        leftx, topy,
        midx, topy
        )
      of 2:
        tri(
        midx, topy,
        rightx, topy,
        rightx, midy
        )
      of 3:
        rect(leftx, midy, scl, scl / 2f)
      of 4:
        tri(
        midx, boty,
        rightx, boty,
        rightx, midy
        )
      of 5:
        #ambiguous

        #7
        tri(
        leftx, midy,
        midx, midy,
        midx, boty
        )

        #13
        tri(
        midx, topy,
        midx, midy,
        rightx, midy
        )

        rect(leftx, midy, scl / 2f, scl / 2f)
        rect(midx, boty, scl / 2f, scl / 2f)

      of 6:
        rect(midx, boty, scl / 2f, scl)
      of 7:
        #invert triangle
        tri(
        leftx, midy,
        midx, midy,
        midx, boty
        )

        #3
        rect(leftx, midy, scl, scl / 2f)

        rect(midx, boty, scl / 2f, scl / 2f)
      of 8:
        tri(
        leftx, boty,
        leftx, midy,
        midx, boty
        )
      of 9:
        rect(leftx, boty, scl / 2f, scl)
      of 10:
        #ambiguous

        #11
        tri(
        midx, boty,
        midx, midy,
        rightx, midy
        )

        #14
        tri(
        leftx, midy,
        midx, midy,
        midx, topy
        )

        rect(midx, midy, scl / 2f, scl / 2f)
        rect(leftx, boty, scl / 2f, scl / 2f)
  
      of 11:
        #invert triangle

        tri(
        midx, boty,
        midx, midy,
        rightx, midy
        )

        #3
        rect(leftx, midy, scl, scl / 2f)

        rect(leftx, boty, scl / 2f, scl / 2f)
      of 12:
        rect(leftx, boty, scl, scl / 2f)
      of 13:
        #invert triangle

        tri(
        midx, topy,
        midx, midy,
        rightx, midy
        )

        #12
        rect(leftx, boty, scl, scl / 2f)

        rect(leftx, midy, scl / 2f, scl / 2f)
      of 14:
        #invert triangle

        tri(
        leftx, midy,
        midx, midy,
        midx, topy
        )

        #12
        rect(leftx, boty, scl, scl / 2f)

        rect(midx, midy, scl / 2f, scl / 2f)
      of 15:
        square(midx, midy, scl)
      else:
        discard

proc renderToFile(outFile: string, scale: int = 16) =
  let buffer = newFramebuffer(state.size * scale)

  drawMat(ortho(-state.size.vec2/2f, state.size.vec2))

  drawBuffer(buffer)

  for layer in state.layers:
    drawLayer(layer, state.size, -state.size.vec2/2f, 1f)
  
  drawFlush()

  let pixels = buffer.read(vec2i(), buffer.size)
  let img = newImage(buffer.size.x, buffer.size.y)

  copyMem(addr img.data[0], pixels, buffer.size.x * buffer.size.y * 4)

  img.flipVertical()
  img.writeFile(outFile)
  
  dealloc pixels
  
  drawBufferScreen()

  fau.cam.use()

proc drawCanvas =
  canvasBuffer.resize(fau.sizei)
  canvasBuffer.clear()

  let 
    stroke = 2f.px * state.zoom
    bounds = rectCenter(vec2(), state.size.vec2)
    patch = initPatch(alphaTex, vec2(), state.size.vec2 * 2f)
    gridColor = colorLightGray
    mouse = toCanvas(fau.mouseWorld)

  if config.bg:
    drawRect(patch, bounds)

  drawBuffer(canvasBuffer)

  for i, layer in state.layers:
    let selected = keyR.down and i == getTopLayer(mouse)
    if layer.visible:
      drawLayer(layer, state.size, -state.size.vec2/2f, 1f, if selected: layer.color.mix(layer.color.inv, 0.1f) else: layer.color)
  
  drawBufferScreen()
  blit(canvasBuffer, params = meshParams(blend = blendNormal))

  if config.bg:
    lineRect(bounds, stroke = stroke, margin = stroke/2f, color = colorCoral)

  if config.grid:
    for x in 0..<(state.size.x-1):
      line(bounds.xy + vec2(x + 1f, 0f), bounds.xy + vec2(x + 1f, bounds.h), stroke = stroke, color = gridColor)

    for y in 0..<(state.size.y-1):
      line(bounds.xy + vec2(0f, y + 1f), bounds.xy + vec2(bounds.w, y + 1f), stroke = stroke, color = gridColor)
  
  if mouse.inBounds(state.size):
    lineRect(rectCenter(mouse.vec2 - state.size.vec2/2f + vec2(0.5f), vec2(1f)), color = colorCoral, stroke = 3f.px * state.zoom, margin = 3f.px * state.zoom/2f)
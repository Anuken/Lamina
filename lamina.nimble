version       = "0.0.1"
author        = "Anuken"
description   = "lamina"
license       = "who knows"
srcDir        = "src"
bin           = @["lamina"]
binDir        = "build"

requires "nim >= 2.0.0"

import strformat, os

template shell(args: string) =
  try: exec(args)
  except OSError: quit(1)

const
  app = "lamina"

  builds = [
    (name: "linux64", os: "linux", cpu: "amd64", args: ""),
    (name: "win64", os: "windows", cpu: "amd64", args: "--gcc.exe:x86_64-w64-mingw32-gcc --gcc.linkerexe:x86_64-w64-mingw32-g++"),
    (name: "mac64", os: "macosx", cpu: "amd64", args: "")
  ]

task pack, "Pack textures":
  shell &"faupack -p:{getCurrentDir()}/assets-raw/sprites -o:{getCurrentDir()}/assets/atlas"

task debug, "Debug build":
  shell &"nim r -d:debug src/{app}"

task packDebug, "Pack and run":
  packTask()
  debugTask()

task release, "Release build":
  shell &"nim r -d:release -d:danger -o:build/{app} src/{app}"

task web, "Deploy web build":
  mkDir "build/web"
  shell &"nim c -d:emscripten -d:danger src/{app}.nim"
  writeFile("build/web/index.html", readFile("build/web/index.html").replace("$title$", capitalizeAscii(app)))

task deployMac, "Build universal mac binary (doesn't work)":
  shell &"nim --cpu:arm64 --passL:\"-arch arm64\" --passC:\"-arch arm64\" --os:macosx --app:gui -d:danger -o:build/{app}-mac-arm c src/{app}"
  shell &"nim --cpu:amd64 --passL:\"-arch x86_64\" --passC:\"-arch arm64\" --os:macosx --app:gui -d:danger -o:build/{app}-mac-x86 c src/{app}"
  
  shell &"lipo -create build/{app}-mac-x86 build/{app}-mac-arm -output build/{app}-macos-universal"

task deploy, "Build for all platforms":
  packTask()

  for name, os, cpu, args in builds.items:
    if commandLineParams()[^1] != "deploy" and not name.startsWith(commandLineParams()[^1]):
      continue
    
    if (os == "macosx") != defined(macosx):
      continue

    let
      exeName = &"{app}-{name}"
      dir = "build"
      exeExt = if os == "windows": ".exe" else: ""
      bin = dir / exeName & exeExt

    mkDir dir
    shell &"nim --cpu:{cpu} --os:{os} --app:gui {args} -d:danger -o:{bin} c src/{app}"
    if not defined(macosx):
      shell &"strip -s {bin}"

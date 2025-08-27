when defined(nimsuggest) and not defined(nimscript): import system/nimscript except existsEnv

--path:"fau/src"
#--hints:off
--passC:"-DSTBI_ONLY_PNG"

#stop yelling
--warning:"BareExcept:off"
--warning:"HoleEnumConv:off"
--hint:"ConvFromXtoItselfNotNeeded:off"
--passC:"-Wno-error=incompatible-pointer-types"

--d:noAudio
--d:noRecorder
--d:debugVarEdit

#skips annoying errors in polymorph (I want to clear other systems!)
--d:ecsPermissive

when defined(sanitize):
  switch("passC", "-fsanitize=address")
  switch("passC", "-fsanitize=leak")
  switch("passL", "-fsanitize=address")
  switch("passL", "-fsanitize=leak")

--mm:arc
--tlsEmulation:off

when defined(release) or defined(danger):
  --passC:"-flto"
  --passL:"-flto"
  --d:strip
else:
  #better compiler/linker performance with local assets
  --d:localAssets
  #core profile catches more errors
  --d:fauGlCoreProfile

when defined(Android):
  #why isn't this the default??
  #--d:androidNDK
  --d:androidFullscreen

if defined(emscripten):
  --threads:off
  --os:linux
  --cpu:wasm32
  --cc:clang
  --clang.exe:emcc
  --clang.linkerexe:emcc
  --clang.cpp.exe:emcc
  --clang.cpp.linkerexe:emcc
  --listCmd

  --d:danger
  --define:useMalloc
  --define:noSignalHandler

  switch("passC", "-s USE_SDL=2")
  switch("passL", "-o build/web/index.html --shell-file shell.html -O3 -s LLD_REPORT_UNDEFINED -s USE_SDL=2 -s ALLOW_MEMORY_GROWTH=1 --closure 1 --preload-file assets")
else:

  when defined(Windows):
    #TODO does this work? needed for tlsEmulation:off
    --l:"-static"
    #x86_64-w64-mingw32-windres icon.rc -O coff -o icon.res
    #where icon.rc is: id ICON "icon.ico"
    --passL:"assets/icon.res"

    switch("passL", "-static-libstdc++ -static-libgcc")

  when defined(MacOSX):
    switch("clang.linkerexe", "g++")
  else:
    switch("gcc.linkerexe", "g++")

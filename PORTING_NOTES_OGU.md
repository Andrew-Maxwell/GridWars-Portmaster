# GridWars — Odroid Go Ultra (ROCKNIX) Porting Notes

## Status (as of 2026-05-10)

- **Working**: Game launches, renders, audio works, movement and twin-stick fire both correct, dead zones applied. Stable for 5+ minute sessions.

### Remaining TODOs

1. **Axis wizard exit with gamepad** — No way to exit the axis wizard screen using only a gamepad. gptokeyb (TODO 2) will fix this by mapping a button to Escape.

2. **Input bindings via gptokeyb** — gptokeyb is the PortMaster-standard way to remap gamepad buttons to keyboard/mouse events on a per-handheld basis. Goals:
   - Map left D-pad to movement (keyboard-style alternative to left stick)
   - Map right face buttons (ABXY) to secondary fire so players can choose keyboard-style or twin-stick style
   - Move bomb off the current menu button and move menu off the current face button — bind both to shoulder buttons instead
   - Map a button to Escape so the axis wizard can be exited

3. **Music** — GridWars never implemented Linux music. `sound.bmx` has an empty `?Linux` block where `StartMusic()` should be. Windows uses BASS (.it tracker files), macOS has an OGG stub. Need to implement OGG or similar for Linux.

4. **GridWars 1 visuals** — The GW2 visuals are considered too busy/ugly. Swap in GW1 assets. (User-side task.)

5. ~~**Auto-detect system resolution**~~ — **Done.** The launch script reads `DISPLAY_WIDTH`/`DISPLAY_HEIGHT` from the PortMaster environment and writes/patches `[Screen Width]`/`[Screen Height]` in Config.txt before every launch. The port now works on devices with different resolutions without any manual Config.txt setup.

---

## Build Environment

- **BlitzMax NG**: 0.138.3.53, arm64 native toolchain at `/workspace/bmx-ng/src/scripts/release/BlitzMax/`
- **Target**: `raspberrypi` platform + `arm64` arch (forces `opengles=true` in bmk)
- **Build command**:
  ```
  cd /workspace/GridWars
  PATH=/workspace/bmx-ng/src/scripts/release/BlitzMax/bin:$PATH \
    bmk makeapp -t gui -r -w -platform raspberrypi -arch arm64 gridwars.bmx
  ```
  - `-t gui`: GUI app type (required — the app uses windowing)
  - `-r`: release build
  - `-w`: warn on argument casting issues instead of error (needed for Float→Int calls in gridparttrail.bmx)
  - `-platform raspberrypi`: enables `opengles` define, targets GLES 2.0
  - `-arch arm64`: 64-bit ARM

- **SDL2 link stub**: The build system needs a `libSDL2-2.0.so.0` to link against. The OGU's system SDL2 (2.32.6) requires glibc 2.34+, so a compatible stub was built from SDL2 2.26.5 source on the glibc 2.31 build system:
  ```
  cmake -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_KMSDRM=ON ...
  # installed to /usr/lib/aarch64-linux-gnu/libSDL2-2.0.so.0
  ```
  This stub is only used at compile time. The actual SDL2 from the OGU's system (`/usr/lib/libSDL2-2.0.so.0`, v2.32.6) is used at runtime.

---

## Fixes Applied to BlitzMax sdl.mod (0.138.3.53)

All files are under `/workspace/bmx-ng/src/scripts/release/BlitzMax/mod/sdl.mod/`.

### Fix 1: Dynamic SDL2 linking for raspberrypi
**File**: `sdl.mod/sdl.mod/common.bmx`

The original code compiles SDL2 from source for all Linux platforms and statically links it. The source-compiled SDL2 is Raspberry Pi-specific and doesn't work on the OGU's Mali/KMSDRM hardware. Switching to dynamic linking lets the device's own SDL2 be used at runtime.

**Change** (around the `?linux` block):
```bmx
' Before:
?linux
Import "source.bmx"
?raspberrypi
Import "-lrt"

' After:
?linux And Not raspberrypi
Import "source.bmx"
?raspberrypi
Import "-lrt"
Import "-lSDL2"
```

### Fix 2: OpenGL-only symbol guards in gl2sdlmax2d
**File**: `sdl.mod/gl2sdlmax2d.mod/main.bmx`

When compiled with `opengles=true` (raspberrypi platform), three OpenGL-only symbols caused link errors. Each was wrapped in `?Not opengles` / `?` conditional blocks.

**a) `glewInit` in `TGL2SDLRenderimageContext.Create`** (around line 322):
```bmx
?Not opengles
If Not glewIsInit
    glewInit
    glewIsInit = True
EndIf
?
```

**b) `GL_RGBA8` in `CreateRenderTarget`** (around line 414–430): The entire FBO/render-target creation body uses `GL_RGBA8` which doesn't exist in GLES 2.0. Wrapped the whole body:
```bmx
Method CreateRenderTarget:TGL2SDLRenderImageFrame(width:Int, height:Int, UseImageFiltering:Int, pixmap:TPixmap)
    ?Not opengles
    ' ... full FBO creation body using GL_RGBA8 ...
    Return Self
    ?
EndMethod
```

**c) `glGetTexImage` in `ToPixmap`** (around line 460–470): OpenGL-only readback function, not available in GLES 2.0:
```bmx
Method ToPixmap:TPixmap(width:Int, height:Int)
    ?Not opengles
    ' ... body using glGetTexImage ...
    Return pixmap
    ?
EndMethod
```

### Fix 3: GLES context profile attributes for SDL window creation
**File**: `sdl.mod/sdlgraphics.mod/sdlgraphics.bmx`

Without telling SDL to create a GLES 2.0 context, SDL defaults to desktop OpenGL profile, which the Mali GPU does not support. Added inside the `If flags & SDL_GRAPHICS_GL Then` block, before window creation:

```bmx
If flags & SDL_GRAPHICS_GL Then
    flags :| SDL_WINDOW_OPENGL

    ?opengles
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, 4)  ' SDL_GL_CONTEXT_PROFILE_ES = 4
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 2)
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 0)
    ?

    If flags & GRAPHICS_BACKBUFFER Then SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1)
    ' ... rest of attribute setup ...
End If
```

### Fix 4: Correct SDL_GL_CONTEXT_PROFILE_MASK constant value
**File**: `sdl.mod/sdlvideo.mod/common.bmx`

The original sdlvideo.mod constants were off by one — it was missing `SDL_GL_CONTEXT_EGL = 19` in the enum, so `SDL_GL_CONTEXT_FLAGS` was 19 (should be 20) and `SDL_GL_CONTEXT_PROFILE_MASK` was 20 (should be 21). This caused GridWars to set `SDL_GL_CONTEXT_FLAGS = 4` (robust access flag) instead of the ES profile, producing `EGL_BAD_ATTRIBUTE` on context creation.

**Change**:
```bmx
' Before (wrong):
Const SDL_GL_CONTEXT_FLAGS:Int = 19
Const SDL_GL_CONTEXT_PROFILE_MASK:Int = 20
Const SDL_GL_SHARE_WITH_CURRENT_CONTEXT:Int = 21

' After (correct, matching SDL2 SDL_GLattr enum):
Const SDL_GL_CONTEXT_FLAGS:Int = 20
Const SDL_GL_CONTEXT_PROFILE_MASK:Int = 21
Const SDL_GL_SHARE_WITH_CURRENT_CONTEXT:Int = 22
```

Also update `SDL_GL_CONTEXT_RELEASE_BEHAVIOR` from 22 → 23 (and any subsequent constants in the enum).

---

## Fixes Applied to freeaudio (pub.mod/freeaudio.mod)

**File**: `/workspace/bmx-ng/src/scripts/release/BlitzMax/mod/pub.mod/freeaudio.mod/freeaudio.h`

ARM64 memory ordering race in the lockfree `queue` struct. The fix adds store-release/load-acquire semantics to the SPSC queue's `tail` variable, ensuring the element write is visible before the index advances.

```cpp
void push(sound *s)
{
    int t = tail;
    que[t] = s;
    __atomic_thread_fence(__ATOMIC_RELEASE);
    t = t + 1;
    if (t >= MAXCHANNELS) t = 0;
    __atomic_store_n(&tail, t, __ATOMIC_RELAXED);
}

sound *pull()
{
    sound *snd=0;
    int t = __atomic_load_n(&tail, __ATOMIC_ACQUIRE);
    if (head!=t)
    {
        snd=que[head];
        int h = head + 1;
        if (h>=MAXCHANNELS) h=0;
        head=h;
    }
    return snd;
}
```

**File**: `freeaudio.cpp` — `sample::refcount` made atomic to prevent double-free race:
```cpp
// In mixer::play():
__atomic_add_fetch(&sam->refcount, 1, __ATOMIC_RELAXED);

// In sample::free():
if (__atomic_sub_fetch(&refcount, 1, __ATOMIC_ACQ_REL) == 0) { ... }
```

The precompiled `.a` was rebuilt in-place by compiling the four C++ files natively with `g++ -fno-exceptions -O3 -fpie -DNDEBUG` and using `ar r` to update the archive.

---

## Fixes Applied to GridWars (control.bmx / gridwars.bmx)

### Right stick / axis mapping fix

**Root cause**: GridWars used raw `SDL_JoystickGetAxis` (via PUB.FreeJoy's `/dev/input/jsX` backend), bypassing `SDL_GAMECONTROLLERCONFIG`. The OGU's gamecontrollerdb correctly maps leftx→a0, lefty→a1, rightx→a2, righty→a3, but the game's defaults had fire X/Y swapped.

**Important gotcha**: Do NOT `Import SDL.SDLGameController` in BlitzMax. That module imports `SDL.SDLJoystick`, which calls `SDL_InitSubSystem(SDL_INIT_JOYSTICK)` and registers `TSDLJoystickDriver` as the default joystick driver, silently replacing `PUB.FreeJoy`. All `JoyX()`/`JoyY()` calls then go through SDL's joystick API instead of `/dev/input/js0`, with unpredictable axis mapping. Instead, declare only the SDL GC functions needed via a bare `Extern` block.

**Fix in `control.bmx`**:
- Replaced `Import SDL.SDLGameController` with direct `Extern` declarations for `SDL_NumJoysticks`, `SDL_IsGameController`, `SDL_GameControllerOpen`, `SDL_GameControllerClose`, `SDL_GameControllerMapping`
- Added `ApplyGCAxisDefaults()`: called after `SetUp()` (SDL must be initialized). Parses the `SDL_GameControllerMapping()` string to get correct raw jsX axis indices, writes them into `j[port]` for all ports where axis values weren't loaded from Config.txt (tracked via `joyAxisConfigured[]` flag). Also sets 0.2 dead zones if unset.
- Added `GCAxisFromMapping()`: parses both plain (`axis:a0`) and signed (`+axis:+a0`) SDL mapping string formats.
- `joyAxisConfigured[port]` is set to `True` when `[Joy Move X]` is loaded from Config.txt, so wizard-configured axes take priority over GC defaults.

**Fix in `gridwars.bmx`**:
- `ApplyGCAxisDefaults()` called after `SetUp()` (not before `LoadConfig()`).

### GFX update
- All `.PNG` filenames renamed to `.png` (case-sensitive Linux filesystem)

---

## OGU Runtime Configuration

### Config file (device-side)
GridWars reads `$HOME/.config/gridwars/Config.txt`. On ROCKNIX, `$HOME = /storage`, so the file lives at `/storage/.config/gridwars/Config.txt`.

The game saves a full Config.txt on exit. For a clean first run, a minimal seed config is sufficient:

```
[Screen Width]
854
[Screen Height]
480
[Windowed]
False
```

The OGU screen is 854×480. Without a config the game tries 1024×768 fullscreen, which doesn't exist, and crashes immediately.

After first launch the game writes a full config. The dead zones default to 0 — set them to 0.25 for the OGU's sticks:

```bash
sed -i '/Dead Zone/{n; s/0\.00000000/0.25/}' /storage/.config/gridwars/Config.txt
```

Or adjust via the in-game joystick setup screen (± buttons on the dead zone row).

### Wayland / display environment
The OGU uses Weston (Wayland compositor) at socket `/run/0-runtime-dir/wayland-1`. When launched from EmulationStation (which runs under Weston), `XDG_RUNTIME_DIR` is inherited and SDL connects to Wayland automatically. From SSH it is NOT set, causing SDL to fall back to the broken offscreen EGL driver. Do not test by running the binary directly over SSH.

---

## Launch Script

GridWars is launched via the PortMaster Doukutsu-rs script, hacked to point at GridWars (`/roms/ports/Doukutsu-rs.sh`).

**Key redirections**:
```bash
GAMEDIR=/$directory/ports/GridWars
CONFDIR="$GAMEDIR/conf/"
BINARY=gridwars
```

**Auto-resolution fix** — Added before the binary launch. Reads `DISPLAY_WIDTH`/`DISPLAY_HEIGHT` from the PortMaster/EmulationStation environment (set by `device_info.txt` on most platforms; on ROCKNIX these come from the ES environment). Creates Config.txt with the correct screen resolution on first run, or patches the two resolution values on subsequent runs without touching any other settings:

```bash
# Get display resolution (normally set by EmulationStation env on ROCKNIX;
# source device_info.txt as fallback for platforms that don't set it).
if [ -z "$DISPLAY_WIDTH" ] || [ -z "$DISPLAY_HEIGHT" ]; then
  source "$controlfolder/device_info.txt"
fi

GRIDWARS_CONF="$HOME/.config/gridwars/Config.txt"
mkdir -p "$HOME/.config/gridwars"

_gw_set_resolution() {
    local file="$1" key="$2" value="$3"
    local tmp; tmp=$(mktemp)
    local found=0 next_is_value=0
    while IFS= read -r line; do
        if [ "$next_is_value" -eq 1 ]; then
            printf '%s\n' "$value"; next_is_value=0; found=1
        else
            printf '%s\n' "$line"
        fi
        [ "$line" = "[$key]" ] && next_is_value=1
    done < "$file" > "$tmp"
    [ "$found" -eq 0 ] && printf '[%s]\n%s\n' "$key" "$value" >> "$tmp"
    mv "$tmp" "$file"
}

if [ ! -f "$GRIDWARS_CONF" ]; then
    printf '[Screen Width]\n%s\n[Screen Height]\n%s\n[Windowed]\nFalse\n' \
        "$DISPLAY_WIDTH" "$DISPLAY_HEIGHT" > "$GRIDWARS_CONF"
else
    _gw_set_resolution "$GRIDWARS_CONF" "Screen Width"  "$DISPLAY_WIDTH"
    _gw_set_resolution "$GRIDWARS_CONF" "Screen Height" "$DISPLAY_HEIGHT"
fi
```

PortMaster's `libgl_ROCKNIX.txt` is sourced automatically, which sets `LIBGL_ES=2`, `LIBGL_GL=21`, `LIBGL_FB=4` and prepends any `gl4es.$DEVICE_ARCH/` to `LD_LIBRARY_PATH`. GridWars does NOT use GL4ES (it uses GLES directly), but the script sourcing is harmless.

---

## Root Cause Chain (for reference)

1. **BlitzMax `raspberrypi` platform**: bmk sets `opengles=true`, enabling `?opengles` blocks and disabling `?Not opengles` blocks in all modules.
2. **Static SDL2 incompatibility**: sdl.mod compiled a Raspberry Pi-specific SDL2 from source; that binary doesn't support the OGU's Mali/GBM hardware → switched to dynamic `-lSDL2`.
3. **No GLES context profile set**: Without `SDL_GL_CONTEXT_PROFILE_MASK = SDL_GL_CONTEXT_PROFILE_ES`, SDL tried to create a desktop OpenGL context; Mali only supports GLES → added `?opengles` block in sdlgraphics.bmx.
4. **Wrong constant value**: `SDL_GL_CONTEXT_PROFILE_MASK` was 20 in sdlvideo.mod but 21 in SDL2's actual enum → was setting `SDL_GL_CONTEXT_FLAGS = 4` (robust access) which Mali's EGL rejected with `EGL_BAD_ATTRIBUTE` → fixed constants.
5. **Wrong resolution**: GridWars defaulted to 1024×768 fullscreen, OGU only supports 854×480 → added config file.
6. **OpenGL-only symbols**: `glewInit`, `GL_RGBA8`, `glGetTexImage` not available in GLES 2.0 → guarded with `?Not opengles`.
7. **ARM64 audio race**: freeaudio's lockfree queue lacked memory barriers → added store-release/load-acquire.
8. **Axis mapping**: Raw jsX axis defaults for fire were swapped; GC mapping now applied at startup for unconfigured ports.
9. **SDL joystick driver takeover**: Importing `SDL.SDLGameController` replaces PUB.FreeJoy → use bare Extern declarations instead.

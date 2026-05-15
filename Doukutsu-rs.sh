#!/bin/bash
# PORTMASTER: doukutsu-rs.zip, Doukutsu-rs.sh

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

source $controlfolder/control.txt

[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"

get_controls

GAMEDIR=/$directory/ports/GridWars
CONFDIR="$GAMEDIR/conf/"
BINARY=gridwars

mkdir -p "$GAMEDIR/conf"

cd $GAMEDIR

> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

bind_directories ~/.local/share/doukutsu-rs $GAMEDIR/conf

export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"

if [ -f "${controlfolder}/libgl_${CFW_NAME}.txt" ]; then
  source "${controlfolder}/libgl_${CFW_NAME}.txt"
else
  source "${controlfolder}/libgl_default.txt"
fi

if [ "${CFW_NAME}" != ROCKNIX ] && [ "$LIBGL_FB" != "" ]; then
  export SDL_VIDEO_GL_DRIVER="$GAMEDIR/gl4es.aarch64/libGL.so.1"
  export SDL_VIDEO_EGL_DRIVER="$GAMEDIR/gl4es.aarch64/libEGL.so.1"
fi

# Get display resolution (set by ES env on ROCKNIX; device_info.txt as fallback)
if [ -z "$DISPLAY_WIDTH" ] || [ -z "$DISPLAY_HEIGHT" ]; then
  source "$controlfolder/device_info.txt"
fi

GRIDWARS_CONF="$HOME/.config/gridwars/Config.txt"
mkdir -p "$HOME/.config/gridwars"

# Compute playfield size: match display if >=720p, otherwise scale up to 768 tall
if [ "$DISPLAY_HEIGHT" -gt 700 ]; then
    PF_WIDTH=$DISPLAY_WIDTH
    PF_HEIGHT=$DISPLAY_HEIGHT
else
    PF_HEIGHT=768
    PF_WIDTH=$(( 768 * DISPLAY_WIDTH / DISPLAY_HEIGHT ))
fi

# Set first occurrence of key; appends if missing
_gw_set_key() {
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
    # Fresh install: seed config with display resolution and keyboard bindings.
    # Button/axis assignments are set at runtime by ApplyGCAxisDefaults() from
    # the SDL GameController mapping, so they are intentionally omitted here.
    cat > "$GRIDWARS_CONF" << CONF
[Screen Width]
${DISPLAY_WIDTH}
[Screen Height]
${DISPLAY_HEIGHT}
[Windowed]
False
[Playfield Width]
${PF_WIDTH}
[Playfield Height]
${PF_HEIGHT}
[Key Bomb]
82
[Key Move Left]
37
[Key Move Right]
39
[Key Move Up]
38
[Key Move Down]
40
[Key Fire Left]
88
[Key Fire Right]
66
[Key Fire Up]
89
[Key Fire Down]
65
[Used Port]
0
[Joy Port]
0
[Joy Move X Inverted]
1
[Joy Move Y Inverted]
1
[Joy Fire X Inverted]
1
[Joy Fire Y Inverted]
1
[Joy Move X Scale]
1
[Joy Move Y Scale]
1
[Joy Fire X Scale]
1
[Joy Fire Y Scale]
1
[Joy Move X Center]
0.000000000
[Joy Move Y Center]
0.000000000
[Joy Fire X Center]
0.000000000
[Joy Fire Y Center]
0.000000000
[Joy Move X Dead Zone]
0.25
[Joy Move Y Dead Zone]
0.25
[Joy Fire X Dead Zone]
0.25
[Joy Fire Y Dead Zone]
0.25
CONF
else
    # Existing config: force screen resolution to match the display
    _gw_set_key "$GRIDWARS_CONF" "Screen Width"  "$DISPLAY_WIDTH"
    _gw_set_key "$GRIDWARS_CONF" "Screen Height" "$DISPLAY_HEIGHT"
fi

$GPTOKEYB "$BINARY" -c "./$BINARY.gptk" &

pm_platform_helper gdb -batch -ex run -ex bt --args "$GAMEDIR/$BINARY"

./$BINARY

pm_finish

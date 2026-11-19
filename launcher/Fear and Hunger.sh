#!/bin/sh
# Miyoo A30 / SpruceOS - Fear & Hunger (RPG Maker MV on quixjs armhf)
ROM_DIR="$(cd "$(dirname "$0")" && pwd)"
GAMEDIR="$ROM_DIR/fearandhunger"
cd "$GAMEDIR" || exit 1

export LD_LIBRARY_PATH="$GAMEDIR:/mnt/SDCARD/spruce/a30/sdl2/sdl2:/mnt/SDCARD/miyoo/lib:/lib:/usr/lib:${LD_LIBRARY_PATH:-}"
export SDL_VIDEODRIVER=mali
export SDL_RENDER_DRIVER=opengles2
export SDL_FBDEV=/dev/fb0
export SDL_AUDIODRIVER=alsa
export AUDIODEV=plughw:0,0
export SDL_NOMOUSE=1
export QUIX_ROT=270
export QUIX_A30_KEYS=1
export QUIXJS_FONT="$GAMEDIR/fonts/DejaVuSans-Bold.ttf"

# A30 pad: use js0 with an explicit controller mapping
export SDL_JOYSTICK_DEVICE=/dev/input/js0
export SDL_LINUX_JOYSTICK_CLASSIC=1
export SDL_JOYSTICK_HIDAPI=0
export SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1
export SDL_GAMECONTROLLERCONFIG_FILE="$GAMEDIR/gamecontrollerdb.txt"
export SDL_GAMECONTROLLERCONFIG="$(grep -v "^[[:space:]]*#" "$GAMEDIR/gamecontrollerdb.txt" | grep -v "^[[:space:]]*$")"

# release event4 from joystickinput so SDL can open the pad
killall -q -USR2 joystickinput 2>/dev/null

./quixjs.armhf -c port.toml > "$GAMEDIR/log.txt" 2>&1
rc=$?
exit $rc

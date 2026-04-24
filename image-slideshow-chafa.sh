#!/usr/bin/env bash
# Terminal media viewer using chafa — slideshow + scroll feed modes
# Usage: image-slideshow-chafa.sh [directory] [delay_seconds]
# Controls: n=next | p=prev | b=pause | r=rotate | m=mode | j/k=±1s delay | l/u=±5% width | i=info | q=quit
# Requires: chafa (yay -S chafa), ffmpeg for video, imagemagick for rotation

set -eo pipefail

SETTINGS_FILE="$HOME/.chafa_slideshow_settings"
TEMP_DIR="/tmp/chafa_slideshow-$$"
CONVERSION_QUEUE="$TEMP_DIR/queue"

# ---- dependency check ----
if ! command -v chafa &> /dev/null; then
    echo "Error: 'chafa' not found. Install with: yay -S chafa"
    exit 1
fi

HAS_FFMPEG=false
if command -v ffmpeg &> /dev/null; then HAS_FFMPEG=true; fi

HAS_CONVERT=false
if command -v convert &> /dev/null; then HAS_CONVERT=true; fi

# ---- load or prompt for settings ----
if [[ -n "$1" ]]; then
    # Args passed directly — skip interactive prompt
    IMAGE_DIR="${1/#\~/$HOME}"
    DELAY="${2:-10}"
    MODE="slideshow"
    ROTATE=false
    WIDTH_PERCENT=100
else
    if [[ -f "$SETTINGS_FILE" ]]; then
        LAST_DIR=$(sed -n '1p' "$SETTINGS_FILE")
        LAST_DELAY=$(sed -n '2p' "$SETTINGS_FILE")
        LAST_MODE=$(sed -n '3p' "$SETTINGS_FILE")
        LAST_ROTATE=$(sed -n '4p' "$SETTINGS_FILE")
        LAST_WIDTH=$(sed -n '5p' "$SETTINGS_FILE")

        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "🎬 Chafa Media Viewer"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "Last settings:"
        echo "  Directory : $LAST_DIR"
        echo "  Delay     : ${LAST_DELAY}s"
        echo "  Mode      : $LAST_MODE"
        echo "  Rotation  : $LAST_ROTATE"
        echo "  Width     : ${LAST_WIDTH}%"
        echo ""
        read -e -p "Press Enter to use last settings, or type a new directory path: " USER_INPUT

        if [[ -z "$USER_INPUT" ]]; then
            IMAGE_DIR="$LAST_DIR"
            DELAY="$LAST_DELAY"
            MODE="$LAST_MODE"
            ROTATE="$LAST_ROTATE"
            WIDTH_PERCENT="${LAST_WIDTH:-100}"
            echo "✓ Using saved settings"
            echo ""
            read -p "Starting zoom % (default ${WIDTH_PERCENT}): " WIDTH_INPUT
            [[ -n "$WIDTH_INPUT" ]] && WIDTH_PERCENT="$WIDTH_INPUT"
        else
            IMAGE_DIR="${USER_INPUT/#\~/$HOME}"
            read -p "Delay in seconds (default ${LAST_DELAY}): " DELAY_INPUT
            DELAY="${DELAY_INPUT:-$LAST_DELAY}"
            read -p "Starting zoom % (default ${LAST_WIDTH:-100}): " WIDTH_INPUT
            WIDTH_PERCENT="${WIDTH_INPUT:-${LAST_WIDTH:-100}}"
            MODE="${LAST_MODE:-slideshow}"
            ROTATE="${LAST_ROTATE:-false}"
        fi
    else
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "🎬 Chafa Media Viewer — First Run Setup"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        read -e -p "Directory path with images/videos: " DIR_INPUT
        IMAGE_DIR="${DIR_INPUT/#\~/$HOME}"
        read -p "Delay in seconds (default 10): " DELAY_INPUT
        DELAY="${DELAY_INPUT:-10}"
        read -p "Starting zoom % (default 100): " WIDTH_INPUT
        WIDTH_PERCENT="${WIDTH_INPUT:-100}"
        MODE="slideshow"
        ROTATE=false
    fi
fi

# ---- startup prompts (skip if args were passed) ----
if [[ -z "$1" ]]; then
    echo "Display mode:"
    echo "  [s] Slideshow — clears screen between images"
    echo "  [f] Feed      — images scroll/append below each other"
    printf "Choice (current: %s): " "$MODE"
    read -r -n 1 mode_answer
    echo ""
    if [[ "$mode_answer" =~ ^[Ff]$ ]]; then
        MODE="feed"
    elif [[ "$mode_answer" =~ ^[Ss]$ ]]; then
        MODE="slideshow"
    fi
    echo "Mode: $MODE"
    echo ""

    printf "Rotate 90 degrees? [y/N] (current: %s): " "$ROTATE"
    read -r -n 1 rotate_answer
    echo ""
    if [[ "$rotate_answer" =~ ^[Yy]$ ]]; then
        ROTATE=true
    elif [[ "$rotate_answer" =~ ^[Nn]$ ]]; then
        ROTATE=false
    fi
    [[ $ROTATE == true ]] && echo "✅ Rotation ON" || echo "➡️  Rotation OFF"
    echo ""
fi

# ---- validate ----
if ! [[ "$DELAY" =~ ^[0-9]+$ ]]; then
    echo "Invalid delay, defaulting to 10"
    DELAY=10
fi
if ! [[ "$WIDTH_PERCENT" =~ ^[0-9]+$ ]]; then
    WIDTH_PERCENT=100
fi

if [[ ! -d "$IMAGE_DIR" ]]; then
    echo "Error: Directory not found: $IMAGE_DIR"
    exit 1
fi

# ---- save settings ----
mkdir -p "$TEMP_DIR"
touch "$CONVERSION_QUEUE"
{
    echo "$IMAGE_DIR"
    echo "$DELAY"
    echo "$MODE"
    echo "$ROTATE"
    echo "$WIDTH_PERCENT"
} > "$SETTINGS_FILE"

# ---- gather media ----
shopt -s nullglob
IMAGES=("$IMAGE_DIR"/*.{jpg,jpeg,png,gif,JPG,JPEG,PNG,GIF,webp,WEBP,bmp,BMP})
VIDEOS=("$IMAGE_DIR"/*.{mp4,MP4,mov,MOV,webm,WEBM,mkv,MKV,avi,AVI,m4v,M4V,flv,FLV,wmv,WMV,vob,VOB,ogv,OGV})

MEDIA=("${IMAGES[@]}")

if [[ ${#MEDIA[@]} -eq 0 ]] && [[ ${#VIDEOS[@]} -eq 0 ]]; then
    echo "Error: No media found in $IMAGE_DIR"
    rm -rf "$TEMP_DIR"; exit 1
fi

# If only videos, block-convert first one before starting
if [[ ${#MEDIA[@]} -eq 0 ]] && [[ ${#VIDEOS[@]} -gt 0 ]]; then
    if [[ $HAS_FFMPEG == false ]]; then
        echo "Error: Only videos found but ffmpeg is not available."
        rm -rf "$TEMP_DIR"; exit 1
    fi
    echo "🎬 Converting first video to GIF..."
    first_video="${VIDEOS[0]}"
    output="$TEMP_DIR/$(basename "$first_video").gif"
    if ffmpeg -i "$first_video" \
        -vf "fps=30,scale=320:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" \
        -c:v gif -f gif "$output" -y &>/dev/null; then
        MEDIA=("$output")
        VIDEOS=("${VIDEOS[@]:1}")
    else
        echo "Error: Failed to convert video"
        rm -rf "$TEMP_DIR"; exit 1
    fi
fi

# Shuffle at startup
MEDIA=($(shuf -e "${MEDIA[@]}"))
TOTAL=${#MEDIA[@]}

# ---- background video converter ----
convert_videos_background() {
    for video in "${VIDEOS[@]}"; do
        output="$TEMP_DIR/$(basename "$video").gif"
        if ffmpeg -i "$video" \
            -vf "fps=30,scale=320:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" \
            -c:v gif -f gif "$output" -y &>/dev/null; then
            echo "$output" >> "$CONVERSION_QUEUE"
        fi
    done
}

if [[ ${#VIDEOS[@]} -gt 0 ]] && [[ $HAS_FFMPEG == true ]]; then
    convert_videos_background &
    CONVERTER_PID=$!
fi

# ---- check for newly converted GIFs, insert at random position ----
check_new_videos() {
    if [[ -f "$CONVERSION_QUEUE" ]]; then
        while IFS= read -r new_gif; do
            if [[ -f "$new_gif" ]] && [[ ! " ${MEDIA[@]} " =~ " ${new_gif} " ]]; then
                local random_pos=$((RANDOM % (${#MEDIA[@]} + 1)))
                MEDIA=("${MEDIA[@]:0:random_pos}" "$new_gif" "${MEDIA[@]:random_pos}")
                TOTAL=${#MEDIA[@]}
            fi
        done < "$CONVERSION_QUEUE"
        > "$CONVERSION_QUEUE"
    fi
}

# ---- rotation: prepare display copy (cached in TEMP_DIR) ----
prepare_file() {
    local src="$1"
    if [[ $ROTATE != true ]]; then
        echo "$src"; return
    fi
    local rotated="$TEMP_DIR/rotated_$(basename "$src")"
    if [[ ! -f "$rotated" ]]; then
        if [[ $HAS_CONVERT == true ]]; then
            convert "$src" -rotate 90 "$rotated" 2>/dev/null || rotated="$src"
        elif [[ $HAS_FFMPEG == true ]]; then
            ffmpeg -i "$src" -vf "transpose=1" "$rotated" -y &>/dev/null || rotated="$src"
        else
            rotated="$src"
        fi
    fi
    echo "$rotated"
}

# ---- save delay to settings ----
save_delay() {
    sed -i "2s/.*/$DELAY/" "$SETTINGS_FILE" 2>/dev/null || true
}

# ---- save width to settings ----
save_width() {
    sed -i "5s/.*/$WIDTH_PERCENT/" "$SETTINGS_FILE" 2>/dev/null || true
}

# ---- detect terminal graphics format ----
# Priority: Kitty native > Shellfish sixels > sixels fallback > Unicode symbols
detect_chafa_format() {
    if [[ -n "$KITTY_WINDOW_ID" ]] || [[ "$TERM" == "xterm-kitty" ]]; then
        echo "kitty"; return
    fi
    if [[ "$TERM_PROGRAM" == "ShellFish" ]]; then
        echo "sixels"; return
    fi
    if [[ "$TERM" == *"256color"* ]] || [[ "$COLORTERM" == "truecolor" ]] || [[ "$COLORTERM" == "24bit" ]]; then
        echo "sixels"; return
    fi
    echo "symbols"
}

# ---- get terminal pixel dimensions (Kitty only) ----
# Uses `kitty +kitten icat --print-window-size` which prints px_width x px_height.
# Falls back to stty-based TIOCGWINSZ row 3/4 fields if kitten is unavailable.
# Returns "WxH" in pixels, or empty string on failure.
get_chafa_size() {
    local fmt="$1"
    local term_cols term_rows
    term_cols=$(tput cols)
    term_rows=$(tput lines)

    local img_cols=$(( term_cols * WIDTH_PERCENT / 100 ))

    if [[ "$MODE" == "slideshow" ]]; then
        # Kitty needs 2 fewer reserved rows than sixels — its cell height is slightly
        # taller so the default 8-row reserve was causing the bottom gap.
        local reserve=8
        [[ "$fmt" == "kitty" ]] && reserve=6
        local img_rows=$(( term_rows - reserve ))
        [[ $img_rows -lt 5 ]] && img_rows=5
        echo "${img_cols}x${img_rows}"
    else
        echo "${img_cols}x"
    fi
}

# ---- check if a file is an animated GIF ----
is_animated_gif() {
    local file="$1"
    [[ "${file,,}" != *.gif ]] && return 1
    # identify (imagemagick) counts frames; ffprobe works too
    if command -v identify &>/dev/null; then
        local frames
        frames=$(identify "$file" 2>/dev/null | wc -l)
        [[ $frames -gt 1 ]] && return 0
    elif command -v ffprobe &>/dev/null; then
        local frames
        frames=$(ffprobe -v quiet -select_streams v:0 \
            -count_frames -show_entries stream=nb_read_frames \
            -of csv=p=0 "$file" 2>/dev/null)
        [[ ${frames:-0} -gt 1 ]] && return 0
    else
        # No tools to check — assume all GIFs may be animated
        return 0
    fi
    return 1
}

# ---- build chafa command based on current width ----
# --scale max allows upscaling to fill the requested --size dimensions
# GIFs play exactly once (--loops 1) then hand control back to the slideshow.
# Feed mode omits height in --size so images flow naturally downward.
# Sizing is character cells for sixels/symbols, pixels for kitty format.

run_chafa() {
    local file="$1"

    local fmt
    fmt=$(detect_chafa_format)

    local size
    size=$(get_chafa_size "$fmt")

    # Animated GIFs: play once then return so the slideshow can advance
    local gif_loops_arg=""
    if is_animated_gif "$file"; then
        gif_loops_arg="--loops 1"
    fi

    chafa --size "$size" --scale max -f "$fmt" $gif_loops_arg "$file"
}

# ---- SLIDESHOW mode: clear screen, show one image at a time ----
show_image_slideshow() {
    local idx=$1
    [[ $TOTAL -eq 0 ]] && return 1

    local file="${MEDIA[$idx]}"
    local attempts=0

    while [[ $attempts -lt 3 ]]; do
        if [[ -f "$file" ]]; then
            clear
            if [[ $VERBOSE == true ]]; then
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo "📸 [$(( idx + 1 ))/$TOTAL] $(basename "$file")"
                [[ $PAUSED == true ]] && echo "⏸️  PAUSED" || echo "▶️  PLAYING  ⏱️  ${DELAY}s"
                echo "🔍 WIDTH: ${WIDTH_PERCENT}% | 🔄 ROTATE: $ROTATE | 📺 MODE: $MODE"
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo ""
            fi
            local display_file
            display_file=$(prepare_file "$file")
            if run_chafa "$display_file"; then
                if [[ $VERBOSE == true ]]; then
                    echo ""
                    echo "Controls: [n]ext | [p]rev | [b]pause | [j/k]±1s | [l/u]±5% | [r]otate | [m]ode | [i]nfo | [h]ide | [q]uit"
                fi
                return 0
            else
                echo "⚠️  chafa failed (attempt $((attempts+1))/3)"
                sleep 0.5
            fi
        fi
        (( attempts++ ))
    done

    CURRENT_IDX=$(( (CURRENT_IDX + 1) % TOTAL ))
    return 1
}

# ---- FEED mode: append image below previous (no clear) ----
show_image_feed() {
    local file="${MEDIA[$CURRENT_IDX]}"
    [[ ! -f "$file" ]] && return 1

    if [[ $VERBOSE == true ]]; then
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        printf "📸 [%d/%d] " "$(( CURRENT_IDX + 1 ))" "$TOTAL"
        printf '\e]8;;file://%s\a%s\e]8;;\a\n' "$file" "$(basename "$file")"
        echo "🔍 WIDTH: ${WIDTH_PERCENT}% | ⏱️  ${DELAY}s | 🔄 $ROTATE | 📺 $MODE"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
    fi

    local display_file
    display_file=$(prepare_file "$file")

    if ! run_chafa "$display_file"; then
        return 1
    fi

    if [[ $VERBOSE == true ]]; then
        echo ""
        echo "Controls: [n]ext | [p]rev | [b]pause | [j/k]±1s | [l/u]±5% | [r]otate | [m]ode | [h]ide | [q]uit"
        echo ""
    fi
    return 0
}

# ---- info screen ----
show_info() {
    local file="${MEDIA[$CURRENT_IDX]}"
    clear
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📋 MEDIA INFO"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "File : $(basename "$file")"
    echo "Path : $file"
    echo "Size : $(du -h "$file" | cut -f1)"
    if command -v identify &> /dev/null; then
        echo ""
        identify -verbose "$file" 2>/dev/null | grep -E "^  (Geometry|Format|Filesize|Colorspace|Depth):" || true
    elif command -v ffprobe &> /dev/null; then
        echo ""
        ffprobe -v quiet -show_format -show_streams "$file" 2>/dev/null \
            | grep -E "^(width|height|duration|codec_name|size)=" || true
    fi
    echo ""
    echo "Press any key to return..."
    read -r -n 1
}

# ---- cleanup ----
cleanup() {
    stty sane 2>/dev/null || true
    clear
    [[ -n "${CONVERTER_PID:-}" ]] && kill "$CONVERTER_PID" 2>/dev/null || true
    rm -rf "$TEMP_DIR"
    exit
}

trap cleanup EXIT INT TERM
stty -echo -icanon time 0 min 0

CURRENT_IDX=0
PAUSED=false
NEXT_NOW=false
VERBOSE=true   # Toggle with [h] to hide/show header and controls

echo ""
echo "🎬 Starting in $MODE mode with ${DELAY}s delay | ${WIDTH_PERCENT}% width"
echo ""

# ---- main loop ----
while true; do
    check_new_videos

    # Show image depending on mode
    if [[ "$MODE" == "slideshow" ]]; then
        show_image_slideshow $CURRENT_IDX || { CURRENT_IDX=$(( (CURRENT_IDX + 1) % TOTAL )); continue; }
    else
        if [[ $PAUSED == false ]] || [[ $NEXT_NOW == true ]]; then
            show_image_feed || { CURRENT_IDX=$(( (CURRENT_IDX + 1) % TOTAL )); continue; }
            CURRENT_IDX=$(( (CURRENT_IDX + 1) % TOTAL ))
        fi
    fi

    NEXT_NOW=false

    # ---- input loop ----
    if [[ $PAUSED == false ]]; then
        for ((i=0; i < DELAY*10; i++)); do
            read -t 0.1 -n 1 key || true
            case "$key" in
                n|N)
                    if [[ "$MODE" == "slideshow" ]]; then
                        CURRENT_IDX=$(( (CURRENT_IDX + 1) % TOTAL ))
                    fi
                    NEXT_NOW=true
                    break
                    ;;
                p|P)
                    CURRENT_IDX=$(( (CURRENT_IDX - 1 + TOTAL) % TOTAL ))
                    if [[ "$MODE" == "slideshow" ]]; then
                        break
                    else
                        show_image_feed || true
                        CURRENT_IDX=$(( (CURRENT_IDX + 1) % TOTAL ))
                        i=0
                    fi
                    ;;
                b|B)
                    PAUSED=true
                    [[ "$MODE" == "slideshow" ]] && show_image_slideshow $CURRENT_IDX || true
                    break
                    ;;
                j|J)
                    DELAY=$(( DELAY - 1 ))
                    [[ $DELAY -lt 1 ]] && DELAY=1
                    save_delay
                    [[ "$MODE" == "slideshow" ]] && show_image_slideshow $(( (CURRENT_IDX - 1 + TOTAL) % TOTAL )) && i=0 || true
                    ;;
                k|K)
                    DELAY=$(( DELAY + 1 ))
                    save_delay
                    [[ "$MODE" == "slideshow" ]] && show_image_slideshow $(( (CURRENT_IDX - 1 + TOTAL) % TOTAL )) && i=0 || true
                    ;;
                l|L)
                    WIDTH_PERCENT=$(( WIDTH_PERCENT + 5 ))
                    save_width
                    [[ "$MODE" == "slideshow" ]] && show_image_slideshow $(( (CURRENT_IDX - 1 + TOTAL) % TOTAL )) && i=0 || true
                    ;;
                u|U)
                    WIDTH_PERCENT=$(( WIDTH_PERCENT - 5 ))
                    [[ $WIDTH_PERCENT -lt 10 ]] && WIDTH_PERCENT=10
                    save_width
                    [[ "$MODE" == "slideshow" ]] && show_image_slideshow $(( (CURRENT_IDX - 1 + TOTAL) % TOTAL )) && i=0 || true
                    ;;
                r|R)
                    ROTATE=$( [[ $ROTATE == true ]] && echo false || echo true )
                    rm -f "$TEMP_DIR"/rotated_*
                    sed -i "4s/.*/$ROTATE/" "$SETTINGS_FILE" 2>/dev/null || true
                    [[ "$MODE" == "slideshow" ]] && break || true
                    ;;
                m|M)
                    # Toggle mode
                    [[ "$MODE" == "slideshow" ]] && MODE="feed" || MODE="slideshow"
                    sed -i "3s/.*/$MODE/" "$SETTINGS_FILE" 2>/dev/null || true
                    break
                    ;;
                i|I)
                    [[ "$MODE" == "slideshow" ]] && show_info && break || true
                    ;;
                h|H)
                    VERBOSE=$( [[ $VERBOSE == true ]] && echo false || echo true )
                    [[ "$MODE" == "slideshow" ]] && show_image_slideshow $(( (CURRENT_IDX - 1 + TOTAL) % TOTAL )) && i=0 || true
                    ;;
                q|Q)
                    cleanup
                    ;;
            esac
        done

        # Auto-advance after delay (slideshow mode only — feed advances in main loop)
        if [[ "$MODE" == "slideshow" ]] && [[ $i -eq $((DELAY*10)) ]]; then
            CURRENT_IDX=$(( (CURRENT_IDX + 1) % TOTAL ))
        fi
    else
        # ---- paused input ----
        # FIX: stty is in non-blocking mode (time 0 min 0), so plain `read` returns
        # immediately with an empty string even when no key is pressed. We must loop
        # and skip empty reads, otherwise the paused block exits instantly and
        # playback resumes as if pause was never pressed.
        while true; do
            read -r -t 0.1 -n 1 key || true
            [[ -z "$key" ]] && continue   # no keypress yet — keep waiting
            case "$key" in
                b|B|p|P)
                    PAUSED=false
                    break
                    ;;
                n|N)
                    PAUSED=false
                    if [[ "$MODE" == "slideshow" ]]; then
                        CURRENT_IDX=$(( (CURRENT_IDX + 1) % TOTAL ))
                    fi
                    NEXT_NOW=true
                    break
                    ;;
                j|J)
                    DELAY=$(( DELAY - 1 ))
                    [[ $DELAY -lt 1 ]] && DELAY=1
                    save_delay
                    [[ "$MODE" == "slideshow" ]] && show_image_slideshow $(( (CURRENT_IDX - 1 + TOTAL) % TOTAL )) || true
                    # stay paused, keep looping
                    ;;
                k|K)
                    DELAY=$(( DELAY + 1 ))
                    save_delay
                    [[ "$MODE" == "slideshow" ]] && show_image_slideshow $(( (CURRENT_IDX - 1 + TOTAL) % TOTAL )) || true
                    # stay paused, keep looping
                    ;;
                l|L)
                    WIDTH_PERCENT=$(( WIDTH_PERCENT + 5 ))
                    save_width
                    [[ "$MODE" == "slideshow" ]] && show_image_slideshow $(( (CURRENT_IDX - 1 + TOTAL) % TOTAL )) || true
                    # stay paused, keep looping
                    ;;
                u|U)
                    WIDTH_PERCENT=$(( WIDTH_PERCENT - 5 ))
                    [[ $WIDTH_PERCENT -lt 10 ]] && WIDTH_PERCENT=10
                    save_width
                    [[ "$MODE" == "slideshow" ]] && show_image_slideshow $(( (CURRENT_IDX - 1 + TOTAL) % TOTAL )) || true
                    # stay paused, keep looping
                    ;;
                r|R)
                    ROTATE=$( [[ $ROTATE == true ]] && echo false || echo true )
                    rm -f "$TEMP_DIR"/rotated_*
                    sed -i "4s/.*/$ROTATE/" "$SETTINGS_FILE" 2>/dev/null || true
                    [[ "$MODE" == "slideshow" ]] && show_image_slideshow $(( (CURRENT_IDX - 1 + TOTAL) % TOTAL )) || true
                    # stay paused, keep looping
                    ;;
                m|M)
                    [[ "$MODE" == "slideshow" ]] && MODE="feed" || MODE="slideshow"
                    sed -i "3s/.*/$MODE/" "$SETTINGS_FILE" 2>/dev/null || true
                    PAUSED=false
                    break
                    ;;
                i|I)
                    [[ "$MODE" == "slideshow" ]] && show_info || true
                    # stay paused, keep looping
                    ;;
                h|H)
                    VERBOSE=$( [[ $VERBOSE == true ]] && echo false || echo true )
                    [[ "$MODE" == "slideshow" ]] && show_image_slideshow $(( (CURRENT_IDX - 1 + TOTAL) % TOTAL )) || true
                    # stay paused, keep looping
                    ;;
                q|Q)
                    cleanup
                    ;;
            esac
        done
    fi

    # Reshuffle when we wrap around in slideshow mode
    if [[ "$MODE" == "slideshow" ]] && [[ $CURRENT_IDX -eq 0 ]]; then
        MEDIA=($(shuf -e "${MEDIA[@]}"))
    fi
done

#!/usr/bin/env bash
# Terminal media viewer using Kitty's icat kitten — slideshow + feed modes
# Usage: image-slideshow.sh [directory] [delay_seconds]
# Controls: n=next | p=prev | b=pause | r=rotate | m=mode | j/k=±1s delay | u=upscale | i=info | h=hide | q=quit
# Requires: kitty (icat kitten built-in), ffmpeg for unsupported video formats, imagemagick for rotation

set -eo pipefail

SETTINGS_FILE="$HOME/.icat_slideshow_settings"
TEMP_DIR="/tmp/icat_slideshow-$$"
CONVERSION_QUEUE="$TEMP_DIR/queue"

# ---- must be inside kitty ----
if [[ -z "$KITTY_WINDOW_ID" ]] && [[ "${TERM:-}" != *kitty* ]]; then
    echo "Error: This slideshow requires the Kitty terminal (kitty +kitten icat)"
    exit 1
fi

# ---- dependency check ----
if ! command -v kitty &>/dev/null; then
    echo "Error: 'kitty' not found in PATH"
    exit 1
fi

HAS_FFMPEG=false
if command -v ffmpeg &>/dev/null; then HAS_FFMPEG=true; fi

HAS_CONVERT=false
if command -v convert &>/dev/null; then HAS_CONVERT=true; fi

# ---- load or prompt for settings ----
if [[ -n "$1" ]]; then
    IMAGE_DIR="${1/#\~/$HOME}"
    DELAY="${2:-10}"
    MODE="slideshow"
    ROTATE=false
    UPSCALE=false
else
    if [[ -f "$SETTINGS_FILE" ]]; then
        LAST_DIR=$(sed -n '1p' "$SETTINGS_FILE")
        LAST_DELAY=$(sed -n '2p' "$SETTINGS_FILE")
        LAST_MODE=$(sed -n '3p' "$SETTINGS_FILE")
        LAST_ROTATE=$(sed -n '4p' "$SETTINGS_FILE")
        LAST_UPSCALE=$(sed -n '5p' "$SETTINGS_FILE")

        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "🎬 Kitty icat Media Viewer"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "Last settings:"
        echo "  Directory : $LAST_DIR"
        echo "  Delay     : ${LAST_DELAY}s"
        echo "  Mode      : $LAST_MODE"
        echo "  Rotation  : $LAST_ROTATE"
        echo "  Upscale   : $LAST_UPSCALE"
        echo ""
        read -e -p "Press Enter to use last settings, or type a new directory path: " USER_INPUT

        if [[ -z "$USER_INPUT" ]]; then
            IMAGE_DIR="$LAST_DIR"
            DELAY="$LAST_DELAY"
            MODE="$LAST_MODE"
            ROTATE="$LAST_ROTATE"
            UPSCALE="${LAST_UPSCALE:-false}"
            echo "✓ Using saved settings"
            echo ""
            read -p "Delay in seconds (default ${DELAY}): " DELAY_INPUT
            [[ -n "$DELAY_INPUT" ]] && DELAY="$DELAY_INPUT"
        else
            IMAGE_DIR="${USER_INPUT/#\~/$HOME}"
            read -p "Delay in seconds (default ${LAST_DELAY}): " DELAY_INPUT
            DELAY="${DELAY_INPUT:-$LAST_DELAY}"
            MODE="${LAST_MODE:-slideshow}"
            ROTATE="${LAST_ROTATE:-false}"
            UPSCALE="${LAST_UPSCALE:-false}"
        fi
    else
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "🎬 Kitty icat Media Viewer — First Run Setup"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        read -e -p "Directory path with images/videos: " DIR_INPUT
        IMAGE_DIR="${DIR_INPUT/#\~/$HOME}"
        read -p "Delay in seconds (default 10): " DELAY_INPUT
        DELAY="${DELAY_INPUT:-10}"
        MODE="slideshow"
        ROTATE=false
        UPSCALE=false
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
    echo "$UPSCALE"
} > "$SETTINGS_FILE"

# ---- gather media ----
shopt -s nullglob
IMAGES=("$IMAGE_DIR"/*.{jpg,jpeg,png,gif,JPG,JPEG,PNG,GIF,webp,WEBP,bmp,BMP})
ICAT_VIDEOS=("$IMAGE_DIR"/*.{mp4,MP4,mov,MOV,webm,WEBM,mkv,MKV,avi,AVI,m4v,M4V})
CONVERT_VIDEOS=("$IMAGE_DIR"/*.{flv,FLV,wmv,WMV,vob,VOB,ogv,OGV})

MEDIA=("${IMAGES[@]}" "${ICAT_VIDEOS[@]}")

if [[ ${#MEDIA[@]} -eq 0 ]] && [[ ${#CONVERT_VIDEOS[@]} -eq 0 ]]; then
    echo "Error: No media found in $IMAGE_DIR"
    rm -rf "$TEMP_DIR"; exit 1
fi

if [[ ${#MEDIA[@]} -eq 0 ]] && [[ ${#CONVERT_VIDEOS[@]} -gt 0 ]]; then
    if [[ $HAS_FFMPEG == false ]]; then
        echo "Error: Only unsupported video formats found but ffmpeg is not available."
        rm -rf "$TEMP_DIR"; exit 1
    fi
    echo "🎬 Converting first video to mp4..."
    first_video="${CONVERT_VIDEOS[0]}"
    output="$TEMP_DIR/$(basename "$first_video").mp4"
    if ffmpeg -i "$first_video" -c:v libx264 -preset fast -crf 23 -c:a aac "$output" -y &>/dev/null; then
        MEDIA=("$output")
        CONVERT_VIDEOS=("${CONVERT_VIDEOS[@]:1}")
    else
        echo "Error: Failed to convert video"
        rm -rf "$TEMP_DIR"; exit 1
    fi
fi

MEDIA=($(shuf -e "${MEDIA[@]}"))
TOTAL=${#MEDIA[@]}

# ---- background converter for unsupported video formats ----
convert_videos_background() {
    for video in "${CONVERT_VIDEOS[@]}"; do
        output="$TEMP_DIR/$(basename "$video").mp4"
        if ffmpeg -i "$video" -c:v libx264 -preset fast -crf 23 -c:a aac "$output" -y &>/dev/null; then
            echo "$output" >> "$CONVERSION_QUEUE"
        fi
    done
}

if [[ ${#CONVERT_VIDEOS[@]} -gt 0 ]] && [[ $HAS_FFMPEG == true ]]; then
    convert_videos_background &
    CONVERTER_PID=$!
fi

# ---- check for newly converted videos, insert at random position ----
check_new_videos() {
    if [[ -f "$CONVERSION_QUEUE" ]]; then
        while IFS= read -r new_video; do
            if [[ -f "$new_video" ]] && [[ ! " ${MEDIA[@]} " =~ " ${new_video} " ]]; then
                local random_pos=$((RANDOM % (${#MEDIA[@]} + 1)))
                MEDIA=("${MEDIA[@]:0:random_pos}" "$new_video" "${MEDIA[@]:random_pos}")
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

# ---- save upscale to settings ----
save_upscale() {
    sed -i "5s/.*/$UPSCALE/" "$SETTINGS_FILE" 2>/dev/null || true
}

# ---- save delay to settings ----
save_delay() {
    sed -i "2s/.*/$DELAY/" "$SETTINGS_FILE" 2>/dev/null || true
}

# ---- clear kitty graphics from screen ----
clear_icat() {
    kitty +kitten icat --clear --stdin=no 2>/dev/null || true
    printf '\033[H\033[2J\033[3J'
}

# ---- display image/video using icat ----
run_icat() {
    local file="$1"
    local icat_opts="--stdin=no"
    [[ $UPSCALE == true ]] && icat_opts="$icat_opts --scale-up"
    kitty +kitten icat $icat_opts "$file"
}

# ---- SLIDESHOW mode: clear screen, show one image at a time ----
show_image_slideshow() {
    local idx=$1
    [[ $TOTAL -eq 0 ]] && return 1

    local file="${MEDIA[$idx]}"
    local attempts=0

    while [[ $attempts -lt 3 ]]; do
        if [[ -f "$file" ]]; then
            clear_icat
            if [[ $VERBOSE == true ]]; then
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo "📸 [$(( idx + 1 ))/$TOTAL] $(basename "$file")"
                [[ $PAUSED == true ]] && echo "⏸️  PAUSED" || echo "▶️  PLAYING  ⏱️  ${DELAY}s"
                echo "🔍 UPSCALE: $UPSCALE | 🔄 ROTATE: $ROTATE | 📺 MODE: $MODE"
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo ""
            fi
            local display_file
            display_file=$(prepare_file "$file")
            if run_icat "$display_file"; then
                if [[ $VERBOSE == true ]]; then
                    echo ""
                    echo "Controls: [n]ext | [p]rev | [b]pause | [j/k]±1s | [u]pscale | [r]otate | [m]ode | [i]nfo | [h]ide | [q]uit"
                fi
                return 0
            else
                echo "⚠️  icat failed (attempt $((attempts+1))/3)"
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
        echo "📸 [$(( CURRENT_IDX + 1 ))/$TOTAL] $(basename "$file")"
        echo "🔍 UPSCALE: $UPSCALE | ⏱️  ${DELAY}s | 🔄 $ROTATE | 📺 $MODE"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
    fi

    local display_file
    display_file=$(prepare_file "$file")

    if ! run_icat "$display_file"; then
        return 1
    fi

    if [[ $VERBOSE == true ]]; then
        echo ""
        echo "Controls: [n]ext | [p]rev | [b]pause | [j/k]±1s | [u]pscale | [r]otate | [m]ode | [h]ide | [q]uit"
        echo ""
    fi
    return 0
}

# ---- info screen ----
show_info() {
    local file="${MEDIA[$CURRENT_IDX]}"
    clear_icat
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📋 MEDIA INFO"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "File : $(basename "$file")"
    echo "Path : $file"
    echo "Size : $(du -h "$file" | cut -f1)"
    if command -v identify &>/dev/null; then
        echo ""
        identify -verbose "$file" 2>/dev/null | grep -E "^  (Geometry|Format|Filesize|Colorspace|Depth):" || true
    elif command -v ffprobe &>/dev/null; then
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
    clear_icat
    [[ -n "${CONVERTER_PID:-}" ]] && kill "$CONVERTER_PID" 2>/dev/null || true
    rm -rf "$TEMP_DIR"
    exit
}

trap cleanup EXIT INT TERM
stty -echo -icanon time 0 min 0

CURRENT_IDX=0
PAUSED=false
NEXT_NOW=false
VERBOSE=true

echo ""
echo "🎬 Starting in $MODE mode with ${DELAY}s delay | upscale: $UPSCALE"
echo "Controls: [n]ext | [p]rev | [b]pause | [j/k]±1s | [u]pscale | [r]otate | [m]ode | [i]nfo | [h]ide | [q]uit"
echo ""

# ---- main loop ----
while true; do
    check_new_videos

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
                u|U)
                    UPSCALE=$( [[ $UPSCALE == true ]] && echo false || echo true )
                    save_upscale
                    [[ "$MODE" == "slideshow" ]] && show_image_slideshow $(( (CURRENT_IDX - 1 + TOTAL) % TOTAL )) && i=0 || true
                    ;;
                r|R)
                    ROTATE=$( [[ $ROTATE == true ]] && echo false || echo true )
                    rm -f "$TEMP_DIR"/rotated_*
                    sed -i "4s/.*/$ROTATE/" "$SETTINGS_FILE" 2>/dev/null || true
                    [[ "$MODE" == "slideshow" ]] && break || true
                    ;;
                m|M)
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

        # Auto-advance after delay (slideshow only — feed advances in main loop)
        if [[ "$MODE" == "slideshow" ]] && [[ $i -eq $((DELAY*10)) ]]; then
            CURRENT_IDX=$(( (CURRENT_IDX + 1) % TOTAL ))
        fi
    else
        # ---- paused input ----
        while true; do
            read -r -t 0.1 -n 1 key || true
            [[ -z "$key" ]] && continue
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
                    ;;
                k|K)
                    DELAY=$(( DELAY + 1 ))
                    save_delay
                    [[ "$MODE" == "slideshow" ]] && show_image_slideshow $(( (CURRENT_IDX - 1 + TOTAL) % TOTAL )) || true
                    ;;
                u|U)
                    UPSCALE=$( [[ $UPSCALE == true ]] && echo false || echo true )
                    save_upscale
                    [[ "$MODE" == "slideshow" ]] && show_image_slideshow $(( (CURRENT_IDX - 1 + TOTAL) % TOTAL )) || true
                    ;;
                r|R)
                    ROTATE=$( [[ $ROTATE == true ]] && echo false || echo true )
                    rm -f "$TEMP_DIR"/rotated_*
                    sed -i "4s/.*/$ROTATE/" "$SETTINGS_FILE" 2>/dev/null || true
                    [[ "$MODE" == "slideshow" ]] && show_image_slideshow $(( (CURRENT_IDX - 1 + TOTAL) % TOTAL )) || true
                    ;;
                m|M)
                    [[ "$MODE" == "slideshow" ]] && MODE="feed" || MODE="slideshow"
                    sed -i "3s/.*/$MODE/" "$SETTINGS_FILE" 2>/dev/null || true
                    PAUSED=false
                    break
                    ;;
                i|I)
                    [[ "$MODE" == "slideshow" ]] && show_info || true
                    ;;
                h|H)
                    VERBOSE=$( [[ $VERBOSE == true ]] && echo false || echo true )
                    [[ "$MODE" == "slideshow" ]] && show_image_slideshow $(( (CURRENT_IDX - 1 + TOTAL) % TOTAL )) || true
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

#!/usr/bin/env bash
# Scrolling image feed with video support and dynamic controls
# Usage: scrolling-feed-catimg.sh [directory] [delay_seconds]

SETTINGS_FILE="$HOME/.terminal_slideshow_scroll_settings"
TEMP_DIR="/tmp/terminal_slideshow_scroll-$$"
CONVERSION_QUEUE="$TEMP_DIR/queue"
WIDTH_PERCENT=120

if ! command -v catimg &> /dev/null; then
    echo "Error: catimg not found. Install: yay -S catimg"
    exit 1
fi

HAS_FFMPEG=false
if command -v ffmpeg &> /dev/null; then
    HAS_FFMPEG=true
fi

if [[ -n "${1:-}" ]]; then
    IMAGE_DIR="${1/#\~/$HOME}"
    DELAY="${2:-10}"
else
    if [[ -f "$SETTINGS_FILE" ]]; then
        LAST_DIR=$(sed -n '1p' "$SETTINGS_FILE")
        LAST_DELAY=$(sed -n '2p' "$SETTINGS_FILE")

        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "🎬 Terminal Scrolling Feed"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "Last settings:"
        echo "  Directory: $LAST_DIR"
        echo "  Delay: ${LAST_DELAY}s"
        echo ""
        read -e -p "Press Enter to use last settings, or type new directory path: " USER_INPUT

        if [[ -z "$USER_INPUT" ]]; then
            IMAGE_DIR="$LAST_DIR"
            DELAY="$LAST_DELAY"
            echo "✓ Using saved settings"
        else
            USER_INPUT="${USER_INPUT/#\~/$HOME}"
            IMAGE_DIR="$USER_INPUT"
            read -p "Delay in seconds (default ${LAST_DELAY}): " DELAY_INPUT
            DELAY="${DELAY_INPUT:-$LAST_DELAY}"
        fi
    else
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "🎬 Terminal Scrolling Feed - First Time Setup"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        read -e -p "Directory path with images/videos: " DIR_INPUT
        IMAGE_DIR="${DIR_INPUT/#\~/$HOME}"
        read -p "Delay in seconds (default 10): " DELAY_INPUT
        DELAY="${DELAY_INPUT:-10}"
    fi
fi

if ! [[ "$DELAY" =~ ^[0-9]+$ ]]; then
    echo "Invalid delay, using 10"
    DELAY=10
fi

if [[ ! -d "$IMAGE_DIR" ]]; then
    echo "Error: Directory not found: $IMAGE_DIR"
    exit 1
fi

echo "$IMAGE_DIR" > "$SETTINGS_FILE"
echo "$DELAY" >> "$SETTINGS_FILE"

mkdir -p "$TEMP_DIR"
touch "$CONVERSION_QUEUE"

shopt -s nullglob
IMAGES=("$IMAGE_DIR"/*.{jpg,jpeg,png,gif,JPG,JPEG,PNG,GIF})
VIDEOS=("$IMAGE_DIR"/*.{mp4,mov,MP4,MOV})

if [[ ${#IMAGES[@]} -eq 0 ]] && [[ ${#VIDEOS[@]} -eq 0 ]]; then
    echo "Error: No media found in $IMAGE_DIR"
    rm -rf "$TEMP_DIR"
    exit 1
fi

if [[ ${#IMAGES[@]} -eq 0 ]] && [[ ${#VIDEOS[@]} -gt 0 ]]; then
    echo "🎬 Converting first video..."
    first_video="${VIDEOS[0]}"
    output="$TEMP_DIR/$(basename "$first_video").gif"
    if ffmpeg -i "$first_video" -vf "fps=30,scale=320:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" -c:v gif -f gif "$output" -y &>/dev/null; then
        IMAGES=("$output")
        VIDEOS=("${VIDEOS[@]:1}")
    else
        echo "Error: Failed to convert video"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
fi

if [[ ${#IMAGES[@]} -gt 0 ]]; then
    IMAGES=($(shuf -e "${IMAGES[@]}"))
    TOTAL=${#IMAGES[@]}
else
    TOTAL=0
fi

convert_videos_background() {
    for video in "${VIDEOS[@]}"; do
        output="$TEMP_DIR/$(basename "$video").gif"
        if ffmpeg -i "$video" -vf "fps=30,scale=320:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" -c:v gif -f gif "$output" -y &>/dev/null; then
            echo "$output" >> "$CONVERSION_QUEUE"
        fi
    done
}

if [[ ${#VIDEOS[@]} -gt 0 ]] && [[ $HAS_FFMPEG == true ]]; then
    convert_videos_background &
    CONVERTER_PID=$!
fi

check_new_videos() {
    if [[ -f "$CONVERSION_QUEUE" ]]; then
        while IFS= read -r new_gif; do
            if [[ -f "$new_gif" ]] && [[ ! " ${IMAGES[@]} " =~ " ${new_gif} " ]]; then
                random_pos=$((RANDOM % (${#IMAGES[@]} + 1)))
                IMAGES=("${IMAGES[@]:0:random_pos}" "$new_gif" "${IMAGES[@]:random_pos}")
                TOTAL=${#IMAGES[@]}
            fi
        done < "$CONVERSION_QUEUE"
        > "$CONVERSION_QUEUE"
    fi
}

echo ""
echo "🎬 Started with ${DELAY}s delay"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Controls: [n]ext | [p]rev | [space]pause | [j]-1s | [k]+1s | [l]+5% | [u]-5% | [q]uit"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

term_cols=$(tput cols)

show_image() {
    local img="$1"

    if [[ ! -f "$img" ]]; then
        return 1
    fi

    local img_width=$((term_cols * WIDTH_PERCENT / 100))

    if ! catimg -w "$img_width" "$img" 2>/dev/null; then
        return 1
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📸 $(basename "$img")"
    echo "🔍 WIDTH: ${WIDTH_PERCENT}% | ⏱️  Delay: ${DELAY}s"
    echo "[n]ext | [p]rev | [space]pause | [j]-1s | [k]+1s | [l]+5% | [u]-5% | [q]uit"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    return 0
}

cleanup() {
    stty sane
    clear
    [[ -n "${CONVERTER_PID:-}" ]] && kill "$CONVERTER_PID" 2>/dev/null || true
    rm -rf "$TEMP_DIR"
    rm -f "$SETTINGS_FILE"
    exit
}

trap cleanup EXIT INT TERM

CURRENT_IDX=0
if [[ ${#IMAGES[@]} -ge 1 ]]; then
    show_image "${IMAGES[0]}"
    CURRENT_IDX=1
fi

stty -echo -icanon time 0 min 0

PENDING_DELAY_CHANGE=0
PAUSED=false

while true; do
    check_new_videos

    if [[ $PENDING_DELAY_CHANGE -ne 0 ]]; then
        DELAY=$((DELAY + PENDING_DELAY_CHANGE))
        if [[ $DELAY -lt 1 ]]; then
            DELAY=1
        fi
        sed -i "2s/.*/$DELAY/" "$SETTINGS_FILE" 2>/dev/null || true
        PENDING_DELAY_CHANGE=0
    fi

    if [[ $TOTAL -gt 0 ]] && [[ ${NEXT_NOW:-false} == true || $PAUSED == false ]]; then
        attempts=0
        while [[ $attempts -lt 5 ]]; do
            if show_image "${IMAGES[$CURRENT_IDX]}"; then
                CURRENT_IDX=$(( (CURRENT_IDX + 1) % TOTAL ))
                break
            else
                CURRENT_IDX=$(( (CURRENT_IDX + 1) % TOTAL ))
                attempts=$((attempts + 1))
            fi
        done
    fi

    NEXT_NOW=false
    if [[ $PAUSED == false ]]; then
        for ((i=0; i<DELAY*10; i++)); do
            read -t 0.1 -n 1 key 2>/dev/null || true

            case "$key" in
                n|N) NEXT_NOW=true; break ;;
                p|P) show_image "${IMAGES[$((CURRENT_IDX - 1 + TOTAL)) % TOTAL]}"; i=0 ;;
                " ") show_image "${IMAGES[$((CURRENT_IDX - 1 + TOTAL)) % TOTAL]}"; i=0; PAUSED=true ;;
                j|J) PENDING_DELAY_CHANGE=$((PENDING_DELAY_CHANGE - 1)) ;;
                k|K) PENDING_DELAY_CHANGE=$((PENDING_DELAY_CHANGE + 1)) ;;
                l|L) WIDTH_PERCENT=$((WIDTH_PERCENT + 5)); show_image "${IMAGES[$((CURRENT_IDX - 1 + TOTAL)) % TOTAL]}"; i=0 ;;
                u|U) WIDTH_PERCENT=$((WIDTH_PERCENT - 5)); [[ $WIDTH_PERCENT -lt 10 ]] && WIDTH_PERCENT=10; show_image "${IMAGES[$((CURRENT_IDX - 1 + TOTAL)) % TOTAL]}"; i=0 ;;
                q|Q) cleanup ;;
            esac
        done
    else
        read -n 1 key
        case "$key" in
            n|N) PAUSED=false; NEXT_NOW=true ;;
            p|P) show_image "${IMAGES[$((CURRENT_IDX - 1 + TOTAL)) % TOTAL]}" ;;
            " ") PAUSED=false ;;
            j|J) PENDING_DELAY_CHANGE=$((PENDING_DELAY_CHANGE - 1)) ;;
            k|K) PENDING_DELAY_CHANGE=$((PENDING_DELAY_CHANGE + 1)) ;;
            l|L) WIDTH_PERCENT=$((WIDTH_PERCENT + 5)); show_image "${IMAGES[$((CURRENT_IDX - 1 + TOTAL)) % TOTAL]}" ;;
            u|U) WIDTH_PERCENT=$((WIDTH_PERCENT - 5)); [[ $WIDTH_PERCENT -lt 10 ]] && WIDTH_PERCENT=10; show_image "${IMAGES[$((CURRENT_IDX - 1 + TOTAL)) % TOTAL]}" ;;
            q|Q) cleanup ;;
        esac
    fi
done

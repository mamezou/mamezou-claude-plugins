#!/usr/bin/env bash
# draw.io ファイルを PNG に書き出し、ページサイズの白背景へ配置して寸法を検証する。
# 使い方: export-png.sh <input.drawio> [output.png]
# 環境変数: DIAGRAM_FONT (既定 IPAPGothic), PAGE_WIDTH/PAGE_HEIGHT (1400/900), LEFT_MARGIN/TOP_MARGIN (40/18)
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "Usage: $0 <input.drawio> [output.png]" >&2
  exit 2
fi

input_path=$1
output_path=${2:-${input_path%.drawio}.png}
page_width=${PAGE_WIDTH:-1400}
page_height=${PAGE_HEIGHT:-900}
left_margin=${LEFT_MARGIN:-40}
top_margin=${TOP_MARGIN:-18}
diagram_font=${DIAGRAM_FONT:-IPAPGothic}

for cmd in drawio fc-match ffmpeg ffprobe; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "$cmd was not found." >&2
    exit 1
  fi
done

if [ ! -f "$input_path" ]; then
  echo "Input file was not found: $input_path" >&2
  exit 1
fi

resolved_font=$(fc-match -f '%{family}' "$diagram_font")
case "$resolved_font" in
  *"$diagram_font"*) ;;
  *)
    echo "$diagram_font was not found. Resolved font: $resolved_font" >&2
    exit 1
    ;;
esac

missing_font_styles=$(grep 'style="' "$input_path" | grep -Evc "fontFamily=${diagram_font}[;\"]" || true)
if [ "$missing_font_styles" -ne 0 ]; then
  echo "Found $missing_font_styles styles without fontFamily=$diagram_font in $input_path." >&2
  exit 1
fi

drawio_command=(drawio)
if [ -z "${DISPLAY:-}" ]; then
  if ! command -v xvfb-run >/dev/null 2>&1; then
    echo "xvfb-run is required when DISPLAY is not available." >&2
    exit 1
  fi
  drawio_command=(xvfb-run -a drawio --no-sandbox)
fi

temporary_dir=$(mktemp -d)
trap 'rm -rf "$temporary_dir"' EXIT
cropped_png="$temporary_dir/cropped.png"
normalized_png="$temporary_dir/normalized.png"

"${drawio_command[@]}" --export --format png --scale 1 --border 0 --output "$cropped_png" "$input_path"

dimensions=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "$cropped_png")
cropped_width=${dimensions%x*}
cropped_height=${dimensions#*x}

if [ "$cropped_width" -eq "$page_width" ] && [ "$cropped_height" -eq "$page_height" ]; then
  cp "$cropped_png" "$normalized_png"
elif [ $((cropped_width + left_margin)) -le "$page_width" ] && [ $((cropped_height + top_margin)) -le "$page_height" ]; then
  ffmpeg -y -v error -i "$cropped_png" \
    -vf "pad=${page_width}:${page_height}:${left_margin}:${top_margin}:color=white" \
    -frames:v 1 "$normalized_png"
else
  echo "Exported content ${cropped_width}x${cropped_height} does not fit the ${page_width}x${page_height} canvas." >&2
  exit 1
fi

mv "$normalized_png" "$output_path"

output_dimensions=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "$output_path")
if [ "$output_dimensions" != "${page_width}x${page_height}" ]; then
  echo "Unexpected PNG dimensions: $output_dimensions" >&2
  exit 1
fi
echo "$output_path (${output_dimensions})"

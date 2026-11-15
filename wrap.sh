#!/bin/bash
# base64-wrap every fetched asset into a .b64.js file and delete the original.
# .unityweb files are gzip-compressed -> decompressed first.
set -e

targets=()
targets+=("Build/"*)
targets+=("StreamingAssets/aa/"WebGL.zip.part*)

for f in StreamingAssets/aa/*; do
  case "$(basename "$f")" in
    catalog.bin|catalog.hash|settings.json) targets+=("$f");;
  esac
done

echo "Files to wrap: ${#targets[@]}"

for f in "${targets[@]}"; do
  [ -f "$f" ] || continue
  case "$f" in *.b64.js) echo "SKIP $f"; continue;; esac
  # skip anything that isn't one of our targets (e.g. index.html, jszip.js)
  case "$f" in
    Build/w-pt.loader.js|Build/*.unityweb) ;;
    StreamingAssets/aa/WebGL.zip.part*) ;;
    StreamingAssets/aa/catalog.bin|StreamingAssets/aa/catalog.hash|StreamingAssets/aa/settings.json) ;;
    *) echo "SKIP $f"; continue;;
  esac

  rel="${f#./}"
  echo "Wrapping $rel ..."

  if [[ "$rel" == *.unityweb ]]; then
    if gzip -t "$f" 2>/dev/null; then
      gunzip -c "$f" > "$f.work"
      echo "  (gzip decompressed)"
    elif head -c 2 "$f" | xxd -p | grep -q '^1f8b'; then
      gunzip -c "$f" > "$f.work"
      echo "  (gzip decompressed)"
    else
      # likely brotli (raw bytes often start 0x1b/0x8b or similar)
      if command -v brotli >/dev/null 2>&1 && brotli -d "$f" -o "$f.work" 2>/dev/null; then
        echo "  (brotli decompressed)"
      else
        echo "  WARNING: could not decompress $rel - wrapping raw"
        cp "$f" "$f.work"
      fi
    fi
    bytes="$f.work"
  else
    bytes="$f"
  fi

  b64=$(base64 -w 0 "$bytes")

  echo "window.__B64=window.__B64||{};window.__B64[\"$rel\"]=\"$b64\";" > "$f.b64.js"
  echo "  -> $(du -h "$f.b64.js" | cut -f1) $f.b64.js"

  rm -f "$f" "$f.work"
done

echo "Done."

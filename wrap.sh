#!/bin/bash
# base64-wrap every fetched asset into one or more .b64.js chunk files and
# delete the original. Files are split so no chunk file exceeds ~14 MB of
# base64 (jsdelivr's limit for gh files is 20 MB).
# .unityweb files are gzip-compressed -> decompressed first.
#
# Chunk files are named:
#   <rel>.b64.js          -> chunk 0
#   <rel>.b64.<n>.js      -> chunk n (n = 1, 2, ...)
# Each chunk registers into window.__B64C[rel][n].
# Run from the root of your fork (or via .github/workflows/wrap.yml).
set -e

CHUNK_B64_BYTES=14680064   # 14 MB of base64 per chunk file (safe under 20 MB)
CHUNK_BIN=$(( CHUNK_B64_BYTES / 4 * 3 ))  # matching raw byte count

root="$(pwd)"
echo "Repo root: $root"

if [ ! -d "StreamingAssets/aa" ]; then
  echo "ERROR: run from the repo root (StreamingAssets/aa/ not found)" >&2
  exit 1
fi

targets=()
targets+=("Build/"*)
targets+=("StreamingAssets/aa/"WebGL.zip.part*)
targets+=("StreamingAssets/aa/"WebGL.zip.part*.js 2>/dev/null || true)
for f in StreamingAssets/aa/*; do
  case "$(basename "$f")" in
    catalog.bin|catalog.hash|settings.json|catalog.bin.js|catalog.hash.js|settings.json.js) targets+=("$f");;
  esac
done

echo "Files to wrap: ${#targets[@]}"

for f in "${targets[@]}"; do
  [ -f "$f" ] || continue
  case "$f" in *.b64*.js|*.b64.*.js) echo "SKIP $f"; continue;; esac
  case "$f" in
    Build/w-pt.loader.js|Build/*.unityweb|Build/*.unityweb.js) ;;
    StreamingAssets/aa/WebGL.zip.part*) ;;
    StreamingAssets/aa/catalog.bin|StreamingAssets/aa/catalog.hash|StreamingAssets/aa/settings.json) ;;
    StreamingAssets/aa/catalog.bin.js|StreamingAssets/aa/catalog.hash.js|StreamingAssets/aa/settings.json.js) ;;
    *) echo "SKIP $f"; continue;;
  esac

  rel="${f#./}"
  # The repo went through a rename pass: raw binaries now carry a .js
  # extension (WebGL.zip.part1.js, w-pt.data.unityweb.js, catalog.bin.js...).
  # Strip the trailing .js so the registry key is the ORIGINAL path the
  # engine asks for.
  case "$rel" in
    *.unityweb.js|*.part[0-9].js|*.part[0-9][0-9].js|catalog.bin.js|catalog.hash.js|settings.json.js)
      rel="${rel%.js}" ;;
  esac
  echo "Wrapping $rel ..."

  work="$f.raw"
  if [[ "$rel" == *.unityweb ]]; then
    # covers both w-pt.data.unityweb and renamed w-pt.data.unityweb.js
    if head -c 2 "$f" | od -An -tx1 | grep -q '1f 8b'; then
      gunzip -c "$f" > "$work"
      echo "  (gzip decompressed)"
    elif command -v brotli >/dev/null 2>&1 && brotli -d "$f" -o "$work" 2>/dev/null; then
      echo "  (brotli decompressed)"
    else
      echo "  (no compression detected - wrapping raw)"
      cp "$f" "$work"
    fi
  else
    cp "$f" "$work"
  fi

  size=$(stat -c%s "$work")
  chunks=$(( (size + CHUNK_BIN - 1) / CHUNK_BIN ))
  echo "  raw size: $size bytes -> $chunks chunk file(s)"

  n=0
  off=0
  while [ "$off" -lt "$size" ]; do
    this=$(( CHUNK_BIN )); if [ $((off + this)) -gt "$size" ]; then this=$((size - off)); fi
    tail -c +"$((off + 1))" "$work" | head -c "$this" | base64 -w 0 > "$work.b64"
    b64=$(cat "$work.b64")
    if [ "$n" -eq 0 ]; then
      out="$f.b64.js"
    else
      out="$f.b64.$n.js"
    fi
    echo "window.__B64C=window.__B64C||{};window.__B64C[\"$rel\"]=window.__B64C[\"$rel\"]||[];window.__B64C[\"$rel\"][$n]=\"$b64\";" > "$out"
    echo "  chunk $n -> $(du -h "$out" | cut -f1) $out"
    rm -f "$work.b64"
    off=$((off + this))
    n=$((n + 1))
  done

  rm -f "$work" "$f"
done

echo "Done."

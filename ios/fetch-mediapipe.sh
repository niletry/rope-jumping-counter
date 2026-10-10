#!/bin/zsh
# Downloads the MediaPipe Tasks iOS frameworks (1.0.0) into ios/Frameworks/.
# They total ~1.3 GB unpacked, far beyond what git can hold, so they are git-ignored and fetched
# on demand. Files come from dl.google.com, the same host CocoaPods would use; the big archive is
# pulled as parallel, resumable range chunks because that host is slow and flaky from some networks.
set -e
cd "$(dirname "$0")"
VISION_URL=https://dl.google.com/cpdc/20260727-225049/MediaPipeTasksVision-1.0.0.tar.gz
COMMON_URL=https://dl.google.com/cpdc/20260727-225047/MediaPipeTasksCommon-1.0.0.tar.gz
TMP=${TMPDIR:-/tmp}/mediapipe-ios-1.0.0
mkdir -p "$TMP/chunks" Frameworks

if [ -d Frameworks/MediaPipeTasksVision.xcframework ] && [ -d Frameworks/MediaPipeTasksCommon.xcframework ] && [ -d Frameworks/graph_libraries ]; then
  echo "MediaPipe frameworks already present."; exit 0
fi

fetch_chunked() {  # url out
  local url=$1 out=$2
  local total=$(curl -sIL -m 30 "$url" | awk 'tolower($1)=="content-length:"{gsub("\r","",$2); n=$2} END{print n}')
  [ -n "$total" ] || { echo "cannot read size of $url"; exit 1; }
  local n=12 ch=$(( (total + 11) / 12 ))
  for i in $(seq 0 $((n-1))); do
    (
      local start=$((i*ch)) end=$(( (i+1)*ch - 1 )); [ $end -ge $total ] && end=$((total-1))
      local f=$TMP/chunks/$(basename $out).$i
      for try in $(seq 1 60); do
        local have=0; [ -f $f ] && have=$(stat -f %z $f)
        [ $have -ge $((end-start+1)) ] && break
        curl -sS -L -r $((start+have))-$end --speed-limit 500 --speed-time 60 "$url" >> $f 2>/dev/null || true
        sleep 3
      done
    ) &
  done
  wait
  cat $TMP/chunks/$(basename $out).{0..11} > "$out"
  [ "$(stat -f %z "$out")" = "$total" ] || { echo "size mismatch for $out"; exit 1; }
}

echo "Downloading MediaPipeTasksVision..."
curl -sS -L --retry 5 -o "$TMP/vision.tar.gz" "$VISION_URL"
echo "Downloading MediaPipeTasksCommon (368 MB, chunked)..."
fetch_chunked "$COMMON_URL" "$TMP/common.tar.gz"

tar -xzf "$TMP/vision.tar.gz" -C "$TMP"
tar -xzf "$TMP/common.tar.gz" -C "$TMP"
rm -rf Frameworks/MediaPipeTasksVision.xcframework Frameworks/MediaPipeTasksCommon.xcframework Frameworks/graph_libraries
mv "$TMP/frameworks/MediaPipeTasksVision.xcframework" "$TMP/frameworks/MediaPipeTasksCommon.xcframework" "$TMP/frameworks/graph_libraries" Frameworks/
rm -rf "$TMP"
echo "Done: $(du -sh Frameworks | cut -f1) in ios/Frameworks"

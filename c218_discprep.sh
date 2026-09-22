#!/bin/bash
cd "$HOME/Downloads/xenolift" || exit 1
# c218 DISC PREP (Jos manual order: "I need a bin and cue file in xenolift
# for the duckstation to play") - locates the disc substrate on this Mac,
# VERIFIES it by the PS1 license strings (any genuine PS1 image carries
# "Sony Computer Entertainment"/"PLAYSTATION" text in its first sectors),
# and stages xenogears.bin + xenogears.cue in xenolift ready to open.
# FAIL EXPLICIT at every step. The runtime tree is NOT modified.

echo "===FIND218=== disc-dump search (whole Mac: image extensions + all big files, cue sheets)"
echo "--- standard image files >50MB:"
find "$HOME" -maxdepth 5 -type f \( -iname "*.bin" -o -iname "*.iso" -o -iname "*.chd" -o -iname "*.img" -o -iname "*.mdf" \) -size +50M 2>/dev/null | head -24
echo "--- ALL files >100MB in the usual places (extension-agnostic):"
find "$HOME/Downloads" "$HOME/Documents" "$HOME/Desktop" -maxdepth 4 -type f -size +100M 2>/dev/null | head -20
echo "--- cue sheets found (any size):"
find "$HOME" -maxdepth 5 -type f -iname "*.cue" 2>/dev/null | head -12
echo "--- the runtime own sector source (receipt lines from the source code):"
grep -n "fopen\|\.bin\|\.cue\|\.chd\|\.iso\|disc_image\|DISC" runtime/runtime.c 2>/dev/null | head -16

echo "===PICK218=== license-verify the candidates (first 48KB of each)"
BEST=""
while IFS= read -r C; do
  LIC=$(head -c 49152 "$C" 2>/dev/null | strings | grep -ci "playstation\|sony computer")
  MOD=$(( $(wc -c < "$C" 2>/dev/null || echo 1) % 2352 ))
  echo "candidate: $C  license_hits=$LIC  mod2352=$MOD  size=$(wc -c < "$C" 2>/dev/null)"
  if [ "$LIC" -gt 0 ] && [ -z "$BEST" ]; then BEST="$C"; fi
done < <(find "$HOME" -maxdepth 5 -type f \( -iname "*.bin" -o -iname "*.iso" -o -iname "*.chd" -o -iname "*.img" -o -iname "*.mdf" \) -size +50M 2>/dev/null; find "$HOME/Downloads" "$HOME/Documents" "$HOME/Desktop" -maxdepth 4 -type f -size +100M 2>/dev/null)
echo "BEST=$BEST"

echo "===STAGE218=== stage the bin + cue in xenolift (FAIL EXPLICIT)"
if [ -z "$BEST" ]; then
  echo "NO-DISC-DUMP-FOUND: no PS1-licensed image anywhere on this Mac."
  echo "The runtime serves sectors from the source lines printed above - send me the FIND218 + PICK218 output and we either build a disc from the substrate or you drop your own dump into Downloads and rerun this script."
  exit 0
fi
if [ "$BEST" = "$PWD/xenogears.bin" ]; then
  echo "already staged in place"
fi
case "$BEST" in
  *.chd)
    if [ "$BEST" != "$PWD/xenogears.chd" ]; then cp -p "$BEST" ./xenogears.chd || { echo "STAGE-FAILED: chd copy"; exit 0; }; fi
    echo "STAGED: ./xenogears.chd - DuckStation opens .chd directly (File > Open Disc Image)"
    ;;
  *)
    if [ "$BEST" != "$PWD/xenogears.bin" ] && [ ! -f ./xenogears.bin ]; then
      cp -p "$BEST" ./xenogears.bin || { echo "STAGE-FAILED: bin copy"; exit 0; }
    fi
    if [ ! -f ./xenogears.bin ]; then echo "STAGE-FAILED: xenogears.bin not present"; exit 0; fi
    SZ=$(wc -c < ./xenogears.bin)
    if [ $((SZ % 2352)) -eq 0 ]; then
      printf 'FILE "xenogears.bin" BINARY\n  TRACK 01 MODE2/2352\n    INDEX 01 00:00:00\n' > xenogears.cue
    else
      cp -p ./xenogears.bin ./xenogears.iso
      printf 'FILE "xenogears.bin" BINARY\n  TRACK 01 MODE1/2048\n    INDEX 01 00:00:00\n' > xenogears.cue
    fi
    echo "STAGED: ./xenogears.bin ($SZ bytes) + ./xenogears.cue"
    cat xenogears.cue
    echo "--- identity + license receipts:"
    shasum -a 256 xenogears.bin | cut -c1-32
    head -c 32768 xenogears.bin | strings | grep -i "playstation\|licensed" | head -3
    echo "OPEN IN DUCKSTATION: File > Open Disc Image > xenogears.cue (or drag it onto the DuckStation window). If the image was 2048-cooked, xenogears.iso also opens directly."
    ;;
esac
echo "===END218=== done - nothing in the runtime tree was modified"

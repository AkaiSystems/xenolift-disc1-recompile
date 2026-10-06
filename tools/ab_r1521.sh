#!/bin/bash
# A/B: baseline (R1520 camera) vs R1521, 6 x 300s each, serialized.
W="$HOME/Library/Application Support/Claude/scratch-workspaces/05c9a5ff-4ec7-46a7-9d64-94980f630f59/340644c1-6cba-4ae2-9712-203d67460a60/scratch-2026-09-22-74dd89"
cd ~/Downloads/xenolift || exit 1
rm -f "$W/trials/ab.done"
cp "$W/trials/runtime_r1520_baseline.c" runtime/runtime.c
bash "$W/tools/boot_protocol.sh" "$W/trials/A300" 6 300
cp "$W/trials/runtime_r1521.c" runtime/runtime.c
bash "$W/tools/boot_protocol.sh" "$W/trials/B300" 6 300
echo "ABDONE $(date +%H:%M:%S)" > "$W/trials/ab.done"

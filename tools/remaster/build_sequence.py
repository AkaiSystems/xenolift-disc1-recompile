#!/usr/bin/env python3
"""Re-time the Square Enix opening: frames 0-41 (logo reveal + hold), the logo's own fade-out on black, a 1 s black pause,
then frames 42+ (star -> flash -> tunnel -> Xenogears logo) - the Xenogears part starts later by the fade + pause.
usage: build_sequence.py <se_dir> <timing.json> <out_dir> <out_timing.json> [fade_frames=12] [fade_refreshes_each=4] [pause_refreshes=60]"""
import glob, json, os, shutil, sys
se, tj, out, otj = sys.argv[1:5]
fadeN = int(sys.argv[5]) if len(sys.argv) > 5 else 12; fdur = int(sys.argv[6]) if len(sys.argv) > 6 else 4
pause = int(sys.argv[7]) if len(sys.argv) > 7 else 60; SPLIT = 42
t = json.load(open(tj)); d = t['durations']; os.makedirs(out, exist_ok=True)
for f in glob.glob(os.path.join(out, 's*.jpg')): os.remove(f)
seq = [(os.path.join(se, f'f{i:04d}.jpg'), d[i]) for i in range(SPLIT)]
seq += [(os.path.join(se, f'fade_{k:02d}.jpg'), fdur) for k in range(1, fadeN + 1)]
seq += [(os.path.join(se, f'fade_{fadeN:02d}.jpg'), pause)]          # last fade frame is black: hold it as the pause
seq += [(os.path.join(se, f'f{i:04d}.jpg'), d[i]) for i in range(SPLIT, len(d))]
for n, (src, _) in enumerate(seq): shutil.copyfile(src, os.path.join(out, f's{n:04d}.jpg'))
json.dump({'refresh_hz': t.get('refresh_hz', 60), 'durations': [x for _, x in seq]}, open(otj, 'w'))
print(f'{len(seq)} frames, {sum(x for _, x in seq) / 60:.2f} s (was {sum(d) / 60:.2f} s)')

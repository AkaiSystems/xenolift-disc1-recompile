#!/bin/bash
# Organized Xenolift backup: everything needed to rebuild, run and continue the project.
# usage: backup_xenolift.sh <destination folder> <browse|archive>
#   browse  - plain folders you can open (use on the FAT32 flash drive; files stay under 4 GB)
#   archive - project and session folders as .tar.gz (use inside ~/Downloads/xenolift, so no second
#             source tree sits inside the live project where builds or searches could pick it up)
set -euo pipefail
DEST="$1"; MODE="$2"; DAY=$(date +%Y-%m-%d)
ROOT="$DEST/Xenolift_Backup_$DAY"
PROJ="$HOME/Downloads/xenolift"
SESS="$HOME/Desktop/xenolift-session"
REPO="$SESS/xenolift-verify"
DISCS="$HOME/Desktop/PS7Z/PS1Games"
CLAUDE="$HOME/.claude/projects/-Users-joshuaghoreishi-Desktop-xenolift-session"
FAT="--modify-window=2"   # FAT32 keeps timestamps to 2 s

mkdir -p "$ROOT"/{1_Project_Source,2_Session_Workspace,3_Git_History,4_Movies,5_Game_Discs,6_Claude_Memory_and_Transcripts}
step() { echo "[$(date +%H:%M:%S)] $*"; }

step "1/6 project source ($PROJ)"
if [ "$MODE" = browse ]; then
  rsync -rt $FAT --delete --exclude '/backups/' "$PROJ/" "$ROOT/1_Project_Source/xenolift/"
else
  tar -czf "$ROOT/1_Project_Source/xenolift-source.tar.gz" --exclude 'xenolift/backups' -C "$(dirname "$PROJ")" xenolift
fi

step "2/6 session workspace ($SESS)"
if [ "$MODE" = browse ]; then
  rsync -rt $FAT --delete "$SESS/" "$ROOT/2_Session_Workspace/xenolift-session/"
else
  tar -czf "$ROOT/2_Session_Workspace/xenolift-session.tar.gz" -C "$(dirname "$SESS")" xenolift-session
fi

step "3/6 git history (all branches, including commits not yet on GitHub)"
git -C "$REPO" bundle create "$ROOT/3_Git_History/xenolift-verify.bundle" --all
git -C "$REPO" bundle verify "$ROOT/3_Git_History/xenolift-verify.bundle" >/dev/null
git -C "$REPO" log --oneline -40 > "$ROOT/3_Git_History/recent_commits.txt"

step "4/6 movies and images"
rsync -t $FAT "$HOME"/Desktop/xenolift_*.mov "$HOME"/Desktop/xenolift_*.gif "$HOME"/Desktop/xenolift_*.png "$ROOT/4_Movies/"

step "5/6 game disc images (Disc 1 is what the build reads)"
for d in "Xenogears (USA) (Disc 1)" "Xenogears (USA) (Disc 1)-1" "Xenogears (USA) (Disc 2)" "Xenogears (USA) (Disc 2)-1"; do
  [ -d "$DISCS/$d" ] && rsync -rt $FAT "$DISCS/$d" "$ROOT/5_Game_Discs/"
done

step "6/6 Claude memory and session transcripts"
rsync -rt $FAT "$CLAUDE/" "$ROOT/6_Claude_Memory_and_Transcripts/"

cat > "$ROOT/README.txt" <<EOF
Xenolift backup - $DAY ($MODE copy)
Xenogears Disc 1 static recompilation (PS1 -> native macOS).

1_Project_Source            ~/Downloads/xenolift: the source of truth. Runtime (runtime/runtime.c), HLE
                            modules (hle/), Rust emitter, run.sh build/run script, overlay capture files,
                            its own .git, DuckStation reference files, and the run logs.
2_Session_Workspace         ~/Desktop/xenolift-session: test harness (tools/boot_protocol.sh), analysis
                            tools, side-panel reports, the 4K upscale and logo pipeline (upscale/), every
                            trial log (trials/), and the xenolift-verify git checkout.
3_Git_History               xenolift-verify.bundle: the full repository with all branches, including
                            commits not yet pushed to GitHub. Restore: git clone xenolift-verify.bundle
                            (branch xenolift-clean). recent_commits.txt lists the latest commits.
4_Movies                    Opening movie in 4K (original and Square Enix versions), GIFs, progress frames.
5_Game_Discs                Xenogears (USA) Disc 1 and Disc 2 images. run.sh reads Disc 1 from
                            ~/Desktop/PS7Z/PS1Games/Xenogears (USA) (Disc 1)/Xenogears (USA) (Disc 1)/
                            (or set XG_DISC_BIN to the .bin path).
6_Claude_Memory_and_Transcripts
                            Claude's project memory (memory/) and conversation transcripts (.jsonl).

Restore
  1. Put 1_Project_Source/xenolift at ~/Downloads/xenolift (archive copy: tar -xzf xenolift-source.tar.gz -C ~/Downloads).
  2. Put 2_Session_Workspace/xenolift-session at ~/Desktop/xenolift-session (archive: tar -xzf ... -C ~/Desktop).
  3. Put the 5_Game_Discs folders in ~/Desktop/PS7Z/PS1Games/.
  4. Copy 6_Claude_Memory_and_Transcripts to ~/.claude/projects/-Users-joshuaghoreishi-Desktop-xenolift-session/.
  5. Install the toolchain (not included): Xcode Command Line Tools and Rust (rustup). Then: cd ~/Downloads/xenolift && bash run.sh
  Flash-drive (FAT32) copies do not keep executable bits: run scripts with bash, or chmod +x them after restoring.
EOF
step "done: $ROOT"
du -sh "$ROOT"/* 2>/dev/null

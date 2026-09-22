#!/bin/bash
# Xenolift Mac runner: pull GitHub → one cycle → push digest.
# Intended to run ON the MacBook (launchd or Claude Code). Cloud cannot invoke this.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE_DIR="$REPO_ROOT/source"
DIRECTIVE="$REPO_ROOT/docs/directives/next.json"
DIGEST_DIR="$REPO_ROOT/docs/digests"
LOCK="$REPO_ROOT/docs/directives/.run.lock"
BRANCH="${XENOLIFT_BRANCH:-xenolift-clean}"
BUDGET_DEFAULT=120

log() { echo "[$(date '+%H:%M:%S')] $*"; }

cd "$REPO_ROOT"
git fetch origin
git checkout "$BRANCH"
git pull --ff-only origin "$BRANCH"

if [[ ! -f "$DIRECTIVE" ]]; then
  log "No docs/directives/next.json — idle."
  exit 0
fi

if [[ -f "$LOCK" ]]; then
  log "Lock present ($LOCK) — refusing stacked run."
  exit 0
fi

cycle_id=$(python3 -c "import json;print(json.load(open('$DIRECTIVE')).get('cycle_id','cycle'))")
budget=$(python3 -c "import json;print(json.load(open('$DIRECTIVE')).get('budget_s',$BUDGET_DEFAULT))")
mode=$(python3 -c "import json;print(json.load(open('$DIRECTIVE')).get('mode','verify'))")

log "Directive $cycle_id mode=$mode budget=${budget}s"
touch "$LOCK"
cleanup() { rm -f "$LOCK"; }
trap cleanup EXIT

cd "$SOURCE_DIR"
sha=$(shasum -a 256 runtime/runtime.c | awk '{print $1}')
log "runtime.c SHA-256=$sha"
echo "$budget" > xenolift_budget.txt
export RUN_BUDGET_S="$budget"

# Prefer existing disc env; do not invent paths
if [[ -z "${XG_DISC_BIN:-}" ]]; then
  log "WARNING: XG_DISC_BIN unset — run.sh will use its default Mac path"
fi

mkdir -p "$DIGEST_DIR"
digest_file="$DIGEST_DIR/${cycle_id}.md"
{
  echo "# Digest $cycle_id"
  echo
  echo "- host: $(hostname)"
  echo "- time: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "- branch: $BRANCH"
  echo "- mode: $mode"
  echo "- runtime_sha256: $sha"
  echo "- budget_s: $budget"
  echo "- XG_DISC_BIN: ${XG_DISC_BIN:-"(unset)"}"
  echo
  echo "## run.sh output"
  echo '```'
  ./run.sh 2>&1 || echo "RUN_EXIT=$?"
  echo '```'
} > "$digest_file"

cd "$REPO_ROOT"
mkdir -p docs/directives/done
mv "$DIRECTIVE" "docs/directives/done/${cycle_id}.json"
git add docs/digests docs/directives
git -c user.email="xenolift-runner@local" -c user.name="xenolift-runner" commit -m "digest: $cycle_id ($mode)" || log "Nothing to commit"
git push origin "$BRANCH" || log "Push failed — fix Mac git auth"

log "Done $cycle_id → $digest_file"

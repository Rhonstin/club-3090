#!/usr/bin/env bash
#
# Generate or submit a BENCHMARKS.md row from results/rebench/<tag>/.
#
# Usage:
#   bash scripts/submit-bench.sh --tag <tag>
#   bash scripts/submit-bench.sh --tag <tag> --auto-submit
#   bash scripts/submit-bench.sh --tag <tag> --auto-submit --as-pr

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TAG=""
AUTO_SUBMIT=0
AS_PR=0
SECTION_OVERRIDE=""

usage() {
  sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

die() {
  echo "[submit-bench] ERROR: $*" >&2
  exit 1
}

log() {
  echo "[submit-bench] $*"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      [[ $# -ge 2 ]] || die "--tag requires a value"
      TAG="$2"
      shift 2
      ;;
    --auto-submit)
      AUTO_SUBMIT=1
      shift
      ;;
    --as-pr)
      AS_PR=1
      shift
      ;;
    --section)
      [[ $# -ge 2 ]] || die "--section requires a value"
      SECTION_OVERRIDE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      die "unknown arg: $1"
      ;;
  esac
done

[[ -n "$TAG" ]] || die "--tag <tag> is required"

TAG_DIR="results/rebench/${TAG}"
[[ -d "$TAG_DIR" ]] || die "tag dir not found: ${TAG_DIR}"
[[ -f "$TAG_DIR/REPORT.md" ]] || die "missing required artifact: ${TAG_DIR}/REPORT.md"
[[ -f "$TAG_DIR/_internal.json" ]] || die "missing required artifact: ${TAG_DIR}/_internal.json"
[[ -f "$TAG_DIR/container-config.json" ]] || die "missing required artifact: ${TAG_DIR}/container-config.json"
[[ -f "$TAG_DIR/rig.txt" ]] || die "missing required artifact: ${TAG_DIR}/rig.txt"

# shellcheck source=lib/bench-row-formatter.sh
source "$ROOT_DIR/scripts/lib/bench-row-formatter.sh"

github_user_for_row() {
  if [[ -n "${BENCH_ROW_GITHUB_USER:-}" ]]; then
    printf '%s' "${BENCH_ROW_GITHUB_USER#@}"
    return 0
  fi
  if [[ "${GH_MOCK:-0}" == "1" ]]; then
    printf '%s' "${GH_MOCK_USER:-mock-user}"
    return 0
  fi
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    gh api user --jq .login 2>/dev/null || true
  fi
}

if [[ "$AUTO_SUBMIT" -eq 1 ]]; then
  GH_USER="$(github_user_for_row)"
  [[ -n "$GH_USER" ]] || die "not authed with gh. Run: gh auth login"
  export BENCH_ROW_GITHUB_USER="$GH_USER"
fi

ROW="$(bench_row_format "$TAG_DIR")"
SECTION="${SECTION_OVERRIDE:-$(bench_row_section "$TAG_DIR")}"
OUTPUT="$TAG_DIR/BENCHMARKS-row.md"
printf '%s\n' "$ROW" > "$OUTPUT"

log "Generated BENCHMARKS row for section: ${SECTION}"
log "Wrote: ${OUTPUT}"
echo

valid_sections() {
  rg -n '^(##|###) ' BENCHMARKS.md | sed 's/^/[submit-bench]   /' >&2 || true
}

write_pr_body() {
  local body_file="$1"
  local row="$2"
  local tag="$3"
  local template=".github/PULL_REQUEST_TEMPLATE/bench-row.md"

  if [[ -f "$template" ]]; then
    python3 - "$template" "$body_file" "$tag" "$row" <<'PY'
from pathlib import Path
import sys

template, body_file, tag, row = sys.argv[1:5]
text = Path(template).read_text()
text = text.replace("<TAG>", tag)
text = text.replace("<!-- The generated BENCHMARKS.md row goes here -->", row)
text = text.replace(
    "<!-- Output of `bash scripts/report.sh` (redacted) -->",
    f"See `results/rebench/{tag}/rig.txt`.",
)
Path(body_file).write_text(text)
PY
  else
    {
      echo "## Rig bench submission"
      echo
      echo "### New row"
      echo
      echo "$row"
      echo
      echo "### Full results"
      echo
      echo "See \`results/rebench/${tag}/REPORT.md\`."
    } > "$body_file"
  fi
}

write_issue_body() {
  local body_file="$1"
  local row="$2"
  local tag="$3"
  local section="$4"

  # The repo's numbers-from-your-rig issue template is a structured YAML form
  # with required textarea/dropdown fields. `gh issue create --template` opens
  # that interactive form shape, which is not useful once submit-bench has
  # already generated the structured report. Use a direct markdown body instead.
  {
    echo "**Compose / section**: \`${section}\`"
    echo
    echo "**Rig**:"
    echo
    echo '```text'
    cat "${TAG_DIR}/rig.txt"
    echo '```'
    echo
    echo "**Proposed BENCHMARKS.md row**:"
    echo
    echo "$row"
    echo
    echo "**Full report**: \`results/rebench/${tag}/REPORT.md\`"
    echo
    echo "**Generated row file**: \`results/rebench/${tag}/BENCHMARKS-row.md\`"
  } > "$body_file"
}

insert_row() {
  local section="$1"
  local row="$2"
  python3 - "$section" "$row" <<'PY'
from __future__ import annotations

import sys
from pathlib import Path

section = sys.argv[1]
row = sys.argv[2]
path = Path("BENCHMARKS.md")
lines = path.read_text().splitlines()

heading_idx = None
for i, line in enumerate(lines):
    if line.strip() in {f"## {section}", f"### {section}"}:
        heading_idx = i
        break
if heading_idx is None:
    print(f"[submit-bench] ERROR: section not found in BENCHMARKS.md: {section}", file=sys.stderr)
    raise SystemExit(1)

table_start = None
for i in range(heading_idx + 1, len(lines)):
    if lines[i].startswith("#"):
        break
    if lines[i].startswith("|"):
        table_start = i
        break
if table_start is None:
    print(f"[submit-bench] ERROR: no markdown table found below section: {section}", file=sys.stderr)
    raise SystemExit(1)

insert_at = table_start
for i in range(table_start, len(lines)):
    line = lines[i]
    if line.startswith("#"):
        break
    if line.startswith("|"):
        insert_at = i + 1
        continue
    if insert_at > table_start:
        break

lines.insert(insert_at, row)
path.write_text("\n".join(lines) + "\n")
PY
}

if [[ "$AUTO_SUBMIT" -ne 1 ]]; then
  cat <<EOF
Inspect at ${OUTPUT}. Three ways to land it (recommended order):

  1. Issue + maintainer integrates (preferred — vetting before merge):
       bash scripts/submit-bench.sh --tag ${TAG} --auto-submit
       (opens an issue via \`gh issue create\`)
     Or, no-gh-needed:
       https://github.com/noonghunna/club-3090/issues/new?template=numbers-from-your-rig.yml
       — paste the contents of ${OUTPUT} + ${TAG_DIR}/rig.txt into the body

  2. Direct PR (advanced — for contributors who know the matrix structure):
       bash scripts/submit-bench.sh --tag ${TAG} --auto-submit --as-pr
     Note: matrix is hand-curated; direct PRs may get redirected to an
     issue thread for context-gathering before merge.

  3. Manual edit (zero tools):
       Paste the row from ${OUTPUT} into BENCHMARKS.md via the GitHub web editor.
EOF
  exit 0
fi

if [[ -n "$SECTION_OVERRIDE" ]]; then
  if ! rg -q "^(##|###) ${SECTION_OVERRIDE//\//\\/}$" BENCHMARKS.md; then
    echo "[submit-bench] Known sections:" >&2
    valid_sections
    die "section override not found: ${SECTION_OVERRIDE}"
  fi
fi

PR_TITLE="bench(matrix): @${BENCH_ROW_GITHUB_USER} $(bench_row_rig_shortname "$TAG_DIR")"
ISSUE_TITLE="[bench] @${BENCH_ROW_GITHUB_USER} $(bench_row_rig_shortname "$TAG_DIR")"
BRANCH_USER="$(printf '%s' "${BENCH_ROW_GITHUB_USER}" | tr -cd '[:alnum:]_.-')"
BRANCH_TAG="$(printf '%s' "${TAG}" | tr -cd '[:alnum:]_.-')"
BRANCH="bench/${BRANCH_USER}-${BRANCH_TAG}"
if [[ "$AS_PR" -eq 1 ]]; then
  BODY_FILE="$TAG_DIR/PR-body.md"
  write_pr_body "$BODY_FILE" "$ROW" "$TAG"
else
  BODY_FILE="$TAG_DIR/ISSUE-body.md"
  write_issue_body "$BODY_FILE" "$ROW" "$TAG" "$SECTION"
fi

if [[ "${GH_MOCK:-0}" == "1" ]]; then
  MOCK_LOG="$TAG_DIR/auto-submit-mock.log"
  if [[ "$AS_PR" -eq 1 ]]; then
    {
      echo "git switch -c ${BRANCH}"
      echo "insert BENCHMARKS.md row under: ${SECTION}"
      echo "git commit -m ${PR_TITLE}"
      echo "git push -u origin ${BRANCH}"
      echo "gh pr create --title ${PR_TITLE} --body-file ${BODY_FILE}"
    } > "$MOCK_LOG"
    log "GH_MOCK=1 — wrote mocked PR auto-submit commands: ${MOCK_LOG}"
    log "PR title: ${PR_TITLE}"
  else
    {
      echo "gh issue create --title ${ISSUE_TITLE} --body-file ${BODY_FILE} --label bench-contribution"
    } > "$MOCK_LOG"
    log "GH_MOCK=1 — wrote mocked issue auto-submit command: ${MOCK_LOG}"
    log "Issue title: ${ISSUE_TITLE}"
  fi
  exit 0
fi

command -v gh >/dev/null 2>&1 || die "'gh' not found. Install GitHub CLI or submit manually."
gh auth status >/dev/null 2>&1 || die "not authed with gh. Run: gh auth login"

if [[ "$AS_PR" -ne 1 ]]; then
  ISSUE_URL="$(gh issue create --title "$ISSUE_TITLE" --body-file "$BODY_FILE" --label bench-contribution)"
  log "Opened issue: ${ISSUE_URL}"
  exit 0
fi

if ! git diff --quiet -- BENCHMARKS.md; then
  die "BENCHMARKS.md already has local edits; commit/stash them before --auto-submit"
fi

git fetch origin master >/dev/null 2>&1 || log "WARN: git fetch origin master failed; continuing from current branch"
if git show-ref --verify --quiet refs/remotes/origin/master; then
  git switch -c "$BRANCH" origin/master
else
  git switch -c "$BRANCH"
fi
insert_row "$SECTION" "$ROW"
git add BENCHMARKS.md
git commit -m "$PR_TITLE"
git push -u origin "$BRANCH"
PR_URL="$(gh pr create --title "$PR_TITLE" --body-file "$BODY_FILE")"
log "Opened PR: ${PR_URL}"

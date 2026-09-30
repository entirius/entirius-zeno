#!/usr/bin/env bash
# dev-runner checkpoints (KIND: checkpoint, FROM: <plan>): diff <done tag of FROM>..HEAD per REPOS repo,
# 3 independent reviewers (contract / tests / regressions), criticals → FIX- plan (checkpoint waits),
# majors → BG- plan (background), then the checkpoint is ready and tagged itself.
# Sourced by runner.sh; uses lib.sh + runner.sh globals (PLAN_SRC, PLAN_FILE, PLAN_ID, TOPIC, HAND, PLAN_CAP_USD).
# shellcheck disable=SC2153  # HAND/PLAN_* are runner.sh globals

CR_DIMS=(contract tests regressions)
: "${CR_SPLIT_BYTES:=150000}"   # total diff > 150 KB → one reviewer call per repo, findings merged
: "${CR_CHUNK_BYTES:=150000}"   # a single repo diff above this is reviewed in chunks (a 200 KB prompt ≈ $2 to read)
: "${CR_CAP_USD:=6}"            # per panel call; a reviewer must read the whole chunk before it can answer

run_checkpoint() {
  local from crit majors
  from=$(plan_header "$PLAN_FILE" FROM)
  [[ -n $from ]] || { escalate "checkpoint without FROM header"; return 0; }
  cr_make_diffs "$from" || return 0
  cr_panel || return 0
  guard_scope || return 0
  cr_no_commits || return 0
  plan_unchanged || { escalate "plan file changed during the checkpoint"; return 0; }
  crit=$(cr_count critical); majors=$(cr_count major)
  [[ $crit =~ ^[0-9]+$ && $majors =~ ^[0-9]+$ ]] || { escalate "checkpoint: unreadable panel verdicts"; return 0; }
  log "CR panel: critical=$crit major=$majors (verdicts: $HAND/cr-*-findings.json)"
  if (( crit > 0 )); then cr_block "$crit"; return 0; fi
  (( majors > 0 )) && cr_seed_plan BG "$(cr_findings_json 'select(.severity != "critical")')" >/dev/null
  tag_done
  release_repos
  mutate plan_set_status "$PLAN_SRC" ready
  journal "$PLAN_ID | CHECKPOINT OK | critical=0 major=$majors"
  archive_handoff
}

cr_diff_name() { echo "${1//\//_}"; }   # REPOS entry → file-safe name (no basename collisions)

# The anchor tag must match the SHA recorded outside the repo at that plan's finalize — a coder can move
# a local tag, it cannot move .runner/bases. Missing tag/record or an all-empty range = escalate.
cr_make_diffs() { # from → $HAND/cr-<repo>.diff per repo
  local r dir tag any=0 want have; tag=$(done_tag "$1")
  while IFS= read -r r; do
    dir=$(repo_dir "$r")
    want=$(cat "$(done_file "$1" "$dir")" 2>/dev/null) || { escalate "checkpoint: no finalize record for $1 in $r"; return 1; }
    have=$(git -C "$dir" rev-parse -q --verify "$tag^{commit}" 2>/dev/null) || { escalate "checkpoint: tag $tag missing in $r"; return 1; }
    [[ $want == "$have" ]] || { escalate "checkpoint: tag $tag in $r does not match the finalize record"; return 1; }
    git -C "$dir" diff "$tag..HEAD" > "$HAND/cr-$(cr_diff_name "$r").diff"
    if [[ -s $HAND/cr-$(cr_diff_name "$r").diff ]]; then any=1; else log "checkpoint: empty range in $r"; fi
  done < <(plan_repos "$PLAN_FILE")
  (( any == 1 )) || { escalate "checkpoint: empty diff since $tag in every repo"; return 1; }
}

# Checkpoints never touch repos: HEAD of every REPOS repo must equal the claim snapshot.
cr_no_commits() {
  local r dir
  while IFS= read -r r; do
    dir=$(repo_dir "$r")
    grep -qxF "$dir"$'\t'"HEAD $(git -C "$dir" rev-parse HEAD)" "$HAND/scope-base.txt" || { escalate "checkpoint: commits appeared in $r during the review"; return 1; }
  done < <(plan_repos "$PLAN_FILE")
}

# 3 independent calls; a reviewer failing after one retry = inconclusive → escalate (never fabricate).
cr_panel() {
  local dim out
  for dim in "${CR_DIMS[@]}"; do
    out=$HAND/cr-$dim-findings.json
    jq -e '.findings | type == "array"' "$out" >/dev/null 2>&1 && continue   # dimension done on a previous tick
    cr_dimension "$dim" 1 > "$out" || cr_dimension "$dim" 2 > "$out" || { escalate "checkpoint inconclusive: reviewer '$dim' failed twice"; return 1; }
    budget_ok "$HAND" "$PLAN_CAP_USD" || { escalate "budget exceeded (cap \$$PLAN_CAP_USD)"; return 1; }
  done
}

cr_dimension() { # dim try → merged findings JSON on stdout (one call, per repo, or per chunk when large)
  local total=0 f parts=() p
  for f in "$HAND"/cr-*.diff; do total=$((total + $(stat -c %s "$f"))); done
  if (( total > CR_SPLIT_BYTES )); then
    for f in $(cr_chunks); do p=$(cr_reviewer_call "$1" "$2-$(basename "$f" .diff)" "$f") || return 1; parts+=("$p"); done
  else
    p=$(cr_reviewer_call "$1" "$2" "$HAND"/cr-*.diff) || return 1; parts+=("$p")
  fi
  printf '%s\n' "${parts[@]}" | jq -cs '{findings: [.[].findings[]?]}'
}

# Split every repo diff above CR_CHUNK_BYTES on file boundaries (`diff --git` headers) into cr-<repo>.pNN.diff.
cr_chunks() {
  local f
  for f in "$HAND"/cr-*.diff; do
    [[ $f == *.p[0-9][0-9].diff ]] && continue
    if (( $(stat -c %s "$f") <= CR_CHUNK_BYTES )); then echo "$f"; continue; fi
    [[ -f ${f%.diff}.p00.diff ]] || awk -v max="$CR_CHUNK_BYTES" -v base="${f%.diff}" '
      /^diff --git / && size > 0 && size + length($0) > max { close(out); n++; size = 0 }
      { if (size == 0) out = sprintf("%s.p%02d.diff", base, n); print > out; size += length($0) + 1 }' "$f"
    ls "${f%.diff}".p[0-9][0-9].diff
  done
}

# One reviewer-profile call through run_role_live (profile check, watchdog, is_error, cost booking).
cr_reviewer_call() { # dim call-id diff-files... → findings JSON on stdout (rc 1 = failed/unparsable)
  local dim=$1 hand=$HAND/cr-$1-$2 rc=0; shift 2
  mkdir -p "$hand"
  cr_prompt "$dim" "$@" > "$hand/reviewer-prompt.md"
  if [[ $MOCK_ROLES == 1 ]]; then cr_mock_result "$hand" || rc=$?
  else run_role_live reviewer "$hand" "$CR_CAP_USD" "" "$hand/reviewer-prompt.md" || rc=$?; fi
  record_cost reviewer "$hand" "$CR_CAP_USD"
  (( rc == 0 )) || return 1
  jq -r '.result // empty' "$hand/reviewer-out.json" | cr_parse_findings
}

cr_mock_result() { # hand → reviewer-out.json from MOCK_CR_JSON (MOCK_CR_FAIL=1 → rc 1, MOCK_CR_PROSE=1 → prose prefix)
  [[ ${MOCK_CR_FAIL:-0} == 1 ]] && return 1
  local body=${MOCK_CR_JSON:-{\"findings\":[]\}}
  [[ ${MOCK_CR_PROSE:-0} == 1 ]] && body="Here is my verdict:"$'\n'"$body"
  jq -n --arg r "$body" '{result: $r, total_cost_usd: 0.01}' > "$1/reviewer-out.json"
}

# shellcheck disable=SC2016
cr_prompt() { # dim diff-files... → stdout; every diff is nonce-fenced, labelled by repo, never instructions
  local f
  cat "$RUNNER_DIR/prompts/cr/panel-base.md"
  printf '\n## Your dimension in this call: %s\n\n## Plan under review\n%s (zeno root: %s)\n' "$1" "$PLAN_SRC" "$ZENO_ROOT"; shift
  for f in "$@"; do untrusted "Diff: $(basename "$f" .diff)" "$(cat "$f")"; done
  printf '\nFORMAT REMINDER: answer ONLY with bare JSON {"findings":[...]} — no text before or after.\n'
}

# Reviewers sometimes prefix JSON with prose — take from the first line containing {"findings".
# Anything without a findings ARRAY is a failure (never an empty verdict).
cr_parse_findings() {
  local txt out; txt=$(sed '/^```/d')
  out=$(jq -c 'select(.findings | type == "array")' <<<"$txt" 2>/dev/null) ||
    out=$(sed -n '/{"findings"/,$p' <<<"$txt" | jq -c 'select(.findings | type == "array")' 2>/dev/null)
  [[ -n $out ]] || return 1
  printf '%s\n' "$out"
}

cr_files() { local d; for d in "${CR_DIMS[@]}"; do echo "$HAND/cr-$d-findings.json"; done; }
# shellcheck disable=SC2046
cr_count() { jq -s "[.[].findings[]? | select(.severity == \"$1\")] | length" $(cr_files) 2>/dev/null; }
# shellcheck disable=SC2046
cr_findings_json() { jq -s "[.[].findings[]? | $1]" $(cr_files); }

# Seed a FIX plan and wait for it (DEPENDS += FIX id). A FIX that already reached `ready` while the panel still
# blocks = the operator decides (never a paid loop).
cr_block() { # crit
  local fix file
  file=$PLANS_DIR/FIX-$PLAN_ID-checkpoint.md
  [[ -f $file && $(plan_header "$file" STATUS) == ready ]] && { escalate "checkpoint still blocked after FIX-$PLAN_ID was fixed ($1 critical)"; return 0; }
  fix=$(cr_seed_plan FIX "$(cr_findings_json 'select(.severity == "critical")')")
  cr_add_dependency "$fix"
  release_repos
  mutate plan_set_status "$PLAN_SRC" to-dev
  journal "$PLAN_ID | CHECKPOINT BLOCKED | critical=$1 → $fix seeded; checkpoint re-runs after it"
  archive_handoff
}

cr_add_dependency() { # id — idempotent; inserts the header when absent
  local cur; cur=$(plan_header "$PLAN_SRC" DEPENDS)
  grep -qw -- "$1" <<<"$cur" && return 0
  if head -12 "$PLAN_SRC" | grep -q '^DEPENDS:'; then mutate sed -i "1,12s/^DEPENDS:.*/DEPENDS: ${cur:+$cur, }$1/" "$PLAN_SRC"
  else mutate sed -i "1,12s/^KIND:.*/&\nDEPENDS: $1/" "$PLAN_SRC"; fi
}

# Seeded plans are ordinary stages with NO gate block (DEFAULT gate) — LLM text never reaches bash.
# shellcheck disable=SC2016  # markdown backticks
cr_seed_plan() { # FIX|BG findings-json → plan id on stdout
  local kind=$1 findings=$2 id=$1-$PLAN_ID file=$PLANS_DIR/$1-$PLAN_ID-checkpoint.md title budget
  title=$([[ $kind == FIX ]] && echo "critical findings (checkpoint waits)" || echo "major/minor findings (background)")
  [[ -f $file ]] && { echo "$id"; return 0; }
  budget=$(awk -v c="$CODER_CAP_USD" 'BEGIN {print c * 2}')
  {
    printf 'STATUS: to-dev\nKIND: stage\nDEPENDS:\nREPOS: %s\nBRANCH: %s\nBUDGET_USD: %s\nTIMEOUT_S: 7200\nCOMMIT_ANY: true\n\n' \
      "$(plan_header "$PLAN_FILE" REPOS)" "$(plan_header "$PLAN_FILE" BRANCH)" "$budget"
    printf '# Plan %s — %s from checkpoint %s (auto-seeded)\n\n' "$id" "$title" "$PLAN_ID"
    printf '## Goal\n\nFix exactly the findings below — scope strictly by findings, no widening. Gate = default (`make migrate && make test`).\n'
    untrusted "Findings from the review panel" "$findings"
    printf '\n## Prompt for the dev session\n\n```\nExecute plan %s from %s. Read the checkpoint plan and its range; fix every finding listed; commit in the repos you touch.\n```\n' "$id" "$file"
  } > "$file"
  cr_readme_row "$id" "$file" "$title"
  echo "$id"
}

cr_readme_row() { # id file title — append a table row to 00-README.md (mirror for plan_set_status)
  local readme=$PLANS_DIR/00-README.md
  [[ -f $readme ]] || return 0
  grep -q '^|' "$readme" || { log "warning: no table in 00-README — row for $1 not added"; return 0; }
  awk -v row="| $1 | \`$(basename "$2")\` | to-dev | — | auto | $3 |" '
    /^\|/ {last = NR} {lines[NR] = $0} END {for (i = 1; i <= NR; i++) {print lines[i]; if (i == last) print row}}' \
    "$readme" > "$readme.tmp" && mv "$readme.tmp" "$readme"
}

#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: 2025 Icinga GmbH
# SPDX-License-Identifier: MIT

usage() {
  cat <<EOF
Updates GitHub branch protection rules with required status checks
based on GitHub Actions workflows triggered by a specified pull request,
while preserving non-Actions checks (e.g., CLA bots).

Helps automate updating branch protection rules dynamically
when new or changed Actions workflows appear in PRs.

Usage:
  gh-update-branch-protection-checks.sh --repo owner/repo --pr PR_NUMBER [--dry-run]

Requirements:
  - GitHub CLI (gh) installed and authenticated with permissions to read PRs,
    list and view runs, and modify branch protection on the target repo.
  - jq for JSON processing.

Arguments:
  --repo    GitHub repository in owner/repo format, e.g., octocat/Hello-World.
  --pr      Pull request number; merged is recommended; unmerged uses the current head commit.
  --dry-run Optional. Shows a unified diff of current vs. intended protection and exits without changes.
EOF
}

set -euo pipefail

REPO=""
PR_NUMBER=""
DRY_RUN=false

# Parse command line arguments.
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --pr) PR_NUMBER="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help|help) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

[[ -z "${REPO}" || -z "${PR_NUMBER}" ]] && usage && exit 1

# Colors for output.
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions.
log_info()    { printf "${BLUE}[INFO]${NC} %s\n" "$1"; }
log_success() { printf "${GREEN}[SUCCESS]${NC} %s\n" "$1"; }
log_warning() { printf "${YELLOW}[WARNING]${NC} %s\n" "$1"; }
log_error()   { printf "${RED}[ERROR]${NC} %s\n" "$1" >&2; }

# Helper function to join array elements for logging.
implode() {
  local delimiter="$1"; shift
  local array=("$@")
  local output=""
  for ((i=0; i<${#array[@]}; i++)); do
    output+="${array[$i]}${delimiter}"
  done
  echo "${output%${delimiter}}" # Remove trailing delimiter.
}

require_cmd() {
  local name="$1"
  command -v "${name}" >/dev/null 2>&1 || { log_error "Missing dependency: ${name}"; exit 127; }
}

# Dependency checks.
require_cmd gh
require_cmd jq

# Validate auth.
if ! gh auth status >/dev/null 2>&1; then
  log_error "gh is not authenticated. Run: gh auth login"
  exit 1
fi

# Validate repo.
if ! gh repo view "${REPO}" >/dev/null 2>&1; then
  log_error "Unable to access repository ${REPO}"
  exit 1
fi

log_info "Fetching PR details..."
pr_json="$(gh pr view "${PR_NUMBER}" --repo "${REPO}" --json baseRefName,headRefName,headRefOid,mergeCommit)"
base_branch=$(echo "${pr_json}" | jq -r '.baseRefName')
head_branch=$(echo "${pr_json}" | jq -r '.headRefName') # For informational purposes only.
head_sha=$(echo "${pr_json}" | jq -r '.headRefOid')
merge_commit="$(echo "${pr_json}" | jq -r '.mergeCommit.oid // empty')"
if [[ -n "${merge_commit}" ]]; then
  commit="${merge_commit}"
else
  log_warning "PR #${PR_NUMBER} is not merged; continuing anyway..."
  commit="${head_sha}"
fi
log_info "Target branch: ${base_branch}"
log_info "PR head branch: ${head_branch}"
log_info "PR head commit SHA: ${head_sha}"
[[ -z "${merge_commit}" ]] || log_info "PR merge commit SHA: ${merge_commit}"

log_info "Listing workflow runs triggered by commit ${commit}..."
# Prefers --commit to avoid branch ambiguity and pagination complexity.
# Note: gh run list supports --limit, but commit filter should be tight already.
run_ids=($(gh run list --repo "${REPO}" --commit "${commit}" --json databaseId --jq '.[] | .databaseId'))
if [[ ${#run_ids[@]} -eq 0 ]]; then
  log_error "No workflow runs found for commit ${commit}."
  exit 1
fi
log_info "Workflow runs: $(implode ', ' "${run_ids[@]}")"

# Extract job names from workflow runs to form required status checks.
# First, gather all job names across runs.
# Note: Job names are considered to be unique.
jobs=()
for run_id in "${run_ids[@]}"; do
   log_info "Listing jobs for workflow ${run_id}..."
   while IFS= read -r line; do
       jobs+=("${line}")
   done < <(gh run view --repo "${REPO}" "${run_id}" --json jobs --jq '.jobs[] | .name')
   log_info "Jobs: $(implode ', ' "${jobs[@]}")"
done
# Then, build `required_status_checks.checks` from jobs array.
# Note: Job output assumes only GitHub Actions, so app_id is hard-coded.
GH_APP_ID=15368
required_status_checks=$(printf '%s\n' "${jobs[@]}" | sort | jq -R -s --argjson app_id "${GH_APP_ID}" \
  'split("\n") | map(select(length > 0)) | {checks: map({context: ., app_id: $app_id})}')

log_info "Fetching current branch protection required status checks..."
bp_current=$(gh api repos/"${REPO}"/branches/"${base_branch}"/protection)

# Build desired branch protection required status checks by merging:
# - existing required checks that are not from GitHub Actions (e.g., CLA bots; in order to preserve them),
# - with all GitHub Actions job names from workflow runs triggered by the PR.
bp_desired=$(jq -S --argjson app_id "${GH_APP_ID}" -s '
  .[0] |= (.required_status_checks //= {checks: []}) |
  .[0].required_status_checks.checks |= map(select(.app_id != $app_id)) |
  .[0].required_status_checks.checks += .[1].checks |
  .[0]
' <(echo "${bp_current}") <(echo "${required_status_checks}"))

log_info "Comparing branch protection required status checks..."
# Prepare diff by sorting the entire JSON and ...
jq_sort='
  def walk(f):
    . as $in |
    if type == "object" then
      reduce keys[] as $key ({}; . + { ($key): ($in[$key] | walk(f)) }) | f
    elif type == "array" then
      map(walk(f)) | sort_by(.) | f
    else
      f
    end;

  walk(.)
'
# ... removing deprecated .required_status_checks.contexts; we use .required_status_checks.checks instead.
bp_current="$(echo "${bp_current}" | jq -S "del(.required_status_checks.contexts) | ${jq_sort}")"
bp_desired="$(echo "${bp_desired}" | jq -S "del(.required_status_checks.contexts) | ${jq_sort}")"
if diff -q <(echo "${bp_current}") <(echo "${bp_desired}") > /dev/null 2>&1; then
  log_success "No changes required (required status checks already up to date)."
  exit 0
fi
diff --color -u <(echo "${bp_current}") <(echo "${bp_desired}") || true
if ${DRY_RUN}; then
  log_success "[dry-run] No changes applied."
  exit 0
fi

log_info "Updating branch protection rules..."
# Transform JSON for branch protection update because
# GET response format differs from the required PUT request format:
# - Strip all URL-related fields
# - Flatten boolean flags nested inside {enabled: bool} objects
jq_transform='
  def walk(f):
    . as $in |
    if type == "object" then
      reduce keys[] as $key
        ({};
          if $key == "url" or ($key | endswith("_url")) then .
          else . + { ($key): ($in[$key] | walk(f)) }
          end
        ) | f
    elif type == "array" then
      map(walk(f)) | f
    else
      f
    end;

  walk(
    if type == "object" and has("enabled") then
      .enabled
    else
      .
    end
  )
'
gh api --method PUT "repos/${REPO}/branches/${base_branch}/protection" --input  <(echo "${bp_desired}" | jq "${jq_transform}")
log_success "Branch protection updated for branch ${base_branch} of repository ${REPO}."

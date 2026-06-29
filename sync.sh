#!/bin/bash

# GitHub Action Deployment:
# 1. Receives repository list from `list-repos.sh`
# 2. Creates temporary branches for each target repository
# 3. Cherry-picks local branch into target branch
# 4. Pushes changes and creates pull requests with auto-generated title and body from commits
# 5. Cleans up local environment (deletes branches/remotes)

# Configuration
DRY_RUN=false

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color (Reset)

show_help() {
    cat << EOF
GitHub Action Deployment - Push Branch to Multiple Repos

Usage: $0 [OPTIONS]

This script usees stdin to push the current branch to multiple repositories and creates PRs with automated message from commits.

OPTIONS:
    --dry-run              Only show what would be done, without changes
    -h, --help             Show this help

EXAMPLES:
    # Use with pipe from list-repos.sh
    ./list-repos.sh -p "Icinga/*" | sync.sh

    # Dry-run to see what would happen
    ./list-repos.sh -p "Icinga/*" | $0 --dry-run
EOF
}

# Parameter parsen
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_help >&2
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            show_help >&2
            exit 1
            ;;
    esac
done

# Get current branch
BRANCH_TO_DISTRIBUTE=$(git branch --show-current)
if [[ -z "$BRANCH_TO_DISTRIBUTE" ]]; then
    exit 1
fi

#global arrays
created_branches=()
updated_repositories=()
failed_repositories=()

deploy_to_repo() {
    local repo="$1"

   # Create remote name from repo (replace / with -)
    local remote_name="${repo//\//-}"
    WORKING_BRUNCH="$remote_name/$BRANCH_TO_DISTRIBUTE"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] $repo - would cherry-pick branch '$BRANCH_TO_DISTRIBUTE'  to $WORKING_BRUNCH" >&2
        return 0
    fi

    echo -e "${BLUE}Processing $repo...${NC}" >&2

    created_branches+=("$WORKING_BRUNCH")
    remote_repos+=("$remote_name")
    local expected_url="https://github.com/${repo}.git"

    #get and add remote repository url
    if ! git remote get-url "$remote_name"; then
      git remote add "$remote_name" "$expected_url"
    elif [[ "$(git remote get-url "$remote_name")" != "$expected_url" ]]; then
        echo -e "${RED}Error: Remote $remote_name URL mismatch${NC}" >&2
        return 1
    fi

    # Fetch the remote repository
    if ! git fetch "$remote_name"; then
        echo -e "${RED}$repo (fetch failed)${NC}" >&2
        return 1
    fi

    # Create new branch from remote main
    if ! git checkout -b "$WORKING_BRUNCH" "$remote_name/main"; then
      echo -e "${RED}Can not create new branch $WORKING_BRUNCH${NC}" >&2
      return 1
    fi

    #cherry-pick branch
    if ! git cherry-pick "$BRANCH_TO_DISTRIBUTE"; then
        echo -e "${RED}$repo (cherry-pick failed for branch $lworking_branch)${NC}" >&2
        git cherry-pick --abort || true
        return 1
    fi

    # Push to remote repository
    if ! git push "$remote_name" "HEAD:$BRANCH_TO_DISTRIBUTE"; then
        echo -e "${RED}$repo (push failed)${NC}" >&2
        return 1
    fi

    # Create pull request
    if gh pr create --repo "$repo" --fill  --head "$BRANCH_TO_DISTRIBUTE"  --base main; then
        echo -e "${GREEN}$repo (PR created)${NC}" >&2
    else
        echo -e "${RED}$repo (PR creation failed)${NC}" >&2
        return 1
    fi

    return 0
}

#set trap to clean up
 cleanup() {
    git checkout "$BRANCH_TO_DISTRIBUTE" || git checkout main

    for branch in "${created_branches[@]}"; do
      git branch -D "$branch"
    done

    for remote_repo in "${remote_repos[@]}"; do
      git remote remove "$remote_repo"
    done

 }

print_results() {
    echo >&2
    echo "=== RESULTS ===" >&2

        if [[ ${#updated_repositories[@]} -gt 0 ]]; then
          for repo in "${updated_repositories[@]}"; do
            echo -e "${GREEN}${repo} updated ${NC}"
          done
        fi

         if [[ ${#failed_repositories[@]} -gt 0 ]]; then
           for repo in "${failed_repositories[@]}"; do
              echo -e "${RED}${repo} failed ${NC}"
            done
        fi
}

  #trap to clean up
  trap 'print_results; cleanup' EXIT INT TERM

main() {

    # Read repository list from file or stdin
    local repositories=()
    mapfile -t repositories

    # Remove empty lines from stdin
    local filtered_repos=()
    for repo in "${repositories[@]}"; do
        [[ -n "$repo" ]] && filtered_repos+=("$repo")
    done

    repositories=("${filtered_repos[@]}")


    if [[ "$DRY_RUN" == "true" ]]; then
        for repo in "${repositories[@]}"; do
            deploy_to_repo "$repo"
        done
        return 0
    fi

    for repo in "${repositories[@]}"; do
        if ! deploy_to_repo "$repo"; then
          failed_repositories+=("$repo")
          exit 1;
        else
          updated_repositories+=("$repo")
        fi
        echo >&2
    done
}

# Script execution
main

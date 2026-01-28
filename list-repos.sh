#!/bin/bash

# Creates a list of repositories based on patterns and filters all public, non-archived repositories

PATTERNS=()

RED='\033[0;31m'
NC='\033[0m' # No Color (Reset)

show_help() {
    cat << EOF
GitHub Repository List Generator

Usage: $0 [OPTIONS]

OPTIONS:
    -p, --pattern PATTERN   Repository pattern (required)
                           Examples: "Icinga/icingaweb*", "MyOrg/*", "Icinga/icinga2"
    -h, --help             Show this help

EXAMPLES:
    # All public Icinga repos
    $0 -p "Icinga/*"

    # Only icingaweb repos in Icinga organization
    $0 -p "Icinga/icingaweb*"

EOF
}

# Parameter parsen
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--pattern)
            PATTERNS+=("$2")
            shift 2
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

# Check if patterns contain organization info
if [[ "${PATTERNS[0]}" != *"/"* ]]; then
    echo -e "${RED}Error: Pattern must include organization (e.g., 'Icinga/icingaweb*')${NC}" >&2
    show_help >&2
    exit 1
fi

get_repositories() {
    local org="${PATTERNS[0]%%/*}"

    # List all public, non-archived repositories for the organization
    gh repo list "$org" --limit 1000 --no-archived --visibility public --json name,owner | \
    jq -r '.[] | "\(.owner.login)/\(.name)"'
}

matches_pattern() {
    local repo="$1"
    local pattern="$2"

    # Bash pattern matching
    case "$repo" in
        $pattern) return 0 ;;
        *) return 1 ;;
    esac
}

# Pattern filtering
filter_repositories() {
    local repos=()

    while IFS= read -r repo; do
        for pattern in "${PATTERNS[@]}"; do
            if matches_pattern "$repo" "$pattern"; then
                repos+=("$repo")
                break
            fi
        done
    done

    printf '%s\n' "${repos[@]}"
}

main() {

    # Get and filter repositories
    mapfile -t repositories < <(get_repositories | filter_repositories)

    if [[ ${#repositories[@]} -eq 0 ]]; then
        echo -e "${RED}No repositories found matching the patterns${NC}" >&2
        exit 1
    fi

    # Output repositories to stdout
       printf '%s\n' "${repositories[@]}"
   }

# Script execution
main

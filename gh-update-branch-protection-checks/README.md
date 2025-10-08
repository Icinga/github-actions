# gh-update-branch-protection-checks

## About

**gh-update-branch-protection-checks** updates GitHub branch protection rules with required status checks
based on GitHub Actions workflows triggered by a specified pull request,
while preserving non-Actions checks (e.g., CLA bots).

This tool helps automate updating branch protection rules dynamically
when new or changed Actions workflows appear in PRs.

## Overview

- Takes a GitHub repository (`owner/repo`) and a pull request number.
- Lists workflow runs for the PR and collects all job names.
- Synchronizes those with the required status checks in branch protection rules of the PR's target branch.
- Preserves existing non–GitHub Actions checks (e.g., CLA checks).
- Supports a `--dry-run` mode to preview changes as a diff.

## Requirements

- [GitHub CLI (`gh`)](https://cli.github.com/) installed and authenticated with permissions to read PRs,
  list and view runs, and modify branch protection on the target repo.
- `jq` for JSON processing.

## Usage

`gh-update-branch-protection-checks.sh --repo owner/repo --pr PR_NUMBER [--dry-run]`

- `--repo`: GitHub repository in `owner/repo` format, e.g., `octocat/Hello-World`.
- `--pr`: Pull request number; merged is recommended; unmerged uses the current head commit.
- `--dry-run`: Optional. Shows a unified diff of current vs. intended protection and exits without changes.

## License

MIT License. See [LICENSE](LICENSE) for details.

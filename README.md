# Icinga GitHub Actions

This repository contains workflow files for centralized management and scripts for distribution of GitHub Actions to all relevant Icinga repositories.

### Management Scripts
The two scripts can be used to distribute GitHub Actions workflow files to multiple repositories.
It works with a local repository set up and creates automatically PRs.

### Prerequisites
- GitHub CLI (`gh`) installed and authenticated
- Write permissions for target repositories

### Setup
```bash
# Create local repository
mkdir github-actions-deploy
cd github-actions-deploy
git init
git checkout -b main

# Set up workflow structure
git checkout -b <Branch>
mkdir -p .github/workflows
cp /path/to/action-file.yml .github/workflows/action-file.yml

# Create commit
git add -A
git commit -m "Commit Message"
```

### Execution
```bash
# All Icinga repositories
./list-repos.sh -p "Icinga/*" | ./sync.sh

# Specific repository patterns
./list-repos.sh -p "Icinga/icingaweb*" | ./sync.sh

# Dry-run
./list-repos.sh -p "Icinga/*" | ./sync.sh --dry-run

#show help
./sync.sh -h
```

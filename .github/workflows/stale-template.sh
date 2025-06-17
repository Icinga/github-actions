# Stale Bot Action for Icinga
name: 'stale'

permissions:
  issues: write

on:
  schedule:
    - cron: 0 13 * * 1-5

jobs:
  stale:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/stale@v9
        with:
          close-issue-message: 'This issue has been automatically closed due to age/inactivity. If still relevant with current software version, feel free to create a new issue with updated details. '
          stale-issue-label: 'stale'
          exempt-issue-labels: 'ref/IP, ref/NP'
          exempt-all-issue-milestones: true
          days-before-issue-stale: 1780
          days-before-issue-close: 0
          operations-per-run: 15
          enable-statistics: true
          ignore-issue-updates: true
          ascending: true
          debug-only: true

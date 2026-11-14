#!/usr/bin/env bash
# Read-only preflight, or verify HEAD is contained in a fetched remote branch.
set -euo pipefail
case "${1:-preflight}" in
  preflight)
    git status --short --branch
    git branch -vv
    git branch -r
    git worktree list
    git log --branches --not --remotes --oneline
    if command -v gh >/dev/null; then gh pr list --state open --limit 100; else echo 'REVIEW: gh unavailable; check open PRs separately.'; fi
    ;;
  verify)
    branch="${2:?Usage: git_delivery.sh verify BRANCH}"
    git check-ref-format "refs/heads/$branch"
    git fetch origin "refs/heads/$branch:refs/remotes/origin/$branch"
    git merge-base --is-ancestor HEAD "refs/remotes/origin/$branch"
    printf 'Verified HEAD %s is contained in origin/%s at %s\n' "$(git rev-parse HEAD)" "$branch" "$(git rev-parse "refs/remotes/origin/$branch")"
    ;;
  *) echo 'Usage: git_delivery.sh [preflight|verify BRANCH]' >&2; exit 2 ;;
esac

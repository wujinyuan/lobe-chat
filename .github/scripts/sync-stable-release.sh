#!/usr/bin/env bash
set -euo pipefail

upstream_repo=${UPSTREAM_REPO:-lobehub/lobehub}
upstream_git_url=${UPSTREAM_GIT_URL:-https://github.com/${upstream_repo}.git}
target_branch=${TARGET_BRANCH:-main}

latest_tag=$(gh api "repos/${upstream_repo}/releases/latest" --jq '.tag_name')
if [[ -z "$latest_tag" ]]; then
  echo "Latest stable release did not contain a tag name" >&2
  exit 1
fi

git fetch --force "$upstream_git_url" \
  "refs/tags/${latest_tag}:refs/tags/${latest_tag}"

current_commit=$(git rev-parse "$target_branch")
release_commit=$(git rev-list -n 1 "$latest_tag")

if git merge-base --is-ancestor "$release_commit" "$current_commit"; then
  echo "${target_branch} already contains stable release ${latest_tag}"
  exit 0
fi

if ! git merge-base "$current_commit" "$release_commit" >/dev/null; then
  echo "Refusing to merge ${latest_tag}: it has no common history with ${target_branch}" >&2
  exit 1
fi

git checkout "$target_branch"
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

git merge --no-commit --no-ff "$release_commit" || true

echo "Keeping fork-owned GitHub Actions workflows"
git restore --source="$current_commit" --staged --worktree -- .github/workflows

conflicts=$(git diff --name-only --diff-filter=U)
if [[ -n "$conflicts" ]]; then
  echo "Merge conflicts require manual resolution:" >&2
  printf '%s\n' "$conflicts" >&2
  git merge --abort
  exit 1
fi

git commit -m "Merge stable release ${latest_tag}"

git push origin "$target_branch"

echo "Updated ${target_branch} to stable release ${latest_tag}"

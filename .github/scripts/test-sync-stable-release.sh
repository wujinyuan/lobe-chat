#!/usr/bin/env bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
script="$repo_root/.github/scripts/sync-stable-release.sh"
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

upstream="$test_root/upstream.git"
target="$test_root/target.git"
seed="$test_root/seed"
runner="$test_root/runner"
fake_bin="$test_root/bin"

git init --bare "$upstream" >/dev/null
git init --bare "$target" >/dev/null
git init -b main "$seed" >/dev/null
git -C "$seed" config user.name "Test"
git -C "$seed" config user.email "test@example.com"
printf 'v1\n' > "$seed/version.txt"
mkdir -p "$seed/.github/workflows"
printf 'name: original sync\n' > "$seed/.github/workflows/sync.yml"
git -C "$seed" add version.txt .github/workflows/sync.yml
git -C "$seed" commit -m v1 >/dev/null
git -C "$seed" remote add upstream "$upstream"
git -C "$seed" remote add origin "$target"
git -C "$seed" push upstream main >/dev/null
git -C "$seed" push origin main >/dev/null
base_commit=$(git -C "$seed" rev-parse HEAD)

printf 'v2\n' > "$seed/version.txt"
printf 'name: upstream sync\n' > "$seed/.github/workflows/sync.yml"
git -C "$seed" commit -am v2 >/dev/null
git -C "$seed" tag v2.0.0
git -C "$seed" push upstream main --tags >/dev/null

git -C "$seed" reset --hard "$base_commit" >/dev/null
printf 'name: fork stable sync\n' > "$seed/.github/workflows/sync.yml"
git -C "$seed" add .github/workflows/sync.yml
git -C "$seed" commit -m 'fork automation' >/dev/null
git -C "$seed" push --force origin main >/dev/null

git clone "$target" "$runner" >/dev/null
mkdir -p "$fake_bin"
cat > "$fake_bin/gh" <<'EOF'
#!/usr/bin/env bash
printf 'v2.0.0\n'
EOF
chmod +x "$fake_bin/gh"

(
  cd "$runner"
  PATH="$fake_bin:$PATH" \
    UPSTREAM_GIT_URL="$upstream" \
    "$script"
)

actual=$(git --git-dir="$target" show main:version.txt)
if [[ "$actual" != "v2" ]]; then
  echo "expected target main to contain v2, got: $actual" >&2
  exit 1
fi

fork_file=$(git --git-dir="$target" show main:.github/workflows/sync.yml)
if [[ "$fork_file" != "name: fork stable sync" ]]; then
  echo "expected target main to preserve fork automation, got: $fork_file" >&2
  exit 1
fi

printf 'sync-stable-release test passed\n'

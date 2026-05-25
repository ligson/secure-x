#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

usage() {
  cat <<'EOF'
用法:
  ./scripts/release-preflight.sh <tag>
  ./scripts/release-preflight.sh --next

说明:
  - 检查工作区是否干净
  - 检查 CHANGELOG.md 是否包含目标版本章节
  - 检查目标 tag 是否已存在于本地或远程
  - 检查当前 HEAD 是否已经包含对应版本 changelog
  - 输出建议的发版顺序
EOF
}

require_command() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "缺少命令: ${cmd}" >&2
    exit 1
  fi
}

latest_tag() {
  git tag --list 'v*' --sort=version:refname | tail -n 1
}

next_patch_tag() {
  local current
  current="$(latest_tag)"
  if [[ -z "${current}" ]]; then
    echo "v1.0.0"
    return
  fi

  local version="${current#v}"
  local major minor patch
  IFS='.' read -r major minor patch <<<"${version}"
  patch=$((patch + 1))
  printf 'v%s.%s.%s\n' "${major}" "${minor}" "${patch}"
}

resolve_tag() {
  if [[ "${1:-}" == "--next" ]]; then
    next_patch_tag
    return
  fi

  if [[ $# -ne 1 ]]; then
    usage >&2
    exit 1
  fi

  local tag="$1"
  if [[ ! "${tag}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "版本号格式不正确: ${tag}，期望形如 v1.0.7" >&2
    exit 1
  fi
  printf '%s\n' "${tag}"
}

ensure_clean_worktree() {
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "当前工作区存在未提交改动，请先提交或暂存后再发版。" >&2
    exit 1
  fi
}

ensure_changelog_heading() {
  local tag="$1"
  if ! grep -Eq "^## \\[${tag//./\\.}\\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$" CHANGELOG.md; then
    echo "CHANGELOG.md 缺少 ${tag} 对应章节，期望格式: ## [${tag}] - YYYY-MM-DD" >&2
    exit 1
  fi
}

ensure_head_contains_changelog() {
  local tag="$1"
  if ! git show HEAD:CHANGELOG.md | grep -Eq "^## \\[${tag//./\\.}\\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$"; then
    echo "当前 HEAD 尚未包含 ${tag} 的 changelog 章节，请先提交 release commit 再打 tag。" >&2
    exit 1
  fi
}

ensure_tag_absent() {
  local tag="$1"
  if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
    echo "本地 tag ${tag} 已存在，请不要重复发版或移动已有 tag。" >&2
    exit 1
  fi
  if git ls-remote --tags origin "refs/tags/${tag}" | grep -q .; then
    echo "远程 tag ${tag} 已存在，请不要重复发版或移动已有 tag。" >&2
    exit 1
  fi
}

main() {
  require_command git
  local tag
  tag="$(resolve_tag "$@")"

  ensure_clean_worktree
  ensure_changelog_heading "${tag}"
  ensure_head_contains_changelog "${tag}"
  ensure_tag_absent "${tag}"

  local head_commit
  head_commit="$(git rev-parse HEAD)"

  cat <<EOF
发版预检通过

- 目标版本: ${tag}
- 当前提交: ${head_commit}
- 当前分支: $(git branch --show-current)

建议顺序:
1. 确认当前 HEAD 就是 release commit
2. 执行: git tag ${tag}
3. 执行: git push origin main
4. 执行: git push origin ${tag}

注意:
- 不要先 push tag 再补 release commit
- 不要把已有 tag 改指向到新的提交
- 如需手工触发 GitHub Release workflow，也必须选择已经存在的正确 tag
EOF
}

main "$@"

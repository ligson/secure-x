#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

IMAGE_NAME="${IMAGE_NAME:-ligson/secure-x}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
BUILDER_NAME="${BUILDER_NAME:-}"
PUSH="${PUSH:-true}"
TAG_LATEST="${TAG_LATEST:-false}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/build-image.sh [image-tag]

Builds the Secure X backend Docker image for linux/amd64 and linux/arm64.

Environment variables:
  IMAGE_NAME    Docker image name. Default: ligson/secure-x
  PLATFORMS    Buildx platforms. Default: linux/amd64,linux/arm64
  PUSH         Push image after build. Default: true
  TAG_LATEST   Also tag and push latest. Default: false
  BUILDER_NAME Docker buildx builder name. Default: current Docker context builder

Examples:
  scripts/build-image.sh v1.0.29
  TAG_LATEST=true scripts/build-image.sh v1.0.29
  PUSH=false PLATFORMS=linux/arm64 scripts/build-image.sh dev-local
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required." >&2
  exit 1
fi

if ! docker buildx version >/dev/null 2>&1; then
  echo "docker buildx is required." >&2
  exit 1
fi

git_sha="$(git -C "${ROOT_DIR}" rev-parse --short=12 HEAD)"
image_tag="${1:-}"
if [[ -z "${image_tag}" ]]; then
  if git -C "${ROOT_DIR}" diff --quiet && git -C "${ROOT_DIR}" diff --cached --quiet; then
    image_tag="$(git -C "${ROOT_DIR}" describe --tags --exact-match --match 'v*' 2>/dev/null || true)"
  fi
fi
if [[ -z "${image_tag}" ]]; then
  image_tag="dev-${git_sha}"
fi

if [[ -z "${BUILDER_NAME}" ]]; then
  context_name="$(docker context show 2>/dev/null || true)"
  if [[ -n "${context_name}" ]] && docker buildx inspect "${context_name}" >/dev/null 2>&1; then
    BUILDER_NAME="${context_name}"
  fi
fi

if [[ -n "${BUILDER_NAME}" ]]; then
  docker buildx use "${BUILDER_NAME}"
fi

docker buildx inspect --bootstrap >/dev/null

build_args=(
  --file "${ROOT_DIR}/securex-be/Dockerfile"
  --platform "${PLATFORMS}"
  --build-arg "VERSION=${image_tag}"
  --build-arg "REVISION=${git_sha}"
  --tag "${IMAGE_NAME}:${image_tag}"
)

if [[ "${TAG_LATEST}" == "true" ]]; then
  build_args+=(--tag "${IMAGE_NAME}:latest")
fi

if [[ "${PUSH}" == "true" ]]; then
  build_args+=(--push)
else
  if [[ "${PLATFORMS}" == *","* ]]; then
    echo "PUSH=false only supports a single platform because Docker cannot load a multi-platform image into the local image store." >&2
    echo "Set PLATFORMS=linux/amd64 or PLATFORMS=linux/arm64 for local test builds." >&2
    exit 1
  fi
  build_args+=(--load)
fi

echo "Building ${IMAGE_NAME}:${image_tag}"
echo "Platforms: ${PLATFORMS}"
echo "Push: ${PUSH}"

docker buildx build "${build_args[@]}" "${ROOT_DIR}/securex-be"

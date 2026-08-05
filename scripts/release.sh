#!/usr/bin/env bash
# Release pipeline: image + Helm chart + install manifest off the exact
# vX.Y.Z tag on HEAD. Adapted from PrimeTime's scripts/release-server.sh —
# same lockstep rule (image tag = chart version = appVersion = ${TAG};
# Chart.yaml's committed version is a placeholder).
#
# The public GHCR push is normally handled by CI — the mirrored tag push
# triggers .github/workflows/release.yml, which also builds the arm64 leg
# of the manifest and attaches dist/install.yaml to a GitHub release. This
# script is the by-hand fallback for that, and the ONLY path to the
# internal gitea registry (unreachable from GitHub runners).
#
#   preflight  clean tree, HEAD at an exact vX.Y.Z tag, tools present,
#              gh token carries write:packages
#   image      docker/nerdctl build, tagged for GHCR (public) and the
#              internal gitea registry
#   chart      helm package with --version/--app-version stamped from tag
#   installer  make build-installer pinned to the release image
#   publish    image → both registries, chart → GHCR OCI, GitHub release
#              with install.yaml (skipped if CI already created it)
#
# Registries:
#   ghcr.io/sf1tzp/databasus-operator              public image
#   oci://ghcr.io/sf1tzp/charts/databasus-operator public chart
#   gitea.zen.lofi/sf1tzp/databasus-operator       internal/staging
#
# GHCR auth rides the gh CLI token; one-time setup:
#   gh auth refresh -h github.com -s write:packages,read:packages
# The internal push expects a prior `docker login gitea.zen.lofi`. The
# first push of each GHCR package creates it PRIVATE — flip it to public
# once in the package's web-UI settings (there is no API for visibility):
#   https://github.com/users/sf1tzp/packages/container/databasus-operator/settings
#   https://github.com/users/sf1tzp/packages/container/charts%2Fdatabasus-operator/settings
#
# Usage:
#   just tag 0.1.0
#   just release                # full pipeline
#   just release --no-publish   # build image + chart + installer, push nothing
#   just release --no-internal  # skip the gitea push
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GHCR_IMAGE="ghcr.io/sf1tzp/databasus-operator"
GHCR_CHARTS="oci://ghcr.io/sf1tzp/charts"
INTERNAL_IMAGE="gitea.zen.lofi/sf1tzp/databasus-operator"
CHART_DIR="$ROOT/charts/databasus-operator"

PUBLISH=1 INTERNAL=1
for arg in "$@"; do
    case "$arg" in
        --no-publish)  PUBLISH=0 ;;
        --no-internal) INTERNAL=0 ;;
        *) echo "unknown flag: $arg (supported: --no-publish --no-internal)" >&2; exit 2 ;;
    esac
done

# --- preflight ---------------------------------------------------------------
[[ -z "$(git -C "$ROOT" status --porcelain)" ]] \
    || { echo "preflight: working tree is dirty — commit or stash first" >&2; exit 1; }

TAG="$(git -C "$ROOT" describe --tags --exact-match 2>/dev/null)" \
    || { echo "preflight: HEAD carries no tag — release from an exact vX.Y.Z tag" >&2; exit 1; }
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || { echo "preflight: tag '$TAG' is not semver (vX.Y.Z)" >&2; exit 1; }
VERSION="${TAG#v}"

# docker on the Mac, nerdctl on the Linux boxes — same CLI surface for
# build/tag/login/push. Override with DOCKER=… if neither is on PATH.
DOCKER="${DOCKER:-$(command -v docker || command -v nerdctl || true)}"
[[ -n "$DOCKER" ]] \
    || { echo "preflight: neither docker nor nerdctl found (set DOCKER=…)" >&2; exit 1; }
for tool in helm gh make; do
    command -v "$tool" >/dev/null \
        || { echo "preflight: '$tool' not found" >&2; exit 1; }
done
if (( PUBLISH )); then
    gh auth status 2>&1 | grep -q "write:packages" \
        || { echo "preflight: gh token lacks write:packages —" \
                  "run: gh auth refresh -h github.com -s write:packages,read:packages" >&2; exit 1; }
fi

echo "==> releasing databasus-operator $TAG"

# --- image -------------------------------------------------------------------
# Cluster targets are amd64; CI owns the multi-arch manifest. A by-hand
# build pins the platform so a run on Apple Silicon can't silently produce
# an arm64-only image.
PLATFORM="${PLATFORM:-linux/amd64}"
"$DOCKER" build --platform "$PLATFORM" \
    -t "$GHCR_IMAGE:$TAG" -t "$GHCR_IMAGE:latest" -t "$INTERNAL_IMAGE:$TAG" \
    "$ROOT"
echo "==> built $GHCR_IMAGE:$TAG"

# --- chart -------------------------------------------------------------------
mkdir -p "$ROOT/dist"
helm package "$CHART_DIR" --version "$VERSION" --app-version "$VERSION" \
    -d "$ROOT/dist" >/dev/null
CHART_TGZ="$ROOT/dist/databasus-operator-$VERSION.tgz"
[[ -f "$CHART_TGZ" ]] || { echo "chart: expected $CHART_TGZ after helm package" >&2; exit 1; }
echo "==> packaged $CHART_TGZ"

# --- installer ---------------------------------------------------------------
# build-installer runs `kustomize edit set image` against a tracked file;
# restore it so a release leaves the tree as clean as preflight found it.
make -C "$ROOT" build-installer IMG="$GHCR_IMAGE:$TAG" >/dev/null
git -C "$ROOT" checkout --quiet config/manager/kustomization.yaml
echo "==> built dist/install.yaml (pinned to $GHCR_IMAGE:$TAG)"

# --- publish -----------------------------------------------------------------
if (( !PUBLISH )); then
    echo "==> skipping publish (--no-publish); image is tagged locally, chart + installer are in dist/"
    exit 0
fi

GH_USER="$(gh api user -q .login)"
gh auth token | "$DOCKER" login ghcr.io -u "$GH_USER" --password-stdin >/dev/null
gh auth token | helm registry login ghcr.io -u "$GH_USER" --password-stdin 2>/dev/null

"$DOCKER" push "$GHCR_IMAGE:$TAG"
"$DOCKER" push "$GHCR_IMAGE:latest"
echo "==> pushed $GHCR_IMAGE:$TAG (+latest)"

if (( INTERNAL )); then
    "$DOCKER" push "$INTERNAL_IMAGE:$TAG"
    echo "==> pushed $INTERNAL_IMAGE:$TAG"
fi

helm push "$CHART_TGZ" "$GHCR_CHARTS"
echo "==> pushed $GHCR_CHARTS/databasus-operator:$VERSION"

# CI's installer job normally creates the GitHub release; only fill the gap.
if gh release view "$TAG" --repo sf1tzp/databasus-operator >/dev/null 2>&1; then
    echo "==> GitHub release $TAG exists (CI got there first) — leaving it alone"
else
    gh release create "$TAG" "$ROOT/dist/install.yaml" \
        --repo sf1tzp/databasus-operator --title "$TAG" \
        --notes "Install: \`kubectl apply -f install.yaml\`, or \`helm install databasus-operator oci://ghcr.io/sf1tzp/charts/databasus-operator --version $VERSION\`. Check the README compatibility matrix for supported databasus versions."
    echo "==> created GitHub release $TAG with install.yaml"
fi
echo "==> if this was the first push, make the GHCR packages public (see header)"

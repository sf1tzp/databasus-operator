# Project scripts live here; Go and chart build targets stay in the
# Makefile (kubebuilder convention — lint/test/build/manifests/chart-crds).

# Accepts "1.2.3" or "v1.2.3" — any leading v is stripped before re-adding,
# so "vv1.2.3" can't happen. The final tag must match release.sh's preflight
# regex (vX.Y.Z, no prerelease/build). Fetches first (pruning tags deleted
# on the remote) and refuses to tag unless HEAD is exactly origin/main, so a
# stale checkout can't ship a release. The pushed tag mirrors to GitHub,
# where .github/workflows/release.yml publishes image + chart + install.yaml.
#
# Tag HEAD as vX.Y.Z and push it — the mirrored tag triggers the release CI.
tag version:
  #!/usr/bin/env bash
  set -euo pipefail
  v="{{version}}"
  v="${v#v}"
  [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
      || { echo "error: 'v$v' is not vX.Y.Z semver" >&2; exit 1; }
  git fetch origin --tags --prune --prune-tags
  [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] \
      || { echo "error: HEAD is not at origin/main — pull first" >&2; exit 1; }
  git tag "v$v" && git push origin "v$v"

# The GHCR side normally rides CI (.github/workflows/release.yml, triggered
# by the mirrored tag); this is the by-hand fallback and the only path to
# the internal gitea registry. Pass --no-publish to build without pushing,
# --no-internal to skip gitea.
#
# By-hand release off the tag on HEAD: image + chart + install.yaml.
release *flags:
  scripts/release.sh {{flags}}

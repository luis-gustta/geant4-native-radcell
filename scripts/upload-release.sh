#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <tag> <path-to-deb>" >&2
  echo "Example: $0 v11.4.2-1 ~/.cache/geant4-native-build/packages/geant4-native_11.4.2-1_amd64.deb" >&2
  exit 2
fi

TAG="$1"
DEB="$2"

[[ -f "$DEB" ]] || { echo "Package not found: $DEB" >&2; exit 1; }
command -v gh >/dev/null 2>&1 || { echo "GitHub CLI 'gh' is required" >&2; exit 1; }

sha256sum "$DEB" | tee "${DEB}.sha256"

gh release create "$TAG" "$DEB" "${DEB}.sha256"   --title "Geant4 native package ${TAG}"   --notes "Native Geant4 Debian package built with install_geant4_native.sh. Install with: sudo apt install ./$(basename "$DEB")"

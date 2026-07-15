#!/bin/bash
set -euo pipefail

# Bumps pubspec.yaml version using a base-10 odometer rule.
# Name is the source of truth; build number = major*100 + minor*10 + patch.
#   1.0.4+104 -> 1.0.5+105
#   1.0.9+109 -> 1.1.0+110
#   1.9.9+199 -> 2.0.0+200
# ponytail: assumes single-digit minor/patch (0-9), the documented scheme.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PUBSPEC="$SCRIPT_DIR/pubspec.yaml"

if [[ ! -f "$PUBSPEC" ]]; then
  echo "Error: pubspec.yaml not found at $PUBSPEC" >&2
  exit 1
fi

CURRENT=$(grep -E '^version:' "$PUBSPEC" | head -1 | sed -E 's/^version:[[:space:]]*//')
if [[ -z "$CURRENT" ]]; then
  echo "Error: no 'version:' line in pubspec.yaml" >&2
  exit 1
fi

NAME=${CURRENT%%+*}
IFS='.' read -r MAJ MIN PAT <<< "$NAME"

if ! [[ "$MAJ" =~ ^[0-9]+$ && "$MIN" =~ ^[0-9]+$ && "$PAT" =~ ^[0-9]+$ ]]; then
  echo "Error: cannot parse semver from '$CURRENT'" >&2
  exit 1
fi

if (( MIN > 9 || PAT > 9 )); then
  echo "Error: scheme supports single-digit minor/patch only (got $NAME)" >&2
  exit 1
fi

PAT=$((PAT + 1))
if (( PAT > 9 )); then PAT=0; MIN=$((MIN + 1)); fi
if (( MIN > 9 )); then MIN=0; MAJ=$((MAJ + 1)); fi

BUILD=$((MAJ * 100 + MIN * 10 + PAT))
NEW="${MAJ}.${MIN}.${PAT}+${BUILD}"

sed -i.bak "s/^version:.*/version: ${NEW}/" "$PUBSPEC" && rm -f "$PUBSPEC.bak"

echo "bump ${CURRENT} -> ${NEW}"

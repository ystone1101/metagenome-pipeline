#!/bin/bash
#================================================
# Build all Dokkaebi pipeline tool images.
# Run from the repository root:
#   bash docker/build-all.sh [tag]
#================================================
set -euo pipefail

TAG="${1:-latest}"
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
REPO_ROOT=$(dirname "$SCRIPT_DIR")

TOOLS=(kneaddata fastp kraken bbmap megahit metawrap gtdbtk bakta eggnog)

cd "$REPO_ROOT"

for tool in "${TOOLS[@]}"; do
    echo "=================================================="
    echo "Building dokkaebi/${tool}:${TAG}"
    echo "=================================================="
    docker build -f "docker/${tool}/Dockerfile" -t "dokkaebi/${tool}:${TAG}" .
done

echo ""
echo "All images built successfully:"
for tool in "${TOOLS[@]}"; do
    echo "  dokkaebi/${tool}:${TAG}"
done

#!/bin/sh
set -eu
cd "$CI_PRIMARY_REPOSITORY_PATH"
./scripts/fetch-vlckit.sh
if ! command -v xcodegen >/dev/null 2>&1; then
    HOMEBREW_NO_AUTO_UPDATE=1 brew install xcodegen
fi
xcodegen generate

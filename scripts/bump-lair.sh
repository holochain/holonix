#!/usr/bin/env bash

# Bump script to update the Lair version in flake.nix
# Usage: ./scripts/bump-lair.sh [apply] [force-version]
#
# The force-version and apply arguments are only for testing. The force-version can be set to any value and the apply
# argument can be set to false to prevent modifications to the flake.nix file.
#
# Method:
# - Holochain exposes the required Lair version in its build-info. The script runs the current Holochain version
#   provided by the flake.nix's default shell and extracts the Lair version.
# - If force-version is provided, the script uses that version instead of the one extracted from the build-info.
# - Checks whether the Lair version is already set in the flake.nix and if so, provide a message and exit.
# - If apply is not provided, or is true: Updates the flake.nix file to use the latest matching tag.
# - If apply is provided as false: Prints the tag that would have been used to update the flake.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

if [ ! -f "./flake.nix" ]; then
    echo "File not found: ./flake.nix"
    exit 1
fi

lair_version=${2:-$(nix shell nixpkgs#jq --command nix develop --command holochain --build-info | jq -r ".lair_keystore_version_req")}

echo "Holochain depends on Lair version: $lair_version"

if grep -q "github:holochain/lair/lair_keystore-v${lair_version}" ./flake.nix; then
    echo "Lair version is already up to date"
    exit 0
fi

APPLY=${1:-true}
if [ "$APPLY" == "true" ]; then
    sed --in-place "s#url = \"github:holochain/lair/.*\";#url = \"github:holochain/lair/lair_keystore-v${lair_version}\";#" ./flake.nix
    nix flake update lair_keystore
else
    printf "Would have updated flake.nix to use: \nlair_keystore-v%s\n" "$lair_version"
fi

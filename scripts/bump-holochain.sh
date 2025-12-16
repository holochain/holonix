#!/usr/bin/env bash

# Bump script to update the Holochain version in flake.nix
# Usage: ./scripts/bump-holochain.sh [branch] [apply]
#
# The branch and apply arguments are only for testing. The branch can be set to any branch which would be expected to
# exist in this repository and the apply argument can be set to false to prevent modifications to the flake.nix file.
#
# Method:
# - Uses the current branch to work out what version of Holochain to look for.
# - Picks a search pattern for a Holochain tag based on the branch.
# - Searches for all Holochain tags and filters them by the search pattern.
# - Picks the latest matching tag.
# - If apply is not provided, or is true: Updates the flake.nix file to use the latest matching tag.
# - If apply is not provided, or is true: Updates the flake lock to match the new flake.nix file.
# - If apply is false: Prints the tag that would have been used to update the flake.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

if [ ! -f "./flake.nix" ]; then
    echo "File not found: ./flake.nix"
    exit 1
fi

CURRENT_BRANCH=${1:-$(git branch --show-current)}

SEARCH_PATTERN="no-tag"
case $CURRENT_BRANCH in
    main)
        SEARCH_PATTERN="^holochain-0.[0-9]+.[0-9]+-(dev|rc).[0-9]+$"
        ;;
    main-*)
        VERSION_STR=$(echo "$CURRENT_BRANCH" | awk -F '-' '{print $2}')

        # Protect against this code trying to bump 1.2.3 versions if one of those shows up.
        SEP_COUNT=$(echo "$VERSION_STR" | tr -d -c '.' | awk '{ print length; }')
        if [ "$SEP_COUNT" -ne "1" ]; then
            echo "Invalid version format: $VERSION_STR"
            exit 1
        fi

        SEARCH_PATTERN=$(echo "$VERSION_STR" | awk -F '.' 'BEGIN { OFS="" } {print "^holochain-", $1, ".", $2, ".[0-9]+$"}')
        ;;
    *)
        echo "Not on branch \`main\` or \`main-X.Y\`, skipping for branch \`${CURRENT_BRANCH}\`"
        exit 0
        ;;
esac

echo "Looking for tags matching pattern: $SEARCH_PATTERN"

ALL_HOLOCHAIN_TAGS=$(git -c 'versionsort.suffix=-dev' -c 'versionsort.suffix=-rc' ls-remote -q --tags --sort='v:refname' https://github.com/holochain/holochain.git holochain-* | cut --delimiter='/' --fields=3)
LATEST_MATCHING_TAG=$(echo "$ALL_HOLOCHAIN_TAGS" | { grep -E "$SEARCH_PATTERN" || true; } | tail -n 1)

if [ -z "$LATEST_MATCHING_TAG" ]; then
    echo "No matching tags found on \`$CURRENT_BRANCH\` for pattern: $SEARCH_PATTERN"
    exit 1
fi

echo "Latest matching tag: $LATEST_MATCHING_TAG"

APPLY=${2:-true}
if [ "$APPLY" == "true" ]; then
    sed --in-place "s#url = \"github:holochain/holochain?ref=.*\";#url = \"github:holochain/holochain?ref=${LATEST_MATCHING_TAG}\";#" ./flake.nix
    nix flake update holochain
else
    printf "Would have updated flake.nix to use: \n%s\n" "$LATEST_MATCHING_TAG"
fi

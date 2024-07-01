#!/usr/bin/env bash

set -eu

if ! (
        (git config --global user.email && git config --global user.name) ||
        (git config --local user.email && git config --local user.name)
    ); then
    git config --local user.email "hra+gh@holochain.org"
    git config --local user.name "Holochain Release Automation"
fi

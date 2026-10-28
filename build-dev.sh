#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
CHATLEDGER_APP_OUTPUT="$PWD/dist/轻随-0.7.0-开发版.app" CHATLEDGER_BUNDLE_ID="local.binbin.chatledger.development070" zsh build.sh

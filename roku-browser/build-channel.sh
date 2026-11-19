#!/usr/bin/env bash
# Packages the Roku channel into tv-browser-roku.zip for sideloading.
set -euo pipefail
cd "$(dirname "$0")/roku-channel"
rm -f ../tv-browser-roku.zip
zip -r -X ../tv-browser-roku.zip manifest source components images >/dev/null
echo "Built $(cd .. && pwd)/tv-browser-roku.zip"

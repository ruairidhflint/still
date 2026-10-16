#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if [[ ! -d dist/Still.app ]]; then zsh scripts/build.sh; fi
open dist/Still.app

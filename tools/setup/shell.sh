#!/bin/bash
# The shell for every make recipe: bash with -e -u -o pipefail. A wrapper (not .SHELLFLAGS) because macOS ships
# GNU make 3.81, which ignores .SHELLFLAGS. make calls this as: shell.sh -c '<recipe line>'.
exec /bin/bash -eu -o pipefail "$@"

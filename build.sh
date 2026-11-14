#!/bin/sh
# Build SCLOCK.ACC (Simple Clock 1.0) from SCLOCK.S with vasm.
# Rick Grinstead 2026
# Needs vasm built for 68k with Motorola syntax (vasmm68k_mot):
#   Arch: install it from the AUR, or build from source with
#         make CPU=m68k SYNTAX=mot
#
# Usage: ./build.sh            (run from the folder holding SCLOCK.S)
#        VASM=/path/to/vasmm68k_mot ./build.sh

set -e
cd "$(dirname "$0")"

VASM=${VASM:-vasmm68k_mot}
SRC=SCLOCK.S
OUT=SCLOCK.ACC

if ! command -v "$VASM" >/dev/null 2>&1; then
    echo "error: '$VASM' not found. Install vasm or set VASM=/path/to/vasmm68k_mot" >&2
    exit 1
fi

if [ ! -f "$SRC" ]; then
    echo "error: $SRC not found in $(pwd)" >&2
    exit 1
fi

"$VASM" -Ftos -devpac -nosym -quiet -o "$OUT" "$SRC"

echo "Built $OUT ($(wc -c < "$OUT") bytes)."
echo "Copy it to the root of your boot drive and reboot."

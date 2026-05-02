#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

RBF="$PROJECT_DIR/src/fpga/build/output_files/ap_core_analogizer.rbf"
RBF_R="$PROJECT_DIR/pkg/Cores/Orbitoid.GBA_Analogizer/bitstream.rbf_r"
PACKAGE="$PROJECT_DIR/build_output/Orbitoid.GBA_Analogizer-dev.zip"

mkdir -p "$(dirname "$RBF_R")" "$PROJECT_DIR/build_output/reports"

echo "=== Starting Analogizer Quartus build via Docker ==="
docker run --rm \
  -v "$PROJECT_DIR":/build \
  -w /build \
  raetro/quartus:21.1 \
  quartus_sh -t generate_analogizer.tcl

echo ""
echo "=== Build complete, reversing bitstream ==="
python3 "$SCRIPT_DIR/reverse_bitstream.py" "$RBF" "$RBF_R"

echo ""
"$SCRIPT_DIR/print_timing.sh" \
  "$PROJECT_DIR/src/fpga/build/output_files/ap_core_analogizer.sta.summary" \
  "$PROJECT_DIR/build_output/reports/ap_core_analogizer.sta.clock_summary.rpt"

echo ""
if command -v zip >/dev/null 2>&1; then
  echo "=== Packaging SD card layout ==="
  rm -f "$PACKAGE"
  (
    cd "$PROJECT_DIR/pkg"
    zip -r "$PACKAGE" Assets Platforms instructions.txt Cores/Orbitoid.GBA_Analogizer
  )
  echo "Package: $PACKAGE"
else
  echo "zip not found; skipping package archive. Copy pkg/Cores, pkg/Platforms, and pkg/Assets to your SD card manually."
fi

echo "=== Done! ==="
echo "Bitstream: $RBF_R"

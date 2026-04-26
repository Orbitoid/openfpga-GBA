#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

RBF="$PROJECT_DIR/src/fpga/build/output_files/ap_core_analogizer.rbf"
RBF_R="$PROJECT_DIR/pkg/Cores/mincer_ray.GBA_Analogizer/bitstream.rbf_r"

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
  "$PROJECT_DIR/build_output/reports/ap_core.sta.clock_summary.rpt"

echo "=== Done! ==="
echo "Bitstream: $RBF_R"

# ---- Auto-copy to SD card ----
# Looks for any /media/orbit/<folder>/Cores/mincer_ray.GBA_Analogizer/ directory.
SD_CORE=""
for dir in /media/orbit/*/; do
    if [ -d "${dir}Cores/mincer_ray.GBA_Analogizer" ]; then
        SD_CORE="${dir}Cores/mincer_ray.GBA_Analogizer"
        break
    fi
done

if [ -n "$SD_CORE" ]; then
    echo ""
    echo "=== Copying to SD card: $SD_CORE ==="
    cp "$RBF_R"                                    "$SD_CORE/bitstream.rbf_r"
    cp "$PROJECT_DIR/pkg/Cores/mincer_ray.GBA_Analogizer/interact.json" "$SD_CORE/interact.json"
    echo "Copied bitstream.rbf_r and interact.json"
else
    echo ""
    echo "(SD card not found — skipping copy)"
fi

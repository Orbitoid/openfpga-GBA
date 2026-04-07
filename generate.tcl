package require ::quartus::project
package require ::quartus::flow

project_open -revision ap_core src/fpga/build/gba_pocket.qpf
set_global_assignment -name NUM_PARALLEL_PROCESSORS 4
execute_flow -compile
project_close

# Run custom STA report for detailed timing path analysis.
# Uses -t (standalone script mode) instead of --report_script for reliability.
# The script opens the project, creates the timing netlist, generates reports,
# and cleans up on its own.
file mkdir build_output/reports
post_message "Running custom STA report..."
if {[catch {qexec "quartus_sta -t scripts/sta_custom_report.tcl"} result]} {
    post_message -type warning "Custom STA report failed: $result"
} else {
    post_message "Custom STA completed successfully."
}

# Verify reports were generated
foreach f {build_output/reports/ap_core.sta.paths_setup.rpt
           build_output/reports/ap_core.sta.paths_hold.rpt
           build_output/reports/ap_core.sta.clock_summary.rpt} {
    if {[file exists $f]} {
        post_message "Report OK: $f"
    } else {
        post_message -type warning "Report MISSING: $f"
    }
}

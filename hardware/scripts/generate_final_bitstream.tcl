# generate_final_bitstream.tcl
open_project picorv32_bootloader/picorv32_bootloader_proj/picorv32_bootloader.xpr

# Reset previous synthesis and implementation to ensure all updated hex and verilog files are incorporated
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

set bitfile [glob -nocomplain picorv32_bootloader/picorv32_bootloader_proj/picorv32_bootloader.runs/impl_1/top.bit]
if {[file exists $bitfile]} {
    puts "================================================================="
    puts ">>> SUCCESS: Final Bitstream Generated Successfully! <<<"
    puts ">>> Location: $bitfile"
    puts "================================================================="
} else {
    puts "================================================================="
    puts ">>> ERROR: Bitstream generation did not produce top.bit <<<"
    puts "================================================================="
}
exit

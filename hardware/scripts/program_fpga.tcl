# program_fpga.tcl
open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target

set device [get_hw_devices xc7s50_0]
if {[llength $device] == 0} {
    set device [lindex [get_hw_devices] 0]
}

puts "Detected Target Device: $device"
current_hw_device $device
refresh_hw_device -update_hw_probes false $device

set bitfile "picorv32_bootloader/picorv32_bootloader_proj/picorv32_bootloader.runs/impl_1/top.bit"
set_property PROGRAM.FILE $bitfile $device

puts "Programming FPGA device with $bitfile..."
program_hw_devices $device
refresh_hw_device $device

puts "================================================================="
puts ">>> SUCCESS: Spartan-7 FPGA Successfully Programmed! <<<"
puts "================================================================="
exit

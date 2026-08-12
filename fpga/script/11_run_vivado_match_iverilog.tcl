set repo_root [file normalize "D:/Design_SoC_RISCV_ASCON H3/fpga"]
set script_dir [file normalize [file dirname [info script]]]
set src_dir    [file normalize "$repo_root/src"]
set tb_file    [file normalize "$repo_root/tb/tb_freertos_kernel_smoke.v"]
set hex_file   [file normalize "$repo_root/os/firmware/test_freertos_kernel_smoke.hex"]
set filelist   [file normalize "$script_dir/rtl_sources.f"]

if {[current_project -quiet] eq ""} {
    error "No Vivado project is open. Open a project first, then source this TCL."
}

foreach f [list $tb_file $hex_file $filelist] {
    if {![file exists $f]} {
        error "Required file not found: $f"
    }
}

proc reset_fileset_if_present {fileset_name} {
    set fs [get_filesets -quiet $fileset_name]
    if {$fs eq ""} {
        return
    }

    set fs_files [get_files -quiet -of_objects $fs]
    if {[llength $fs_files] > 0} {
        remove_files -fileset $fileset_name $fs_files
    }
}

proc read_filelist {filelist_path script_dir} {
    set fh [open $filelist_path r]
    set raw [split [read $fh] "\n"]
    close $fh

    set result {}
    foreach line $raw {
        set item [string trim $line]
        if {$item eq ""} {
            continue
        }
        if {[string match "#*" $item]} {
            continue
        }

        if {[file pathtype $item] eq "absolute"} {
            lappend result [file normalize $item]
        } else {
            lappend result [file normalize [file join $script_dir $item]]
        }
    }
    return $result
}

set rtl_files [read_filelist $filelist $script_dir]
foreach f $rtl_files {
    if {![file exists $f]} {
        error "RTL file from rtl_sources.f not found: $f"
    }
}

puts "==============================================================="
puts " Vivado one-shot simulation setup"
puts "==============================================================="
puts " Project : [current_project]"
puts " Filelist: $filelist"
puts " TB      : $tb_file"
puts " HEX     : $hex_file"
puts "==============================================================="

catch {close_sim}

reset_fileset_if_present sources_1
reset_fileset_if_present sim_1

add_files -fileset sources_1 -norecurse $rtl_files
add_files -fileset sim_1 -norecurse [list $tb_file]
add_files -fileset sim_1 -norecurse [list $hex_file]

set hex_obj [get_files -quiet $hex_file]
if {$hex_obj ne ""} {
    set_property file_type {Memory Initialization Files} $hex_obj
    set_property used_in_simulation true $hex_obj
    set_property used_in_synthesis false $hex_obj
}

set_property include_dirs [list $src_dir] [get_filesets sources_1]
set_property include_dirs [list $src_dir] [get_filesets sim_1]
set_property top fpga_top [get_filesets sources_1]
set_property top run_soc [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sources_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]
set_property verilog_define {BAUD_DIV=16 LOG_LEVEL=0 FINISH_ON_PASS} [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

launch_simulation
restart
run all

puts "==============================================================="
puts " Vivado simulation command sequence finished"
puts " Check the transcript for: \\[PASS\\] freertos_kernel_smoke"
puts "==============================================================="

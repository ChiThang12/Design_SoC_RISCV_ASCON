# Cadence Genus(TM) Synthesis Solution, Version 23.10-p004_1, built Feb  1 2024 13:43:46

# Date: Fri Feb 13 20:06:54 2026
# Host: vku-truongsa (x86_64 w/Linux 3.10.0-1160.119.1.el7.x86_64) (4cores*24cpus*6physical cpus*Intel(R) Xeon(R) CPU E5-2667 v2 @ 3.30GHz 25600KB)
# OS:   CentOS Linux release 7.9.2009 (Core)

read_db ./outputs/inst_mem_innovus/
get_db inst.name
get_db insts .name
get_db insts .area
get_db insts .name
get_db insts .is_macro
get_db insts -if {.name == u_ram_macro g1242__2398 g1243__5107}
get_db insts -if {.name == *macro*}
set_db [get_db insts -if {.name == *macro*}] .is_macro true
get_db [get_db insts -if {.name == *macro*}] .area
exit

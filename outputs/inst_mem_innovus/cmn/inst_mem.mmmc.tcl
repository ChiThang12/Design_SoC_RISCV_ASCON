#################################################################################
#
# Created by Genus(TM) Synthesis Solution 23.10-p004_1 on Fri Feb 13 19:56:27 +07 2026
#
#################################################################################

## library_sets
create_library_set -name ls_of_ld_slow \
    -timing { /home/ducnm.23ce/Documents/SoC_RISCV/Design_SoC_RISCV_ASCON/libraries/lib/slow/RM_IHPSG13_2P_1024x32_c2_bm_bist_slow_1p08V_125C.lib \
              /home/ducnm.23ce/Documents/SoC_RISCV/Design_SoC_RISCV_ASCON/libraries/lib/slow/sg13g2_io_slow_1p08V_3p0V_125C.lib \
              /home/ducnm.23ce/Documents/SoC_RISCV/Design_SoC_RISCV_ASCON/libraries/lib/slow/sg13g2_io_slow_1p35V_3p0V_125C.lib \
              /home/ducnm.23ce/Documents/SoC_RISCV/Design_SoC_RISCV_ASCON/libraries/lib/slow/sg13g2_stdcell_slow_1p08V_125C.lib \
              /home/ducnm.23ce/Documents/SoC_RISCV/Design_SoC_RISCV_ASCON/libraries/lib/slow/sg13g2_stdcell_slow_1p35V_125C.lib }
create_library_set -name ls_of_ld_typ \
    -timing { /home/ducnm.23ce/Documents/SoC_RISCV/Design_SoC_RISCV_ASCON/libraries/lib/typ/RM_IHPSG13_2P_1024x32_c2_bm_bist_typ_1p20V_25C.lib \
              /home/ducnm.23ce/Documents/SoC_RISCV/Design_SoC_RISCV_ASCON/libraries/lib/typ/sg13g2_io_typ_1p2V_3p3V_25C.lib \
              /home/ducnm.23ce/Documents/SoC_RISCV/Design_SoC_RISCV_ASCON/libraries/lib/typ/sg13g2_io_typ_1p5V_3p3V_25C.lib \
              /home/ducnm.23ce/Documents/SoC_RISCV/Design_SoC_RISCV_ASCON/libraries/lib/typ/sg13g2_stdcell_typ_1p20V_25C.lib \
              /home/ducnm.23ce/Documents/SoC_RISCV/Design_SoC_RISCV_ASCON/libraries/lib/typ/sg13g2_stdcell_typ_1p50V_25C.lib }
create_library_set -name ls_of_ld_fast \
    -timing { /home/ducnm.23ce/Documents/SoC_RISCV/Design_SoC_RISCV_ASCON/libraries/lib/fast/RM_IHPSG13_2P_1024x32_c2_bm_bist_fast_1p32V_m55C.lib \
              /home/ducnm.23ce/Documents/SoC_RISCV/Design_SoC_RISCV_ASCON/libraries/lib/fast/sg13g2_io_fast_1p32V_3p6V_m40C.lib \
              /home/ducnm.23ce/Documents/SoC_RISCV/Design_SoC_RISCV_ASCON/libraries/lib/fast/sg13g2_io_fast_1p65V_3p6V_m40C.lib \
              /home/ducnm.23ce/Documents/SoC_RISCV/Design_SoC_RISCV_ASCON/libraries/lib/fast/sg13g2_stdcell_fast_1p32V_m40C.lib \
              /home/ducnm.23ce/Documents/SoC_RISCV/Design_SoC_RISCV_ASCON/libraries/lib/fast/sg13g2_stdcell_fast_1p65V_m40C.lib }

## rc_corner
create_rc_corner -name default_emulate_rc_corner \
    -T 125.0 \
    -preRoute_res 1.0 \
    -preRoute_cap 1.0 \
    -preRoute_clkres 0.0 \
    -preRoute_clkcap 0.0 \
    -postRoute_res {1.0 1.0 1.0} \
    -postRoute_cap {1.0 1.0 1.0} \
    -postRoute_xcap {1.0 1.0 1.0} \
    -postRoute_clkres {1.0 1.0 1.0} \
    -postRoute_clkcap {1.0 1.0 1.0} \
    -postRoute_clkxcap {1.0 1.0 1.0}

## delay_corner
create_delay_corner -name default_emulate_delay_corner \
    -early_library_set { ls_of_ld_slow } \
    -late_library_set { ls_of_ld_slow } \
    -early_rc_corner default_emulate_rc_corner \
    -late_rc_corner default_emulate_rc_corner
create_delay_corner -name default_emulate_power_delay_corner \
    -early_library_set { ls_of_ld_fast } \
    -late_library_set { ls_of_ld_fast } \
    -early_rc_corner default_emulate_rc_corner \
    -late_rc_corner default_emulate_rc_corner

## constraint_mode
create_constraint_mode -name default_emulate_constraint_mode \
    -sdc_files { outputs/inst_mem_innovus/cmn/inst_mem.mmmc/modes/default_emulate_constraint_mode/default_emulate_constraint_mode.sdc.gz }

## analysis_view
create_analysis_view -name default_emulate_view \
    -constraint_mode default_emulate_constraint_mode \
    -delay_corner default_emulate_delay_corner
create_analysis_view -name default_emulate_power_view \
    -constraint_mode default_emulate_constraint_mode \
    -delay_corner default_emulate_power_delay_corner

## set_analysis_view
set_analysis_view -setup { default_emulate_view } \
                  -hold { default_emulate_view } \
                  -leakage default_emulate_power_view \
                  -dynamic default_emulate_power_view

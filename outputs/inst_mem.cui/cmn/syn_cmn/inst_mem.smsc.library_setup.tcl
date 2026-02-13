################################################################################
#
# Genus(TM) Synthesis Solution setup file
# Created by Genus(TM) Synthesis Solution 23.10-p004_1
#   on 02/13/2026 19:36:11
#
#
################################################################################


# This script is intended for use with Genus(TM) Synthesis Solution version 23.10-p004_1


# To allow user-readonly attributes
################################################################################
::legacy::set_attribute -quiet force_tui_is_remote 1 /


# Libraries
################################################################################
create_library_domain {slow typ fast}
::legacy::set_attribute library {/home/ducnm.23ce/Documents/SoC_RISCV/Design_SoC_RISCV_ASCON/libraries/lib/slow/RM_IHPSG13_2P_1024x32_c2_bm_bist_slow_1p08V_125C.lib /home/ducnm.23ce/Documents/SoC_RISCV/Design_SoC_RISCV_ASCON/libraries/lib/slow/sg13g2_io_slow_1p08V_3p0V_125C.lib /home/ducnm.23ce/Documents/SoC_RISCV/Design_SoC_RISCV_ASCON/libraries/lib/slow/sg13g2_io_slow_1p35V_3p0V_125C.lib /home/ducnm.23ce/Documents/SoC_RISCV/Design_SoC_RISCV_ASCON/libraries/lib/slow/sg13g2_stdcell_slow_1p08V_125C.lib /home/ducnm.23ce/Documents/SoC_RISCV/Design_SoC_RISCV_ASCON/libraries/lib/slow/sg13g2_stdcell_slow_1p35V_125C.lib} slow
::legacy::set_attribute library {/home/ducnm.23ce/Documents/SoC_RISCV/Design_SoC_RISCV_ASCON/libraries/lib/typ/RM_IHPSG13_2P_1024x32_c2_bm_bist_typ_1p20V_25C.lib /home/ducnm.23ce/Documents/SoC_RISCV/Design_SoC_RISCV_ASCON/libraries/lib/typ/sg13g2_io_typ_1p2V_3p3V_25C.lib /home/ducnm.23ce/Documents/SoC_RISCV/Design_SoC_RISCV_ASCON/libraries/lib/typ/sg13g2_io_typ_1p5V_3p3V_25C.lib /home/ducnm.23ce/Documents/SoC_RISCV/Design_SoC_RISCV_ASCON/libraries/lib/typ/sg13g2_stdcell_typ_1p20V_25C.lib /home/ducnm.23ce/Documents/SoC_RISCV/Design_SoC_RISCV_ASCON/libraries/lib/typ/sg13g2_stdcell_typ_1p50V_25C.lib} typ
::legacy::set_attribute library {/home/ducnm.23ce/Documents/SoC_RISCV/Design_SoC_RISCV_ASCON/libraries/lib/fast/RM_IHPSG13_2P_1024x32_c2_bm_bist_fast_1p32V_m55C.lib /home/ducnm.23ce/Documents/SoC_RISCV/Design_SoC_RISCV_ASCON/libraries/lib/fast/sg13g2_io_fast_1p32V_3p6V_m40C.lib /home/ducnm.23ce/Documents/SoC_RISCV/Design_SoC_RISCV_ASCON/libraries/lib/fast/sg13g2_io_fast_1p65V_3p6V_m40C.lib /home/ducnm.23ce/Documents/SoC_RISCV/Design_SoC_RISCV_ASCON/libraries/lib/fast/sg13g2_stdcell_fast_1p32V_m40C.lib /home/ducnm.23ce/Documents/SoC_RISCV/Design_SoC_RISCV_ASCON/libraries/lib/fast/sg13g2_stdcell_fast_1p65V_m40C.lib} fast
::legacy::set_attribute -quiet default true slow
::legacy::set_attribute -quiet wireload_selection /libraries/library_domains/slow/sg13g2_io_slow_1p08V_3p0V_125C/wireload_selections/4_metls_routing slow
::legacy::set_attribute -quiet power_library {/libraries/library_domains/fast} slow
::legacy::set_attribute -quiet wireload_selection /libraries/library_domains/typ/sg13g2_io_typ_1p2V_3p3V_25C/wireload_selections/4_metls_routing typ
::legacy::set_attribute -quiet wireload_selection /libraries/library_domains/fast/sg13g2_io_fast_1p32V_3p6V_m40C/wireload_selections/4_metls_routing fast


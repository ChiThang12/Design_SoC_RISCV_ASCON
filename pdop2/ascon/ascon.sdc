# =========================================================
# File: ascon.sdc
# Purpose: Timing constraints for OpenLane / Sky130
# =========================================================

# ================= CLOCK DEFINITION =====================
# Clock on top-level port 'clk' với period 10ns
create_clock -name clk -period 10.0 [get_ports clk]

# Duty cycle 50%
set_clock_uncertainty 0.1 [get_clocks clk]

# ================= INPUT / OUTPUT DELAY =================
# Giả sử input đến trễ 2ns từ bên ngoài
set_input_delay 2.0 -clock clk [all_inputs]

# Giả sử output cần ổn định sau 2ns
set_output_delay 2.0 -clock clk [all_outputs]

# Loại trừ clock khỏi input/output delay
set_input_delay 0 -clock clk [get_ports clk]

# ================= LOAD & DRIVE ========================
# Mô phỏng tải output
set_load 0.1 [all_outputs]

# Chỉ định driving cell cho input
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 [all_inputs]

# ================= FALSE PATH / MULTICYCLE =============
# Ví dụ reset async, nếu có
# set_false_path -from [get_ports rst]

# ================= COMMENTS ============================
# - Không dùng /Y với driving cell
# - Chỉ định đúng cell trong thư viện Sky130
# - Tweak input_delay, output_delay, load theo thiết kế cụ thể
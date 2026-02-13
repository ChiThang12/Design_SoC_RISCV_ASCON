# 1. Định nghĩa đơn vị thời gian (thường mặc định là ns trong thư viện)
# set_units -time ns

# 2. Tạo Clock (100MHz -> Period = 10ns)
create_clock -name VCLK -period 10 [get_ports clk]

# 3. Thiết lập Design Rule Constraints
set_max_transition 0.2 [current_design]
set_clock_uncertainty 0.1 [get_clocks VCLK]

# 4. Thiết lập Input Delay
# Giả định dữ liệu từ PC và Burst Req đến từ các Flip-Flop bên ngoài SoC
# Max delay thường chiếm 40-60% chu kỳ để dành phần còn lại cho logic nội bộ
set_input_delay -max 4.0 -clock VCLK [remove_from_collection [all_inputs] {clk rst_n}]
set_input_delay -min 0.5 -clock VCLK [remove_from_collection [all_inputs] {clk rst_n}]

# 5. Thiết lập Output Delay
# Output phải sẵn sàng cho tầng tiếp theo (Instruction Decoder / AXI Bus)
set_output_delay -max 4.0 -clock VCLK [all_outputs]
set_output_delay -min 0.5 -clock VCLK [all_outputs]

# 6. False Path
# Reset thường là tín hiệu bất đối xứng (asynchronous), có thể set false path 
# để Genus không mất thời gian tối ưu timing phục hồi (recovery/removal) nếu hệ thống cho phép
set_false_path -from [get_ports rst_n]

# 7. Case Analysis (Tùy chọn)
# Vì bạn không dùng tính năng BIST trong synthesis, ta nên ép các chân BIST về 0 
# để Genus tối ưu hóa bằng cách loại bỏ logic liên quan.
set_case_analysis 0 [get_pins u_ram_macro/*BIST*EN]



group_path -name reg2reg  -from [all_registers] -to [all_registers]
group_path -name in2reg   -from [all_inputs]    -to [all_registers]
group_path -name reg2out  -from [all_registers] -to [all_outputs]
group_path -name in2out   -from [all_inputs]    -to [all_outputs]

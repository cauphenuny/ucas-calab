create_project -force loongson ./project -part xc7a200tfbg676-1

# Add conventional sources
add_files -scan_for_includes [glob -nocomplain ../rtl/*.v]
add_files -scan_for_includes [glob -nocomplain ../rtl/*/*.v]

# Add IPs
add_files -quiet [glob -nocomplain ../rtl/xilinx_ip/*/*.xci]

# 创建无符号除法器
create_ip -name div_gen -vendor xilinx.com -library ip -version 5.1 -module_name udiv
set_property -dict [list \
    CONFIG.algorithm_type {Radix2} \
    CONFIG.operand_sign {Unsigned} \
    CONFIG.dividend_and_quotient_width {32} \
    CONFIG.divisor_width {32} \
    CONFIG.remainder_type {Remainder} \
    CONFIG.clocks_per_division {8} \
    CONFIG.FlowControl {NonBlocking} \
] [get_ips udiv]
generate_target all [get_ips udiv]

# 创建有符号除法器
create_ip -name div_gen -vendor xilinx.com -library ip -version 5.1 -module_name sdiv
set_property -dict [list \
    CONFIG.algorithm_type {Radix2} \
    CONFIG.operand_sign {Signed} \
    CONFIG.dividend_and_quotient_width {32} \
    CONFIG.divisor_width {32} \
    CONFIG.remainder_type {Remainder} \
    CONFIG.clocks_per_division {8} \
    CONFIG.FlowControl {NonBlocking} \
] [get_ips sdiv]
generate_target all [get_ips sdiv]

# Add simulation files
add_files -fileset sim_1 ../testbench

# Add myCPU
add_files -quiet -scan_for_includes ../../../myCPU

# Add constraints
add_files -fileset constrs_1 -quiet ./constraints

set_property -name "top" -value "tb_top" -objects  [get_filesets sim_1]
set_property -name "xsim.simulate.log_all_signals" -value "1" -objects [get_filesets sim_1]

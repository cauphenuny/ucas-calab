# 定义颜色变量（加粗）
set COLOR_RED "\033\[1;31m"
set COLOR_GREEN "\033\[1;32m"
set COLOR_YELLOW "\033\[1;33m"
set COLOR_BLUE "\033\[1;34m"
set COLOR_RESET "\033\[0m"

# 错误处理函数
proc error_exit {msg} {
    global COLOR_RED COLOR_RESET
    puts "${COLOR_RED}ERROR: $msg${COLOR_RESET}"
    close_project
    exit 1
}

# 检查源文件是否存在
if {![file exists "create_project.tcl"]} {
    puts "${COLOR_RED}ERROR: create_project.tcl not found${COLOR_RESET}"
    exit 1
}

# 创建项目
puts "${COLOR_GREEN}INFO: Creating project...${COLOR_RESET}"
if {[catch {source create_project.tcl} result]} {
    puts "${COLOR_RED}ERROR: Failed to create project: $result${COLOR_RESET}"
    exit 1
}

puts "${COLOR_GREEN}INFO: Starting synthesis...${COLOR_RESET}"
launch_runs synth_1 -jobs 10
wait_on_run synth_1

# 检查综合是否成功
set synth_status [get_property STATUS [get_runs synth_1]]
set synth_progress [get_property PROGRESS [get_runs synth_1]]

puts "${COLOR_GREEN}INFO: Synthesis status: $synth_status, Progress: $synth_progress${COLOR_RESET}"

if {$synth_status == "synth_design ERROR"} {
    error_exit "Synthesis failed with errors"
}

if {$synth_progress != "100%"} {
    error_exit "Synthesis incomplete, progress: $synth_progress"
}

# 检查综合后的关键错误
open_run synth_1
set critical_warnings [get_msg_config -count -severity {CRITICAL WARNING}]
if {$critical_warnings > 0} {
    puts "${COLOR_YELLOW}WARNING: Found $critical_warnings critical warnings in synthesis${COLOR_RESET}"
}

# 生成综合报告
puts "${COLOR_GREEN}INFO: Generating synthesis reports...${COLOR_RESET}"
report_utilization -file synth_utilization.rpt
report_timing -file synth_timing.rpt

puts "${COLOR_GREEN}INFO: Synthesis completed successfully${COLOR_RESET}"

# 运行实现
puts "${COLOR_GREEN}INFO: Starting implementation...${COLOR_RESET}"
launch_runs impl_1 -jobs 10
wait_on_run impl_1

# 检查实现是否成功
set impl_status [get_property STATUS [get_runs impl_1]]
set impl_progress [get_property PROGRESS [get_runs impl_1]]

puts "${COLOR_GREEN}INFO: Implementation status: $impl_status, Progress: $impl_progress${COLOR_RESET}"

if {$impl_status == "place_design ERROR" || $impl_status == "route_design ERROR"} {
    error_exit "Implementation failed with errors: $impl_status"
}

if {$impl_progress != "100%"} {
    error_exit "Implementation incomplete, progress: $impl_progress"
}

puts "${COLOR_GREEN}INFO: Implementation completed successfully${COLOR_RESET}"

# 生成比特流
puts "${COLOR_GREEN}INFO: Starting bitstream generation...${COLOR_RESET}"
if {[catch {launch_runs impl_1 -to_step write_bitstream -jobs 10} result]} {
    error_exit "Failed to launch bitstream generation: $result"
}
wait_on_run impl_1

# 检查比特流生成是否成功
set bitstream_status [get_property STATUS [get_runs impl_1]]
if {$bitstream_status == "write_bitstream ERROR"} {
    error_exit "Bitstream generation failed"
}

puts "${COLOR_GREEN}INFO: Bitstream generation completed successfully${COLOR_RESET}"

# 生成最终报告
puts "${COLOR_GREEN}INFO: Generating implementation reports...${COLOR_RESET}"
open_run impl_1

# 检查时序约束
set timing_met [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
if {$timing_met < 0} {
    puts "${COLOR_YELLOW}WARNING: Timing constraints not met! Worst negative slack: $timing_met ns${COLOR_RESET}"
    puts "${COLOR_YELLOW}WARNING: Design may not work at target frequency${COLOR_RESET}"
} else {
    puts "${COLOR_GREEN}INFO: Timing constraints met. Slack: $timing_met ns${COLOR_RESET}"
}

# 检查 DRC 错误
puts "${COLOR_GREEN}INFO: Running DRC check...${COLOR_RESET}"
set drc_results [report_drc -return_string -quiet]
if {[string length $drc_results] > 0} {
    puts "${COLOR_YELLOW}WARNING: DRC violations found:${COLOR_RESET}"
    puts $drc_results
    report_drc -file drc.rpt
}

# 生成各种报告
if {[catch {
    report_utilization -file utilization.rpt
    report_timing_summary -file timing_summary.rpt
    report_power -file power.rpt
    report_route_status -file route_status.rpt
} result]} {
    puts "${COLOR_YELLOW}WARNING: Failed to generate some reports: $result${COLOR_RESET}"
}

# 检查比特流文件是否生成
set bit_file [get_property DIRECTORY [get_runs impl_1]]/soc_lite_top.bit
if {[file exists $bit_file]} {
    puts "${COLOR_GREEN}INFO: Bitstream file generated successfully: $bit_file${COLOR_RESET}"
    set bit_size [file size $bit_file]
    puts "${COLOR_GREEN}INFO: Bitstream size: [expr {$bit_size / 1024}] KB${COLOR_RESET}"
} else {
    puts "${COLOR_YELLOW}WARNING: Bitstream file not found at expected location: $bit_file${COLOR_RESET}"
}

puts "${COLOR_GREEN}INFO: Build process completed successfully!${COLOR_RESET}"

# 关闭项目
close_project
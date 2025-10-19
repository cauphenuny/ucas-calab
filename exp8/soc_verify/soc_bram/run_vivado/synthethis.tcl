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
# if {[catch {open_project project/loongson.xpr; set_property top tb_top} result]} {
    # puts "${COLOR_RED}WARNNING: Failed to load project: $result${COLOR_RESET}"
    if {[catch {source create_project.tcl} result]} {
        puts "${COLOR_RED}ERROR: Failed to create project: $result${COLOR_RESET}"
        exit 1
    }
# }

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

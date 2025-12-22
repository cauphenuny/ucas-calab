create_project -force loongson ./project -part xc7a200tfbg676-1

# Add conventional sources
add_files -scan_for_includes [glob -nocomplain ../rtl/*.v]

# Add IPs
add_files -quiet [glob -nocomplain ../rtl/xilinx_ip/*.xci]

# Add simulation files
add_files -fileset sim_1 ../testbench

# Add source files
set mycpu_sv_files [glob -nocomplain ../myCPU/*.sv]
if {[llength $mycpu_sv_files] > 0} {
	add_files -quiet -scan_for_includes $mycpu_sv_files
	set_property file_type {SystemVerilog} [get_files $mycpu_sv_files]
}

set mycpu_v_files [glob -nocomplain ../myCPU/*.v]
if {[llength $mycpu_v_files] > 0} {
	add_files -quiet -scan_for_includes $mycpu_v_files
}

# Add constraints
add_files -fileset constrs_1 -quiet ./constraints

# Add cache RAM IP cores
set ip_repo_dir [file normalize ../rtl/xilinx_ip]

proc ensure_cache_bram {name width depth use_byte_we init_mem ip_dir} {
	if {[llength [get_ips -quiet $name]] == 0} {
		create_ip -name blk_mem_gen -vendor xilinx.com -library ip -version 8.4 -module_name $name -dir $ip_dir
	}

	set config_list [list \
		CONFIG.Memory_Type {Single_Port_RAM} \
		CONFIG.Write_Width_A $width \
		CONFIG.Read_Width_A $width \
		CONFIG.Write_Depth_A $depth \
		CONFIG.Enable_A {Use_ENA_Pin} \
		CONFIG.Register_PortA_Output_of_Memory_Primitives {false} \
		CONFIG.Register_PortA_Output_of_Memory_Core {false} \
		CONFIG.Load_Init_File {false}
	]

	if {$init_mem} {
		lappend config_list CONFIG.Fill_Remaining_Memory_Locations {true}
		lappend config_list CONFIG.Remaining_Memory_Locations {0}
	} else {
		lappend config_list CONFIG.Fill_Remaining_Memory_Locations {false}
	}

	if {$use_byte_we} {
		lappend config_list CONFIG.Use_Byte_Write_Enable {true}
		lappend config_list CONFIG.Byte_Size {8}
	} else {
		lappend config_list CONFIG.Use_Byte_Write_Enable {false}
	}

	set_property -dict $config_list [get_ips $name]
	generate_target {instantiation_template} [get_ips $name]
	generate_target all [get_ips $name]
	export_ip_user_files -of_objects [get_ips $name] -no_script -sync -force -quiet
}

ensure_cache_bram cache_tagv_ram 21 256 false true $ip_repo_dir
ensure_cache_bram cache_data_ram 32 256 true false $ip_repo_dir

set_property -name "top" -value "tb_top" -objects  [get_filesets sim_1]
set_property -name "xsim.simulate.log_all_signals" -value "1" -objects [get_filesets sim_1]

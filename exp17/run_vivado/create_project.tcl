create_project -force loongson ./project -part xc7a200tfbg676-1

# Add conventional sources
add_files -scan_for_includes [glob -nocomplain ../rtl/*.v]

# Add IPs
add_files -quiet [glob -nocomplain ../rtl/xilinx_ip/*.xci]

# Add simulation files
add_files -fileset sim_1 ../testbench

# Add SystemVerilog design sources explicitly so Vivado parses them as SV
set sv_design_sources [list \
	../myCPU/tlb.sv \
	../myCPU/tools.sv \
	../myCPU/tlb_searcher.sv
]

foreach sv_file $sv_design_sources {
	if {[file exists $sv_file]} {
		set sv_norm [file normalize $sv_file]
		add_files -quiet -scan_for_includes $sv_norm
		set_property file_type {SystemVerilog} [get_files $sv_norm]
	} else {
		puts "[format {WARNING: SystemVerilog source '%s' was not found.} $sv_file]"
	}
}

# Add constraints
add_files -fileset constrs_1 -quiet ./constraints

set_property -name "top" -value "tb_top" -objects  [get_filesets sim_1]
set_property -name "xsim.simulate.log_all_signals" -value "1" -objects [get_filesets sim_1]

# Compile the MC68020 into the `sun3' xsim library, and set the define that
# tells sun3_top.v which of its two instantiations to build.
#
# Sourced by run_xsim.sh.  Expects `top' to be set and a `defargs' array to
# append to; call compile_cpu after the run directory exists and before the
# Sun-3 gateware is compiled, since the define has to reach that xvlog.
#
#   SUN3_CPU=suska     the Suska WF68K30L VHDL core (default)
#   SUN3_CPU=rd68021   the SystemVerilog core in Inputs/RD68021
#
# Both are compiled from patched copies under build/inputs/ (see
# tools/patch_inputs.sh), never from Inputs/ itself.  With no patches in
# patches/<name>/ the copy is identical to the input.
#
# SUSKA_DIR builds the VHDL core from somewhere else entirely.

compile_cpu() {
	case "${SUN3_CPU:-suska}" in
	rd68021)
		"$top/tools/patch_inputs.sh" RD68021
		local rd="$top/build/inputs/RD68021"
		defargs+=(-d SUN3_CPU_RD68021)
		echo "== compiling the RD68021 MC68020 (SystemVerilog) =="
		# Order from that project's own Makefile: packages first (the
		# generated ones too), then the generated ROMs, then the RTL.
		xvlog --sv --work sun3 \
			"$rd/rtl/rd68021_pkg.sv" \
			"$rd/rtl/gen/rd68021_frame_pkg.sv" \
			"$rd/rtl/gen/rd68021_ucode_pkg.sv" \
			"$rd/rtl/gen/rd68021_cpdec_rom.sv" \
			"$rd/rtl/gen/rd68021_decode_rom.sv" \
			"$rd/rtl/gen/rd68021_eadec_rom.sv" \
			"$rd/rtl/gen/rd68021_eamode_rom.sv" \
			"$rd/rtl/gen/rd68021_ucode_rom.sv" \
			"$rd/rtl/rd68021_sync.sv" \
			"$rd/rtl/rd68021_dedge_ff.sv" \
			"$rd/rtl/rd68021_shifter.sv" \
			"$rd/rtl/rd68021_divider.sv" \
			"$rd/rtl/rd68021_bitfield.sv" \
			"$rd/rtl/rd68021_biu.sv" \
			"$rd/rtl/rd68021_icache.sv" \
			"$rd/rtl/rd68021_ifu.sv" \
			"$rd/rtl/rd68021_seq.sv" \
			"$rd/rtl/rd68021_top.sv"
		;;
	suska)
		"$top/tools/patch_inputs.sh" Suska_Configware
		local sk="${SUSKA_DIR:-$top/build/inputs/Suska_Configware/68K30L}"
		if [ ! -e "$sk/wf68k30L_top.vhd" ]; then
			echo "no Suska WF68K30L at $sk" >&2
			return 1
		fi
		echo "== compiling the Suska WF68K30L (VHDL, from $sk) =="
		# The package first: everything else depends on it.  Of the two
		# ALUs (same entity), alu_new is the one the old build used: it
		# takes X from X_IN throughout rather than from STATUS_REG(4).
		# -2008: the Sun-2 build of the sibling 68K10 core needed it
		# (`buffer' formals on `out' actuals); harmless here.
		xvhdl -2008 --work sun3 \
			"$sk/wf68k30L_pkg.vhd" \
			"$sk/wf68k30L_address_registers.vhd" \
			"$sk/wf68k30L_alu_new.vhd" \
			"$sk/wf68k30L_bus_interface.vhd" \
			"$sk/wf68k30L_control.vhd" \
			"$sk/wf68k30L_data_registers.vhd" \
			"$sk/wf68k30L_exception_handler.vhd" \
			"$sk/wf68k30L_opcode_decoder.vhd" \
			"$sk/wf68k30L_top.vhd"
		;;
	*)
		echo "SUN3_CPU must be suska or rd68021, not '$SUN3_CPU'" >&2
		return 1
		;;
	esac
}

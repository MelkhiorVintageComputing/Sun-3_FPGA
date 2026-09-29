# Compile the Sun-3 machine (rtl/sun3 plus the SCC and, optionally, the
# Wish7990) into the `sun3' xsim library.
#
# Sourced by run_xsim.sh and run_xsim_board.sh, so the file list exists once.
# Expects `top' and a `defargs' array (the -d defines); `eth' says whether the
# Wish7990 is in (none | wish7990).  Call it after compile_cpu, in the run
# directory.  Leaves the SystemVerilog sources the machine needs in the
# `sun3_sv' array rather than compiling them, so the caller can compile them
# in one xvlog --sv run with its own testbench and board files.

compile_sun3() {
	"$top/tools/patch_inputs.sh" z8530_scc
	[ "$eth" = wish7990 ] && "$top/tools/patch_inputs.sh" Wish7990

	# The Sun-3 gateware is plain Verilog; compiled as such.
	echo "== compiling the Sun-3 gateware (Verilog) =="
	xvlog --work sun3 \
		"${defargs[@]}" \
		-i "$top/rtl/sun3" -i "$top/build/rom" \
		"$top/rtl/sun3/sun3_top.v" \
		"$top/rtl/sun3/sun3_fpga.v" \
		"$top/rtl/sun3/sun3_mmu.v" \
		"$top/rtl/sun3/ctx_reg_sun3.v" \
		"$top/rtl/sun3/smap.v" \
		"$top/rtl/sun3/pmap.v" \
		"$top/rtl/sun3/sram_sync.v" \
		"$top/rtl/sun3/idprom_sun3.v" \
		"$top/rtl/sun3/gen8bit_reg.v" \
		"$top/rtl/sun3/cyctr32bit_reg.v" \
		"$top/rtl/sun3/bootrom32.v" \
		"$top/rtl/sun3/icm7170.v" \
		"$top/rtl/sun3/eeprom.v" \
		"$top/rtl/sun3/sun3_irq_priority.v" \
		"$top/rtl/sun3/sun3_wishbone_bridge.v" \
		"$top/rtl/sun3/wish7990_sun3_regs.v" \
		"$top/rtl/sun3/wish7990_dvma_to_020.v"

	sun3_sv=("$top/build/inputs/z8530_scc/z8530_scc.sv")
	if [ "$eth" = wish7990 ]; then
		local w="$top/build/inputs/Wish7990/src"
		sun3_sv+=("$w/wish7990_pkg.sv" "$w/crc32_eth.sv" "$w/sync_fifo.sv"
			"$w/async_fifo.sv" "$w/dp_ram.sv" "$w/mii_rx.sv" "$w/mii_tx.sv"
			"$w/wb_master.sv" "$w/wb_arb.sv" "$w/le_regs.sv" "$w/le_init.sv"
			"$w/le_tx.sv" "$w/le_filt.sv" "$w/le_rx.sv" "$w/wish7990.sv"
			"$w/wb_mdio.sv")
	fi
}

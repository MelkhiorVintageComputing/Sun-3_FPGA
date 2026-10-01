# Read by syn/build.tcl for the FIFO bridge (WB_FIFO=1), in place of
# wukong_wbcdc.xdc.  From the Sun-2 project's file of the same name.
#
# The crossing between cpu_clk and MIG's ui_clk is inside sun3_fifo_bridge, in
# two sun3_async_fifo instances: req_fifo writes on cpu_clk and reads on
# ui_clk, rsp_fifo the other way.  wb_mig_sync, beyond it, is entirely in
# ui_clk.  The clock handles come from wukong_common.xdc, read first, which
# leaves cpu_clk and the MIG clocks in one group: no set_clock_groups between
# them here, or it would outrank every bound below (the Sun-2's file was
# silently overridden that way).
#
# What crosses, per FIFO: the registered gray write pointer into the read
# side's first synchroniser, the registered gray read pointer into the write
# side's, and the storage -- read asynchronously, as LUT RAM -- into whatever
# the read side registers from its head.  Each is bounded by the destination
# clock's period: generous for a pointer with a whole synchroniser stage behind
# it, and a real bound for the storage, stable for two read clocks before the
# read side looks.
#
# Then the resets, the only other crossings: the bridge's two reset
# synchronisers, and init_calib_complete (ui_clk) into the CPU's reset_sync,
# whose chain it presets asynchronously.  Anything else between the two clocks
# is timed as a synchronous path between unrelated periods and fails.
#
# `get_cells -hier -filter' rather than literal paths: the bridge sits under
# machine/.../wbridge, and a pattern that stops matching after a hierarchy
# change is dropped with nothing louder than a warning.  build.tcl checks that
# every one of these lists is non-empty.

set cpu_period [get_property PERIOD $cpu_clk]
set ui_period  12.000

# request FIFO: cpu_clk -> ui_clk
set_max_delay -datapath_only \
    -from [get_cells -hier -filter {NAME =~ *wbridge/req_fifo/wgray_reg[*]}] \
    -to   [get_cells -hier -filter {NAME =~ *wbridge/req_fifo/wgray_r1_reg[*]}] $ui_period
set_max_delay -datapath_only \
    -from [get_cells -hier -filter {NAME =~ *wbridge/req_fifo/rgray_reg[*]}] \
    -to   [get_cells -hier -filter {NAME =~ *wbridge/req_fifo/rgray_w1_reg[*]}] $cpu_period
set_max_delay -datapath_only \
    -from [get_cells -hier -filter {NAME =~ *wbridge/req_fifo/mem_reg*}] \
    -to   [get_clocks clk_pll_i] $ui_period

# response FIFO: ui_clk -> cpu_clk
set_max_delay -datapath_only \
    -from [get_cells -hier -filter {NAME =~ *wbridge/rsp_fifo/wgray_reg[*]}] \
    -to   [get_cells -hier -filter {NAME =~ *wbridge/rsp_fifo/wgray_r1_reg[*]}] $cpu_period
set_max_delay -datapath_only \
    -from [get_cells -hier -filter {NAME =~ *wbridge/rsp_fifo/rgray_reg[*]}] \
    -to   [get_cells -hier -filter {NAME =~ *wbridge/rsp_fifo/rgray_w1_reg[*]}] $ui_period
set_max_delay -datapath_only \
    -from [get_cells -hier -filter {NAME =~ *wbridge/rsp_fifo/mem_reg*}] \
    -to   $cpu_clk $cpu_period

# Resets.
set_false_path -to [get_cells -hier -filter {NAME =~ *wbridge/wbrst_s_reg[0]}]
set_false_path -to [get_cells -hier -filter {NAME =~ *wbridge/cpurst_s_reg[0]}]
set_false_path -from $mig_clks -to [get_pins rst_cpu/chain_reg[*]/PRE]

`ifndef SUN3_ATTR_VH
`define SUN3_ATTR_VH
//
// Synthesis attributes, spelled once, per tool.  A typo in a macro is an
// elaboration error; a typo in an attribute is silently ignored.
//
// Vivado reads `ram_style' and ignores `ramstyle'; Quartus the reverse.
// syn/quartus.tcl defines SUN3_QUARTUS; nothing else does.  Quartus has no
// per-register ASYNC_REG: its global SYNCHRONIZER_IDENTIFICATION setting and
// the SDC's asynchronous clock groups do that job (as in the Sun-2 project).
//
`ifdef SUN3_QUARTUS
 `define SUN3_RAM_BLOCK (* ramstyle = "M9K" *)
 `define SUN3_ASYNC_REG
`else
 `define SUN3_RAM_BLOCK (* ram_style = "block" *)
 `define SUN3_ASYNC_REG (* ASYNC_REG = "TRUE" *)
`endif

`endif // SUN3_ATTR_VH

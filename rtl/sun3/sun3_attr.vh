`ifndef SUN3_ATTR_VH
`define SUN3_ATTR_VH
//
// Synthesis attributes, spelled once.  A typo in a macro is an elaboration
// error; a typo in an attribute is silently ignored.  Only Vivado is a target
// today; a second tool gets its own arm here (the Sun-2 project has a Quartus
// one).
//
`define SUN3_RAM_BLOCK (* ram_style = "block" *)
`define SUN3_ASYNC_REG (* ASYNC_REG = "TRUE" *)

`endif // SUN3_ATTR_VH

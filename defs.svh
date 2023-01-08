`ifndef DEFS_SV
`define DEFS_SV

`default_nettype none
timeunit 1ns;
timeprecision 10ps;

// This makes it easier to create a getter function
// so that it can be read in the C++ wrapper.
// The CMT_SLASH and CMT_STAR macros are so that the
// necessary comment /*verilator public*/ is preserved.
`define CMT_SLASH /
`define CMT_STAR *
`define getter(name, signal, bus_type) `ifdef verilator \
    function bus_type get_``name; \
        `CMT_SLASH`CMT_STAR``verilator public```CMT_STAR`CMT_SLASH \
        get_``name = signal; \
    endfunction \
`endif

`endif

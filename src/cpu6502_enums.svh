`ifndef CPU6502_STATE_SV
`define CPU6502_STATE_SV

typedef enum {
    CpuInvalid,
    CpuReadOpcode,
    CpuImplied,
    CpuImmediate,
    CpuZeroPage1, CpuZeroPage2,
    CpuZeroPageIdx2, CpuZeroPageIdx3,
    CpuAbsolute1, CpuAbsolute2, CpuAbsolute3,
    CpuAbsoluteIdx1, CpuAbsoluteIdx2, CpuAbsoluteIdx3,
    CpuIndirectX1, CpuIndirectX2, CpuIndirectX3, CpuIndirectX4, CpuIndirectX5,
    CpuIndirectY1, CpuIndirectY2, CpuIndirectY3, CpuIndirectY4, CpuIndirectY5,
    CpuRelative1, CpuRelativeBrTaken, CpuRelativeFixPCH,
    CpuRMW1, CpuRMW2,
    CpuStackPush,
    CpuStackPop1, CpuStackPop2,
    CpuJmpInd1, CpuJmpInd2,
    CpuJsr1, CpuJsr2, CpuJsr3, CpuJsr4,
    CpuRtsRti1, CpuRti2, CpuRtsRti3, CpuRtsRti4, CpuRtsRti5, CpuRts6,
    CpuBrk1, CpuBrk2, CpuBrk3, CpuBrk4, CpuBrk5, CpuBrk6, CpuBrk7
} cpu_state_e;

typedef enum {
    PS_CARRY    = 0,
    PS_ZERO     = 1,
    PS_INTDIS   = 2,
    PS_DEC      = 3,
    // 4 and 5 do not exist on the 6502
    PS_OVERFLOW = 6,
    PS_NEGATIVE = 7
} status_indices_e;

typedef enum {
    IntReset,
    IntNMI,
    IntIRQ,
    IntBRK
} cpu_interrupt_type_e;

`endif

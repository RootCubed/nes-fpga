# NES on an FPGA

## About

This is an implementation of the Nintendo Entertainment System on an FPGA. Though I try to match the original console as closely as possible, the inputs and outputs of the individual modules are not the same as the ones of the ICs used in the NES.

The Vivado project and the constraints file are specific to the Digilent Basys 3 board, but one should be able to modify these easily to support other FPGA development boards.

## Current state

The project is still WIP and especially the PPU is relatively buggy. Here's a rough outline of the state of the project:
- ✅ Basic CPU implementation
- ✅ Basic PPU implementation
- ✅ VGA output
- ⚠️ Game loading is still semi-hardcoded (memory file loaded with `readmemh`)
- ⚠️ Controller currently only mapped to the buttons on the Basys 3 board itself
- ❌ APU implementation
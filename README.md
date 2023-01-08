# NES on an FPGA

## About

This is a Verilog implementation of the Nintendo Entertainment System. Though I try to match the original console as closely as possible, the inputs and outputs of the individual modules are not the same as the ones of the ICs used in the NES.

Currently the design only runs as a simulation, because of some missing modules like VGA output and controller input, but this should be soon supported.

The simulation is done with [Verilator](https://www.veripool.org/verilator/), as it allows for very fast simulation and thus leads to faster development time.

## Code-along guide

I am planning on turning this project into a guide for programming your own NES implementation. The format of this guide is still undecided. Maybe it'll be a video tutorial series, simple PDF files with instructions, or something completely different.

## Current state

Here's a rough outline of the state of the project:
- ✅ Basic CPU implementation
- ✅ Basic PPU implementation
- ❌ VGA output
- ❌ Controller input
- ❌ Working on an FPGA board
- ❌ APU implementation
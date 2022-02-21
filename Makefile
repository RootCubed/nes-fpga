SRC       := ./src
SRCS	  := $(filter-out $(SRC)/NES.sv $(SRC)/ClockGen.sv, $(wildcard $(SRC)/*.sv))
TESTBENCH := $(SRC)/tb/NESTestbench.sv

all: simulate

lint:
	verilator --lint-only $(SRCS)

FORCE: ;

simulate: FORCE
	iverilog -g2005-sv -Wall -o $(TESTBENCH).vvp $(SRCS) $(TESTBENCH)
	cd src && vvp ./tb/NESTestbench.sv.vvp -n -fst > ../Testbench.log

gtkwave: simulate
	gtkwave $(SRC)/NESTestbench.fst testbench_wave.gtkw --optimize

clean:
	rm -rf $(TESTBENCH).fst NESTestbench.vcd
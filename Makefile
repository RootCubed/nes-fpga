.PHONY: compile

VERILOG_FILES = nes.sv

clean:
	rm -rf obj_dir

compile: clean
	verilator --cc --exe --build -j 0 --trace-fst $(VERILOG_FILES) wrapper.cpp screen_renderer.cpp -LDFLAGS "-lX11 -lGL -lGLU"

run: compile
	cd obj_dir && ./Vnes

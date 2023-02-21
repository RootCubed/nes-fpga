.PHONY: compile

VERILOG_FILES = src/nes.sv

clean:
	rm -rf obj_dir

compile: clean
	verilator --cc --exe --build -j 0 --trace-fst $(VERILOG_FILES) wrapper.cpp screen_renderer.cpp -Isrc -LDFLAGS "-lX11 -lGL -lGLU"

run: compile
	cd obj_dir && ./Vnes

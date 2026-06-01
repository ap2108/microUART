OUT = sim
VCD = wave.vcd

all: compile run

compile:
	iverilog -o $(OUT) src/design/*.v src/test_bench/uart_tb.v
run: 
	vvp $(OUT)

wave: 
	gtkwave $(VCD) &

clean:
	rm -f $(OUT) $(VCD)
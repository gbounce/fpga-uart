rx:
	iverilog -s rx_tb -g2012 -o uart_rx src/uart_rx.sv src/rx_tb.sv
	vvp uart_rx

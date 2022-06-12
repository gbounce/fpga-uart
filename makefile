rx:
	iverilog -s rx_tb -g2012 -o uart_rx.icarus src/uart_rx.sv src/rx_tb.sv
	vvp uart_rx.icarus

tx:
	iverilog -s tx_tb -g2012 -o uart_tx.icarus src/uart_tx.sv src/tx_tb.sv
	vvp uart_tx.icarus

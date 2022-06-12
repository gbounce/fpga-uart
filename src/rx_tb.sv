/*
Copyright (C) 2022 Ryan Robertson <rrobertson@gmail.com>

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

// simple rx tb
// send a byte of data at a specified baud rate

module rx_tb;
  localparam int  BAUD_RATE      = 115200;
  localparam real BAUD_PERIOD_NS = 1.0/BAUD_RATE * 1e9;
  localparam bit  EVEN_PARITY    = 1;
  localparam int  STOP_BITS      = 1;

  logic clk, rst, bclk;
  logic uart_rx = 1;
  logic uart_vld;
  logic uart_err;
  logic [7:0] rdata;
  logic [7:0] sent_data [$];
  logic [7:0] expected_data;
  logic pass_fail = 1'b1;

  uart_rx #(.CLK_FREQ    (100e6),
            .NCO_WIDTH   (16),
            .BAUD_RATE   (BAUD_RATE),
            .STOP_BITS   (STOP_BITS),
            .EVEN_PARITY (EVEN_PARITY)
  )
  U_DUT (
    .clk       (clk),
    .rst       (rst),
    .uart_rx   (uart_rx),
    .uart_err  (uart_err),
    .rdata_vld (rdata_vld),
    .rdata     (rdata)
  );

  initial begin
    $dumpfile("wave.vcd");
    $dumpvars(1, U_DUT);
    $dumpvars(1, rx_tb);
  end

  // 100 mhz clk
  initial begin
    clk = 0;
    forever clk = #5 ~clk;
  end

  // uart baud clk
  initial begin
    bclk = 0;
    forever bclk = #(BAUD_PERIOD_NS/2 * 1ns) ~bclk;
  end

  // reset gen
  initial begin
    rst <= 1;
    #1us;
    @(posedge clk)
    rst <= 0;
  end

  // driver
  task tx_byte(input logic [7:0] data);
    $display("SENDING 0x%h", data);

    sent_data.push_front(data);

    // start bit
    @(posedge bclk);
    uart_rx <= 1'b0;

    // data, lsb first
    for (int i=0; i<8; i++) begin
      @(posedge bclk);
      uart_rx <= data[i];
    end

    // parity
    @(posedge bclk);
    uart_rx <= EVEN_PARITY ? ^data : ~^data;

    // deassert
    @(posedge bclk);
    uart_rx <= 1;

    // guarantee stop bit time before returning
    repeat(2) @(posedge bclk);
  endtask

  // data monitor
  always begin
      @(posedge rdata_vld);
      expected_data = sent_data.pop_front();

      if (rdata == expected_data) begin
        $display("RECEIVED DATA: 0x%h, OK", rdata);
      end else begin
        $error("DATA MISMATCH, EXPECTED 0x%h, GOT 0x%h", expected_data, rdata);
        pass_fail <= 1'b0;
      end
  end

  // err monitor
  always begin
    @(posedge uart_err);
    $error("Saw UART_ERR assert!");
    pass_fail = 0;
  end

  // test
  initial begin
    string set_parity;
    if (EVEN_PARITY) set_parity = "EVEN";
    else set_parity = "ODD"; // icarus choking on ternary
    $display("TESTBENCH START");
    $display("BAUD RATE SET TO %0d", BAUD_RATE);
    $display("PARITY SET TO %s", set_parity);
    $display("STOP BITS SET TO %0d", STOP_BITS);
    @(posedge rst);
    #2us;
    tx_byte(8'h12);
    tx_byte(8'hFF);
    tx_byte(8'h00);
    tx_byte(8'hAA);
    tx_byte(8'h55);
    #10us;
    $display("TESTBENCH END");
    if (pass_fail) begin
        $display("TEST PASSED :)");
    end else begin
        $display("TEST FAILED :(");
    end
    $finish;
  end
endmodule

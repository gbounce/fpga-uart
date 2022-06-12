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

module tx_tb;
  localparam int  BAUD_RATE      = 115200;
  localparam real BAUD_PERIOD_NS = 1.0/BAUD_RATE * 1e9;
  localparam bit  EVEN_PARITY    = 1;
  localparam int  STOP_BITS      = 1;

  logic clk, rst, bclk;
  logic uart_tx;
  logic overflow, ready;
  logic dvld = 0;
  logic [7:0] data = '0;
  logic [7:0] data_comp = '0;    
  logic [8:0] data_check; // data + parity
  logic [7:0] sent_data [$];
  logic pass_fail = 1'b1;
  int dcnt;

  uart_tx #(.CLK_FREQ    (100e6),
            .NCO_WIDTH   (16),
            .BAUD_RATE   (BAUD_RATE),
            .STOP_BITS   (STOP_BITS),
            .EVEN_PARITY (EVEN_PARITY)
  ) U_DUT (
    .clk      (clk),
    .rst      (rst),
    .dvld     (dvld),
    .data     (data),
    .ready    (ready),
    .overflow (overflow),
    .uart_tx  (uart_tx)
  );

  initial begin
    $dumpfile("wave.vcd");
    $dumpvars(1, U_DUT);
    $dumpvars(1, tx_tb);
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

  function print_settings ();
    string set_parity;
    if (EVEN_PARITY) set_parity = "EVEN";
    else set_parity = "ODD"; // icarus choking on ternary
    $display("TESTBENCH START");
    $display("BAUD RATE SET TO %0d", BAUD_RATE);
    $display("PARITY SET TO %s", set_parity);
    $display("STOP BITS SET TO %0d", STOP_BITS);
  endfunction

  task wait_for_reset ();
    @(posedge rst);
    #2us;
    @(posedge clk);
  endtask

  task send_data (input logic [7:0] idata, input bit wait_for_done = 1);
    $display("Sending 0x%0h @ %0t", idata, $realtime);
    @(posedge clk);
    dvld <= 1'b1;
    data <= idata;
    sent_data.push_front(idata);    
    @(posedge clk);
    dvld <= 1'b0;
    if (wait_for_done) begin
      @(posedge ready);
      $display("Complete @ %0t", $realtime);
    end
  endtask

  // data checker
  always begin
    dcnt = 0;

    // wait for start bit assertion and center align
    @(negedge uart_tx);
    #(BAUD_PERIOD_NS/2 * 1ns);

    // grab data and parity
    repeat(9) begin
      #(BAUD_PERIOD_NS * 1ns);
      data_check[dcnt] = uart_tx;
      dcnt++;
    end

    data_comp = sent_data.pop_front();
    if (data_comp != data_check[7:0]) begin
        $error("Data mismatch, got 0x%0x, expected 0x%0x @ %0t", 
               data_check[7:0], data_comp, $realtime);
        pass_fail = 0;
    end

    // check for stop bits
    repeat(STOP_BITS) begin
      #(BAUD_PERIOD_NS * 1ns);
      if (!uart_tx) begin 
        $error("Stop bit invalid @ %0t", $realtime);
        pass_fail = 0;
      end
    end

    $display("Got data 0x%0x @ %0t", data_check[7:0], $realtime);
  end

  // test
  initial begin
    print_settings();
    wait_for_reset();
    send_data('h12);
    send_data('h00);
    send_data('hFF);
    send_data('h00);
    send_data('hAA);
    send_data('h55);
    #1ms;
    $display("TESTBENCH END");
    if (pass_fail) begin
      $display("TEST PASSED :)");
    end else begin
      $display("TEST FAILED :(");
    end
    $finish;
  end
endmodule

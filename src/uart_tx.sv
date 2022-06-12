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

`timescale 1ns / 1ns

module uart_tx #(
  parameter int CLK_FREQ    = 100E6,
  parameter int NCO_WIDTH   = 16,
  parameter int BAUD_RATE   = 115200,
  parameter int STOP_BITS   = 1,
  parameter bit EVEN_PARITY = 0) // even = 1, odd = 0
(
  // globals
  input  logic       clk,
  input  logic       rst,
  // control
  input  logic       dvld,
  input  logic [7:0] data,
  // status
  output logic       ready,
  output logic       overflow,
  // i/o
  output logic       uart_tx
);

  localparam real CLK_PER  = 1.0/CLK_FREQ;
  localparam real BAUD_PER = 1.0/(BAUD_RATE);
  localparam int  NCO_INCR = int'(2**NCO_WIDTH / (BAUD_PER / CLK_PER));

  logic [NCO_WIDTH-1:0] nco_accum = '0;
  logic                 baud_tx_en;

  logic [3:0]           dcnt;

  logic                 start_tx;

  logic [8+STOP_BITS:0] rdata_sr;
  logic                 calc_parity;

  logic dvld_q, dvld_q2;
  logic [9:0]           data_q; // start + 8b data + parity
  logic                 parity;

  logic                 clr_ready;

  // overflow
  always_ff @(posedge clk) begin
    if (rst) begin
      overflow <= 1'b0;
    end else begin
      overflow <= 1'b0;
      if (dvld && !ready) overflow <= 1'b1;
    end
  end

  // hold data, calc parity, and shift
  always_ff @(posedge clk) begin
    if (dvld && ready) begin
      data_q[8:1] <= data;
      data_q[0]   <= 1'b0;
    end else if (dvld_q) begin
      data_q[9] <= EVEN_PARITY ? ^data_q[8:1] : ~^data_q[8:1];
    end else if (baud_tx_en && dcnt != 0) begin
      data_q <= data_q >> 1;
    end
  end

  always_ff @(posedge clk) begin
    dvld_q  <= dvld;
    dvld_q2 <= dvld_q;
  end

  // numerically controlled oscillator, 1x tx baud
  always_ff @(posedge clk) begin
    if (rst) begin
      baud_tx_en <= 1'b0;
      nco_accum  <= '0;
    end else begin
      {baud_tx_en, nco_accum} <= nco_accum + NCO_INCR;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      ready <= 1'b1;
    end else begin
      if (dvld) begin
        ready <= 1'b0;
      end else if (dcnt == 0 && baud_tx_en && clr_ready) begin
        ready <= 1'b1;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      start_tx <= 1'b0;
    end else begin
      if (dvld_q) start_tx <= 1'b1;
      else if (baud_tx_en) start_tx <= 1'b0;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      dcnt      <= '0;
      uart_tx   <= 1'b1;
      clr_ready <= 1'b0;
    end else if (baud_tx_en) begin
      clr_ready <= 1'b0;

      if (start_tx) begin
        dcnt <= 9 + STOP_BITS;
      end else if (dcnt != 0) begin
        dcnt <= dcnt - 1'b1;
        if (dcnt == 1) clr_ready <= 1'b1;
      end

      uart_tx <= 1'b1;
      if (dcnt != 0) begin
        uart_tx <= data_q[0];
      end
    end
  end
endmodule
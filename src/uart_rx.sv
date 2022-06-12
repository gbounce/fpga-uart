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

module uart_rx #(
  parameter int CLK_FREQ    = 100E6,
  parameter int NCO_WIDTH   = 16,
  parameter int BAUD_RATE   = 115200,
  parameter int STOP_BITS   = 1,
  parameter bit EVEN_PARITY = 0) // even = 1, odd = 0
(
  // globals
  input  logic       clk,
  input  logic       rst,
  // status
  output logic       uart_err,
  // control
  output logic       rvld,
  output logic [7:0] rdata,
  // i/o  
  input  logic       uart_rx
);

  localparam real CLK_PER  = 1.0/CLK_FREQ;
  localparam real BAUD_PER = 1.0/(BAUD_RATE*16);
  localparam int  NCO_INCR = int'(2**NCO_WIDTH / (BAUD_PER / CLK_PER));

  (* ASYNC_REG = "TRUE" *) logic [1:0] uart_rx_sync_sr;
  logic uart_rx_sync;

  logic [7:0] start_bit_det_sr;
  logic       start_bit_det;

  logic [NCO_WIDTH-1:0] nco_accum;
  logic                 baud_rx_en;

  logic [3:0]           center_sample_cnt;
  logic [3:0]           bit_cnt;

  logic                 bit_vld;
  logic                 busy;

  logic [8+STOP_BITS:0] rdata_sr;
  logic                 calc_parity;

  logic [7:0]           rdata_tmp;

  // numerically controlled oscillator, 16x baud rx oversample
  always_ff @(posedge clk) begin
    if (rst) begin
      baud_rx_en <= 1'b0;
      nco_accum  <= '0;
    end else begin
      {baud_rx_en, nco_accum} <= nco_accum + NCO_INCR;
    end
  end

  // metafilter input
  always_ff @(posedge clk) begin
    uart_rx_sync_sr <= {uart_rx_sync_sr[0], uart_rx};
  end

  assign uart_rx_sync = uart_rx_sync_sr[1];

  // hold half the oversample rate of uart_rx, equal to half a baud period
  always_ff @(posedge clk) begin
    if (rst) begin
      start_bit_det_sr <= '1;
    end else if (busy) begin
      start_bit_det_sr <= '1;
    end else if (baud_rx_en) begin
      start_bit_det_sr <= {start_bit_det_sr[6:0], uart_rx_sync};
    end
  end

  // start bit detected when all held samples are 0
  // this is asserted in the middle of the start bit
  assign start_bit_det = ~|start_bit_det_sr;

  // set busy flag when start bit detected, deassert when byte captured
  always_ff @(posedge clk) begin
    if (rst) begin
      busy <= 1'b0;
    end else begin
      if (start_bit_det) begin
        busy <= 1'b1;
      end else if (bit_vld &&
                   ((STOP_BITS == 0 && bit_cnt == 9) ||
                     bit_cnt == 8+STOP_BITS)) begin
        busy <= 1'b0;
      end
    end
  end

  // center bit detected after 9 continous samples of logic 0
  // count 16 more and center sample uart_rx
  always_ff @(posedge clk) begin
    if (rst) begin
      center_sample_cnt <= '0;
      bit_vld           <= 1'b0;
    end else if (baud_rx_en) begin
      bit_vld           <= 1'b0;
      center_sample_cnt <= '0;

      if (busy) begin
        if (center_sample_cnt < NCO_WIDTH-1) begin
          center_sample_cnt <= center_sample_cnt + 1;
        end else begin
          center_sample_cnt <= '0;
          bit_vld           <= 1'b1;
        end
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      bit_cnt  <= '0;
      rvld     <= 1'b0;
      uart_err <= 1'b0;
    end else begin
      rvld     <= 1'b0;
      uart_err <= 1'b0;

      if (baud_rx_en && bit_vld) begin
        if ((STOP_BITS == 0 && bit_cnt < 9) || bit_cnt < 8+STOP_BITS) begin
          bit_cnt <= bit_cnt + 1;
        end else begin
          bit_cnt <= '0;

          // check for stop bit (active uart_rx signal) and parity
          // if no stop bit defined just check parity
          if ((STOP_BITS != 0 && uart_rx_sync &&
              rdata_sr[$size(rdata_sr)-STOP_BITS] == calc_parity) ||
              (STOP_BITS == 0 &&
               rdata_sr[$size(rdata_sr)-1] == calc_parity)) begin
            rvld <= 1'b1;
          end else begin
            uart_err <= 1'b1;
          end
        end
      end
    end
  end

  // lsb received first, shift in left to right so [0] = lsb
  always_ff @(posedge clk) begin
    if (baud_rx_en && bit_vld && ((bit_cnt < 9+STOP_BITS && STOP_BITS == 0) ||
        bit_cnt < 8 + STOP_BITS)) begin
      rdata_sr <= {uart_rx_sync, rdata_sr[$size(rdata_sr)-1:1]};
    end
  end

  // select bits and parity calculation
  assign rdata_tmp   = (STOP_BITS != 0) ?
                       rdata_sr[$size(rdata_sr)-1-STOP_BITS:1] :
                       rdata_sr[$size(rdata_sr)-2:0];
  assign calc_parity = EVEN_PARITY ? ^rdata_tmp : ~^rdata_tmp;

  always_ff @(posedge clk) begin
    if (rst) begin
      rdata <= '0;
    end else begin
      rdata <= rdata_tmp;
    end
  end
endmodule
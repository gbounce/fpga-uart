module uart_rx #(
  parameter int  CLK_FREQ  = 100E6,
  parameter int  NCO_WIDTH = 16,
  parameter int  BAUD_RATE = 115200,
  parameter      PARITY    = "ODD")
(
  input  logic       clk,
  input  logic       rst,
  input  logic       uart_rx,
  output logic       rdata_vld,
  output logic [7:0] rdata
);

  localparam real CLK_PER  = 1.0/CLK_FREQ;
  localparam real BAUD_PER = 1.0/(BAUD_RATE*16);
  localparam int  NCO_INCR = int'(2**NCO_WIDTH / (BAUD_PER / CLK_PER));

  (* ASYNC_REG = "TRUE" *) logic [1:0] uart_rx_sync_sr;
  logic uart_rx_sync;

  logic [7:0] start_bit_det_sr;
  logic       start_bit_det;

  logic [NCO_WIDTH-1:0] nco_accum = '0;
  logic                 baud_rx_en;

  logic [3:0]           center_sample_cnt;
  logic [3:0]           bit_cnt;

  logic                 bit_vld;
  logic                 busy;

  logic [9:0]           rdata_sr;
  logic                 calc_parity;

  // nco, 16x baud rx oversample
  always_ff @(posedge clk) begin
    {baud_rx_en, nco_accum} <= nco_accum + NCO_INCR;
  end

  // metafilter
  always_ff @(posedge clk) begin
    uart_rx_sync_sr <= {uart_rx_sync_sr[0], uart_rx};
  end

  assign uart_rx_sync = uart_rx_sync_sr[1];

  always_ff @(posedge clk) begin
    if (rst) begin
      start_bit_det_sr <= '0;
    end else if (baud_rx_en) begin
      start_bit_det_sr <= {start_bit_det_sr[$size(start_bit_det_sr)-1], uart_rx_sync};
    end
  end

  assign start_bit_det = ~|start_bit_det_sr;

  always_ff @(posedge clk) begin
    if (rst) begin
      busy <= 1'b0;
    end else begin
      if (start_bit_det) begin
        busy <= 1'b1;
      end else if (baud_rx_en && bit_cnt == 9) begin
        busy <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      center_sample_cnt <= '0;
      bit_vld           <= 1'b0;
    end else if (baud_rx_en) begin
      bit_vld           <= 1'b0;
      center_sample_cnt <= '0;

      if (busy) begin
        if (center_sample_cnt < 15) begin
          center_sample_cnt++;
          bit_vld <= 1'b1;
        end else begin
          center_sample_cnt <= '0;
        end
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      bit_cnt   <= '0;
      rdata_vld <= 1'b0;
    end else begin
      rdata_vld <= 1'b0;

      if (baud_rx_en && bit_vld) begin
        if (bit_cnt < 9) begin
          bit_cnt++;
        end else begin
          bit_cnt <= '0;

          if (rdata[8] == calc_parity && rdata[9]) begin
            rdata_vld <= 1'b1;
          end
        end
      end
    end
  end

  always_ff @(posedge clk) begin
    if (baud_rx_en && bit_vld) begin
      rdata_sr <= {rdata_sr[$size(rdata_sr)-1:0], uart_rx};
    end
  end

  assign calc_parity = (PARITY == "ODD") ? ^rdata_sr[$size(rdata_sr)-1:1] : ~^rdata_sr[$size(rdata_sr)-1:1];
  assign rdata       = rdata_sr[2:9];

endmodule

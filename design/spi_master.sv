// SPI master, mode 0 (clock rests low, data read on the rising edge,
// changed on the falling edge). Sends and receives one byte per transfer,
// most significant bit first.
//
// SCLK frequency = i_Clk frequency / (2 * CLKS_PER_HALF_BIT)

module spi_master #(
  parameter int CLKS_PER_HALF_BIT = 2
) (
  input  logic       i_Clk,
  input  logic       i_Rst_n,

  // Inside the FPGA
  input  logic [7:0] i_Tx_Byte,
  input  logic       i_Tx_Start,
  output logic       o_Busy,
  output logic [7:0] o_Rx_Byte,
  output logic       o_Rx_Done,

  // To the peripheral
  output logic       o_SPI_Clk,
  output logic       o_SPI_MOSI,
  input  logic       i_SPI_MISO,
  output logic       o_SPI_CS_n
);

  typedef enum logic [1:0] {IDLE, TRANSFER, DONE} state_t;
  state_t r_State;

  logic [$clog2(CLKS_PER_HALF_BIT)-1:0] r_Half_Cnt;
  logic [2:0] r_Bit_Cnt;
  logic       r_SPI_Clk;
  logic [7:0] r_Tx_Shift;
  logic [7:0] r_Rx_Shift;

  // End of a half bit, and which way SCLK is about to change
  wire w_End_Half = (r_State == TRANSFER) && (r_Half_Cnt == CLKS_PER_HALF_BIT - 1);
  wire w_Rising   = w_End_Half & (r_SPI_Clk == 1'b0);
  wire w_Falling  = w_End_Half & (r_SPI_Clk == 1'b1);

  always_ff @(posedge i_Clk or negedge i_Rst_n) begin
    if (!i_Rst_n) begin
      r_State    <= IDLE;
      r_Half_Cnt <= '0;
      r_Bit_Cnt  <= '0;
      r_SPI_Clk  <= 1'b0;
      r_Tx_Shift <= '0;
      r_Rx_Shift <= '0;
      o_SPI_CS_n <= 1'b1;
      o_Rx_Byte  <= '0;
      o_Rx_Done  <= 1'b0;
    end else begin
      o_Rx_Done <= 1'b0;

      case (r_State)
        IDLE: begin
          r_Half_Cnt <= '0;
          r_Bit_Cnt  <= '0;
          r_SPI_Clk  <= 1'b0;
          if (i_Tx_Start) begin
            r_Tx_Shift <= i_Tx_Byte;      // bit 7 goes out on MOSI straight away
            o_SPI_CS_n <= 1'b0;
            r_State    <= TRANSFER;
          end
        end

        TRANSFER: begin
          // SCLK generator
          if (w_End_Half) begin
            r_Half_Cnt <= '0;
            r_SPI_Clk  <= ~r_SPI_Clk;
          end else begin
            r_Half_Cnt <= r_Half_Cnt + 1'b1;
          end

          // Rising edge: read MISO into the bottom of the receive register
          if (w_Rising)
            r_Rx_Shift <= {r_Rx_Shift[6:0], i_SPI_MISO};

          // Falling edge: move the next bit up to MOSI, count the bit
          if (w_Falling) begin
            r_Tx_Shift <= {r_Tx_Shift[6:0], 1'b0};
            if (r_Bit_Cnt == 3'd7) begin
              o_SPI_CS_n <= 1'b1;
              r_State    <= DONE;
            end else begin
              r_Bit_Cnt <= r_Bit_Cnt + 1'b1;
            end
          end
        end

        DONE: begin
          o_Rx_Byte <= r_Rx_Shift;
          o_Rx_Done <= 1'b1;
          r_State   <= IDLE;
        end

        default: r_State <= IDLE;
      endcase
    end
  end

  assign o_SPI_Clk  = r_SPI_Clk;
  assign o_SPI_MOSI = r_Tx_Shift[7];
  assign o_Busy     = (r_State != IDLE);

endmodule
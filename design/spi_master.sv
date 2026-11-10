// SPI master, all 4 modes. Sends and receives one byte per transfer,
// most significant bit first.
//
// CPOL: level of SCLK when idle (0 = low, 1 = high)
// CPHA: 0 = data read on the first edge of each clock pulse, changed on the second
//       1 = data changed on the first edge, read on the second
// Mode 0: CPOL 0, CPHA 0   Mode 1: CPOL 0, CPHA 1
// Mode 2: CPOL 1, CPHA 0   Mode 3: CPOL 1, CPHA 1
//
// SCLK frequency = i_Clk frequency / (2 * CLKS_PER_HALF_BIT), CLKS_PER_HALF_BIT >= 2

module spi_master #(
  parameter int CLKS_PER_HALF_BIT = 2,
  parameter bit CPOL = 0,
  parameter bit CPHA = 0
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
  logic [2:0] r_Bit_Cnt;      // number of second edges so far in this byte
  logic       r_SPI_Clk;      // internal clock, always rests at 0
  logic [7:0] r_Tx_Shift;
  logic [7:0] r_Rx_Shift;

  // End of a half bit, and which edge of the clock pulse comes next
  wire w_End_Half    = (r_State == TRANSFER) && (r_Half_Cnt == CLKS_PER_HALF_BIT - 1);
  wire w_First_Edge  = w_End_Half & (r_SPI_Clk == 1'b0);
  wire w_Second_Edge = w_End_Half & (r_SPI_Clk == 1'b1);

  // Which edge reads MISO and which edge moves the next bit onto MOSI.
  // With CPHA = 1 the very first edge does not shift: bit 7 is already on MOSI.
  wire w_Read_Edge  = CPHA ? w_Second_Edge : w_First_Edge;
  wire w_Shift_Edge = CPHA ? (w_First_Edge && (r_Bit_Cnt != 3'd0)) : w_Second_Edge;

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

          // Read MISO into the bottom of the receive register
          if (w_Read_Edge)
            r_Rx_Shift <= {r_Rx_Shift[6:0], i_SPI_MISO};

          // Move the next bit up to MOSI
          if (w_Shift_Edge)
            r_Tx_Shift <= {r_Tx_Shift[6:0], 1'b0};

          // Count clock pulses on the second edge; the byte ends on the 8th
          if (w_Second_Edge) begin
            if (r_Bit_Cnt == 3'd7)
              r_State <= DONE;
            else begin
              r_Bit_Cnt <= r_Bit_Cnt + 1'b1;
            end
          end
        end

        DONE: begin
          o_SPI_CS_n <= 1'b1;         // one clock after the last edge, so the last bit is read first
          o_Rx_Byte  <= r_Rx_Shift;
          o_Rx_Done  <= 1'b1;
          r_State    <= IDLE;
        end

        default: r_State <= IDLE;
      endcase
    end
  end

  assign o_SPI_Clk  = r_SPI_Clk ^ CPOL;   // CPOL = 1 turns the idle-low clock into idle-high
  assign o_SPI_MOSI = r_Tx_Shift[7];
  assign o_Busy     = (r_State != IDLE);

endmodule
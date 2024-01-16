`include "param.v"
// `include "./riscv/src/param.v"
// `include "./riscv/src/icache.v"

module memCtrl #(
  parameter ICACHE_BLK_SIZE = 64
)(
    input wire clk,       // system clock signal
    input wire rst_in,    // reset signal
    input wire rdy_in,    // ready signal, pause cpu when low
    input wire roll_back, // wrong prediction signal

    input wire io_buffer_full,  // 1 if uart buffer is full

    // RAM
    input  wire [       7:0] mem_din,   // read data from ram
    output wire              mem_rw,    // write/read signal (1 for write)
    output wire [       7:0] mem_dout,  // write data to ram
    output wire [`MEM_WIDTH] mem_aout,  // address to ram (only 17:0 is used)

    // Instruction Unit
    input  wire [ `ADDR_WIDTH] if_ain,           // address from instruction unit
    output wire                if_instr_out_en,
    output wire [`INSTR_WIDTH] if_instr_out,     // instruction to instruction unit

    // Load Store Buffer
    input  wire               lsb_rw,       // write/read signal (1 for write)
    input  wire [        1:0] lsb_d_type,   // 2'b00 None/2'b01 Byte/2'b10 Half/2'b11 Word
    input  wire [`ADDR_WIDTH] lsb_ain,
    input  wire [`DATA_WIDTH] lsb_din,
    output wire               lsb_dout_en,
    output wire [`DATA_WIDTH] lsb_dout,
    output wire               lsb_w_done
);

  parameter IDLE = 0, IF = 1, LOAD = 2, STORE = 3;

  reg  [              1:0 ] status;
  reg  [              6:0 ] stage;
  reg  [              6:0 ] steps;

  reg  [      `ADDR_WIDTH]  store_a;

  // Interface-related reg
  reg                       q_mem_rw;
  reg  [              7:0 ] q_mem_dout;
  reg  [       `MEM_WIDTH]  q_mem_aout;

  reg                       q_lsb_dout_en;
  reg  [      `DATA_WIDTH]  q_lsb_dout;
  reg                       q_lsb_w_done;

  // conserve LOAD/STORE status
  reg               q_lsb_rw;
  reg [        1:0] q_lsb_d_type;
  reg [`ADDR_WIDTH] q_lsb_ain;
  reg [`DATA_WIDTH] q_lsb_din;

  wire               lsb_rw_conv = (lsb_d_type != 2'b00) ? lsb_rw : q_lsb_rw;
  wire [        1:0] lsb_d_type_conv = (lsb_d_type != 2'b00) ? lsb_d_type : q_lsb_d_type;
  wire [`ADDR_WIDTH] lsb_ain_conv = (lsb_d_type != 2'b00) ? lsb_ain : q_lsb_ain;
  wire [`DATA_WIDTH] lsb_din_conv = (lsb_d_type != 2'b00) ? lsb_din : q_lsb_din;


  // ICache input 
  reg                       mem2icache_in_en;
  reg  [      `ADDR_WIDTH]  mem2icache_ain;
  wire [`ICACHE_BLK_WIDTH]  mem2icache_din;
  reg  [              7:0 ] mem2icache_din_  [ICACHE_BLK_SIZE-1:0];

  genvar _i;
  generate
    for (_i = 0; _i < ICACHE_BLK_SIZE; _i = _i + 1) begin
      assign mem2icache_din[_i*8+7:_i*8] = mem2icache_din_[_i];
    end
  endgenerate

  iCache icache (
      .clk            (clk),
      .rst_in         (rst_in),
      .mem_in_en      (mem2icache_in_en),
      .mem_ain        (mem2icache_ain),
      .mem_din        (mem2icache_din),
      .if_ain         (if_ain),
      .if_instr_out_en(if_instr_out_en),
      .if_instr_out   (if_instr_out)
  );

  integer i;
  always @(posedge clk) begin
    if (rst_in) begin
      status <= IDLE;
      q_mem_rw <= 0;
      q_mem_dout <= 0;
      q_mem_aout <= 0;
      q_lsb_dout_en <= 0;
      q_lsb_dout <= 0;
      q_lsb_w_done <= 0;
      mem2icache_in_en <= 0;
    end else if (!rdy_in) begin
      // nothing
    end else begin
      q_mem_rw <= 0;
      case (status)
        IDLE: begin
          if (mem2icache_in_en || q_lsb_dout_en || q_lsb_w_done) begin
            mem2icache_in_en <= 0;
            q_lsb_dout_en <= 0;
            q_lsb_w_done <= 0;
          end else if (!roll_back) begin
            if (lsb_d_type_conv != 2'b00) begin  // load & store first
              if (lsb_rw_conv) begin
                // synchronize
                status  <= STORE;
                store_a <= lsb_ain;
              end else begin
                status <= LOAD;
                q_mem_aout <= lsb_ain;
                q_lsb_dout <= 0;
              end
              stage <= 0;
              case (lsb_d_type_conv)
                2'b01: steps <= 1;
                2'b10: steps <= 2;
                2'b11: steps <= 4;
              endcase
            end else if (!if_instr_out_en) begin
              status <= IF;
              stage <= 0;
              steps <= 64;
              mem2icache_ain <= if_ain;
              q_mem_aout <= {if_ain[`ICACHE_TAG_RANGE], if_ain[`ICACHE_IDX_RANGE], 6'b0};
            end
          end
        end

        IF: begin
          if (stage != 0) mem2icache_din_[stage-1] <= mem_din;
          if (stage + 1 == steps) q_mem_aout <= 0;
          else q_mem_aout <= q_mem_aout + 1;
          if (stage == steps) begin
            status <= IDLE;
            stage <= 0;
            q_mem_rw <= 0;
            q_mem_aout <= 0;
            mem2icache_in_en <= 1;
          end else begin
            stage <= stage + 1;
          end
        end

        LOAD: begin
          if (roll_back) begin
            status <= IDLE;
            stage <= 0;
            q_mem_rw <= 0;
            q_mem_aout <= 0;
            q_lsb_dout_en <= 0;
            q_lsb_w_done <= 0;
          end else begin
            case (stage)
              1: q_lsb_dout[7:0] <= mem_din;
              2: q_lsb_dout[15:8] <= mem_din;
              3: q_lsb_dout[23:16] <= mem_din;
              4: q_lsb_dout[31:24] <= mem_din;
            endcase
            if (stage + 1 == steps) q_mem_aout <= 0;
            else q_mem_aout <= q_mem_aout + 1;
            if (stage == steps) begin
              status <= IDLE;
              stage <= 0;
              q_mem_rw <= 0;
              q_mem_aout <= 0;
              q_lsb_d_type <= 2'b00;
              q_lsb_dout_en <= 1;
            end else begin
              stage <= stage + 1;
            end
          end
        end

        STORE: begin
          if (store_a[17:16] != 2'b11 || !io_buffer_full) begin
            q_mem_rw <= 1;
            case (stage)  // little-endian
              0: q_mem_dout <= lsb_din[7:0];
              1: q_mem_dout <= lsb_din[15:8];
              2: q_mem_dout <= lsb_din[23:16];
              3: q_mem_dout <= lsb_din[31:24];
            endcase
            if (stage == 0) q_mem_aout <= store_a;
            else q_mem_aout <= q_mem_aout + 1;
            if (stage == steps) begin
              status <= IDLE;
              stage <= 0;
              q_mem_rw <= 0;
              q_mem_aout <= 0;
              q_lsb_d_type <= 2'b00;
              q_lsb_w_done <= 1;
            end else begin
              stage <= stage + 1;
            end
          end
        end
      endcase

      if(lsb_d_type != 2'b00) begin
        q_lsb_rw <= lsb_rw;
        q_lsb_d_type <= lsb_d_type;
        q_lsb_ain <= lsb_ain;
        q_lsb_din <= lsb_din;
      end
    end
  end

  assign mem_rw = q_mem_rw;
  assign mem_dout = q_mem_dout;
  assign mem_aout = q_mem_aout;

  assign lsb_dout_en = q_lsb_dout_en;
  assign lsb_dout = q_lsb_dout;
  assign lsb_w_done = q_lsb_w_done;
endmodule

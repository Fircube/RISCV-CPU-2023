`include "./riscv/src/param.v"
`include "./riscv/src/icache.v"

module memCtrl (
    input wire clk,     // system clock signal
    input wire rst_in,  // reset signal
    input wire rdy_in,  // ready signal, pause cpu when low

    input wire io_buffer_full,  // 1 if uart buffer is full

    // RAM
    input  wire [       7:0] mem_din,   // read data from ram
    output wire              mem_rw,    // write/read signal (1 for write)
    output wire [       7:0] mem_dout,  // write data to ram
    output wire [`MEM_WIDTH] mem_aout,  // address to ram (only 17:0 is used)


    // Load Store Buffer
    input  wire               lsb_in_en,
    input  wire               lsb_rw,          // write/read signal (1 for write)
    input  wire [        1:0] lsb_data_width,
    input  wire [`ADDR_WIDTH] lsb_ain,
    input  wire [`DATA_WIDTH] lsb_din,
    output wire               lsb_out_en,
    output wire [`DATA_WIDTH] lsb_dout,


    // Instruction Unit
    input  wire                if_in_en,
    input  wire [ `ADDR_WIDTH] if_ain,       // address from instruction unit
    output wire                if_out_en,
    output wire [`INSTR_WIDTH] if_instr_out  // instruction to instruction unit

);

  parameter IDLE = 0, IF = 1, LOAD = 2, STORE = 3;

  reg  [              1:0 ] status;
  reg  [              5:0 ] stage;
  reg  [              5:0 ] steps;


  reg                       q_mem_rw;
  reg  [              7:0 ] q_mem_dout;
  reg  [       `MEM_WIDTH]  q_mem_aout;

  reg                       q_lsb_out_en;
  reg  [      `DATA_WIDTH]  q_lsb_dout;

  reg                       q_if_out_en;

  //
  reg  [      `ADDR_WIDTH]  store_a;
  // ICache input 
  reg                       icache_mem_in_en;
  reg  [      `ADDR_WIDTH]  icache_mem_ain;
  wire [`ICACHE_BLK_WIDTH]  icache_mem_din;
  reg  [              7:0 ] icache_mem_din_  [`ICACHE_BLK_SIZE:0];

  // ICache output 
  wire                      icacheMiss;

  genvar _i;
  generate
    for (_i = 0; _i < `ICACHE_BLK_INSTR; _i = _i + 1) begin
      assign icache_mem_din[(_i+1)*8-1:_i*8] = icache_mem_din_[_i];
    end
  endgenerate

  iCache icache (
      .clk         (clk),
      .rst_in      (rst_in),
      .if_ain      (if_ain),
      .mem_in_en   (icache_mem_in_en),
      .mem_ain     (icache_mem_ain),
      .mem_din     (icache_mem_din),
      .miss        (icacheMiss),
      .if_out_en   (if_out_en),
      .if_instr_out(if_instr_out)
  );

  always @(posedge clk) begin
    if (rst_in) begin
      status <= IDLE;
      q_mem_rw <= 0;
      q_mem_dout <= 0;
      q_mem_aout <= 0;
      q_lsb_out_en <= 0;
      q_if_out_en <= 0;
    end else if (!rdy_in || io_buffer_full) begin
      // nothing
    end else begin
      case (status)
        IDLE: begin
          if (if_out_en || lsb_out_en) begin
            q_if_out_en  <= 0;
            q_lsb_out_en <= 0;
          end else if (lsb_in_en) begin  // load & store first
            if (lsb_rw) begin
              status  <= STORE;
              store_a <= lsb_ain;
            end else begin
              status <= LOAD;
              q_mem_aout <= lsb_ain;
              q_lsb_dout <= 0;
            end
            stage <= 0;
            steps <= {3'b0, lsb_data_width};
          end else if (if_in_en) begin
            if (icacheMiss) begin
              status <= IF;
              q_mem_aout <= if_ain;
              icache_mem_ain <= if_ain;
              stage <= 0;
              steps <= 64;
            end else begin
              status <= IDLE;
              stage <= 0;
              q_mem_rw <= 0;
              q_mem_aout <= 0;
            end
          end
        end
        IF: begin
          if (icacheMiss) begin
            icache_mem_din_[stage] <= mem_din;
            if (stage + 1 == steps) q_mem_aout <= 0;
            else q_mem_aout <= q_mem_aout + 1;
            if (stage == steps) begin
              icache_mem_in_en <= 1;
            end else begin
              stage <= stage + 1;
            end
          end else begin
            status <= IDLE;
            stage <= 0;
            q_if_out_en <= 1;
            q_mem_rw <= 0;
            q_mem_aout <= 0;
          end
        end
        LOAD: begin
          case (stage)
            1: q_lsb_dout[7:0] <= mem_din;
            2: q_lsb_dout[15:8] <= mem_din;
            3: q_lsb_dout[23:16] <= mem_din;
            4: q_lsb_dout[31:24] <= mem_din;
          endcase
          if (stage + 1 == steps) q_mem_aout <= 0;
          else q_mem_aout <= q_mem_aout + 1;
          if (stage == 0) q_mem_aout = store_a;
          else q_mem_aout = q_mem_aout + 1;
          if (stage == steps) begin
            status <= IDLE;
            stage <= 0;
            q_lsb_out_en <= 1;
            q_mem_rw <= 0;
            q_mem_aout <= 0;
          end else begin
            stage <= stage + 1;
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
              q_lsb_out_en <= 1;
              q_mem_rw <= 0;
              q_mem_aout <= 0;
            end else begin
              stage <= stage + 1;
            end
          end
        end
      endcase
    end
  end

  assign mem_rw = q_mem_rw;
  assign mem_dout = q_mem_dout;
  assign mem_aout = q_mem_aout;
  assign lsb_out_en = q_lsb_out_en;
  assign lsb_dout = q_lsb_dout;
  assign if_out_en = q_if_out_en;


endmodule

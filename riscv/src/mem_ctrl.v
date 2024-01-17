`include "param.v"
// `include "./riscv/src/param.v"
// `include "./riscv/src/icache.v"
// `include "./riscv/src/dcache.v"
module memCtrl #(
    parameter ICACHE_SIZE = 16,
    parameter ICACHE_BLK_INSTR = 4,
    parameter DCACHE_SIZE = 8,
    parameter DCACHE_BLK_DATA = 16
) (
    input wire clk,       // system clock signal
    input wire rst_in,    // reset signal
    input wire rdy_in,    // ready signal, pause cpu when low
    input wire roll_back, // wrong prediction signal

    input wire io_buffer_full,

    input  wire [        7:0] mem_din,
    output wire               mem_rw,
    output wire [`ADDR_WIDTH] mem_aout,
    output wire [        7:0] mem_dout,

    // IF
    input  wire [ `ADDR_WIDTH] if_ain,
    output wire                if_instr_out_en,
    output wire [`INSTR_WIDTH] if_instr_out,

    // LSB
    input wire lsb_rw,
    input wire [1:0] lsb_d_type,
    input wire [31:0] lsb_ain,
    input wire [31:0] lsb_din,

    output wire        lsb_dout_en,
    output wire [31:0] lsb_dout,
    output wire        lsb_w_done
);

  parameter IDLE = 0, IF = 1, LOAD = 2, STORE = 3;

  reg [3:0] stage;
  reg [6:0] steps;
  reg [1:0] status;
  reg [1:0] IO_status;

  wire is_IO = (lsb_d_type_conv != 2'b00) && (lsb_ain_conv[17:16] == 2'b11);

  reg q_mem_rw;
  reg [7:0] q_mem_dout;
  reg [31:0] q_mem_aout;

  reg [31:4] mem2cache_a;
  reg [`CACHE_BLK_WIDTH] mem2cache_d;

  // ICache input 
  reg mem2icache_in_en;
  wire [31:4] mem2icache_ain = mem2cache_a;
  wire [`CACHE_BLK_WIDTH] mem2icache_din = mem2cache_d;

  // DCache input 
  reg mem2dcache_in_en;
  wire [31:4] mem2dcache_ain = mem2cache_a;
  wire [`CACHE_BLK_WIDTH] mem2dcache_din = mem2cache_d;
  reg q_mem_w_done;
  reg q_IO_din_en;
  reg q_IO_w_done;

  // DCache output wires
  wire dCache_miss;
  wire [31:4] dCache_miss_a;
  wire dCache_rw_out;
  wire [`CACHE_BLK_WIDTH] dcache_write_back_en;

  // conserve LOAD/STORE status
  reg q_lsb_rw;
  reg [1:0] q_lsb_d_type;
  reg [`ADDR_WIDTH] q_lsb_ain;
  reg [`DATA_WIDTH] q_lsb_din;

  wire lsb_rw_conv = (lsb_d_type != 2'b00) ? lsb_rw : q_lsb_rw;
  wire [1:0] lsb_d_type_conv = (lsb_d_type != 2'b00) ? lsb_d_type : q_lsb_d_type;
  wire [`ADDR_WIDTH] lsb_ain_conv = (lsb_d_type != 2'b00) ? lsb_ain : q_lsb_ain;
  wire [`DATA_WIDTH] lsb_din_conv = (lsb_d_type != 2'b00) ? lsb_din : q_lsb_din;

  reg ls_proceeding;
  reg IO_proceeding;
  reg ls_done;
  reg IO_done;
  reg ID;  // ICache: 1, Dcache: 0
  reg rw;  // read: 0, write: 1
  reg idle;
  reg idle_;

  iCache icache (
      .clk            (clk),
      .rst_in         (rst_in),
      .if_ain         (if_ain),
      .mem_in_en      (mem2icache_in_en),
      .mem_ain        (mem2icache_ain),
      .mem_din        (mem2icache_din),
      .if_instr_out_en(if_instr_out_en),
      .if_instr_out   (if_instr_out)
  );

  dCache dcache (
      .clk      (clk),
      .rst_in   (rst_in),
      .roll_back(roll_back),
      .rdy_in   (rdy_in),

      .lsb_rw    (lsb_rw),
      .lsb_d_type(lsb_d_type),
      .lsb_ain   (lsb_ain),
      .lsb_din   (lsb_din),

      .mem_in_en(mem2dcache_in_en),
      .mem_ain  (mem2dcache_ain),
      .mem_din  (mem2dcache_din),

      .mem_w_done(q_mem_w_done),

      .IO_din_en(q_IO_din_en),
      .IO_din   (q_lsb_din),
      .IO_w_done(q_IO_w_done),

      .miss_a(dCache_miss_a),
      .miss  (dCache_miss),

      .mem_rw       (dCache_rw_out),
      .write_back_en(dcache_write_back_en),

      .lsb_dout_en(lsb_dout_en),
      .lsb_dout   (lsb_dout),
      .lsb_w_done (lsb_w_done)
  );

  always @(posedge clk) begin
    if (rst_in) begin
      ls_proceeding    <= 0;
      ls_done          <= 0;
      rw               <= 1;
      idle             <= 0;
      idle_            <= 0;
      stage            <= 0;
      IO_done          <= 0;
      IO_proceeding    <= 0;
      IO_status        <= 2'b00;
      q_mem_rw         <= 0;
      q_IO_din_en      <= 0;
      q_IO_w_done      <= 0;
      q_lsb_ain        <= 32'b0;
      q_lsb_d_type     <= 2'b00;
      q_lsb_din        <= 32'b0;
      q_lsb_rw         <= 1'b0;
      mem2cache_a      <= 28'b0;
      mem2cache_d      <= 128'b0;
      mem2icache_in_en <= 0;
      mem2dcache_in_en <= 0;
      q_mem_dout       <= 8'b0;
      q_mem_aout       <= 32'b0;
      ID               <= 0;
    end else if (rdy_in) begin
      if (lsb_d_type != 2'b00) begin
        q_lsb_ain    <= lsb_ain;
        q_lsb_d_type <= lsb_d_type;
        q_lsb_din    <= lsb_din;
        q_lsb_rw     <= lsb_rw;
      end

      if (ls_done) begin
        mem2cache_d[16*8-1:16*8-8] <= mem_din;
        if (rw) begin
          if (ID) begin
            mem2icache_in_en <= 1;
          end else begin
            mem2dcache_in_en <= 1;
          end
        end else begin
          q_mem_rw <= 0;
          q_mem_w_done <= 1;
        end
        ls_done <= 1'b0;
      end else begin
        mem2icache_in_en <= 0;
        mem2dcache_in_en <= 0;
        q_mem_w_done <= 0;
      end

      if (IO_done) begin
        if (!lsb_rw_conv) begin
          q_IO_din_en <= 1;
          case (lsb_d_type_conv)
            2'b01: q_lsb_din[7:0] <= mem_din;
            2'b10: q_lsb_din[15:8] <= mem_din;
            2'b11: q_lsb_din[31:24] <= mem_din;
          endcase
        end else begin
          q_IO_w_done <= 1;
        end
        IO_done <= 0;
        q_mem_rw <= 0;
        q_lsb_d_type <= 2'b00;
      end else begin
        q_IO_din_en <= 0;
        q_IO_w_done <= 0;
      end

      // if(rw) begin
      // end else begin
      // end
      // if (stage != 0) mem2icache_din_[stage-1] <= mem_din;
      // if (stage + 1 == steps) q_mem_aout <= 0;
      // else q_mem_aout <= q_mem_aout + 1;
      // if (stage == steps) begin
      //   status <= IDLE;
      //   stage <= 0;
      //   q_mem_rw <= 0;
      //   q_mem_aout <= 0;
      //   mem2icache_in_en <= 1;
      // end else begin
      //   stage <= stage + 1;
      // end
      // load the memory
      
      if (ls_proceeding) begin
        q_mem_w_done <= 0;
        if (rw) begin
          case (stage)
            4'b1111: begin
              ls_proceeding                        <= 0;
              idle                                 <= 1;
              stage                                <= 0;
              ls_done                              <= 1;
              mem2cache_d[4'b1111*8-1:4'b1111*8-8] <= mem_din;
            end
            4'b1110: begin
              stage <= 4'b1111;
              mem2cache_d[4'b1110*8-1:4'b1110*8-8] <= mem_din;
              q_mem_aout <= {mem2cache_a, 4'b1111};
            end
            4'b1101: begin
              stage <= 4'b1110;
              mem2cache_d[4'b1101*8-1:4'b1101*8-8] <= mem_din;
              q_mem_aout <= {mem2cache_a, 4'b1110};
            end
            4'b1100: begin
              stage <= 4'b1101;
              mem2cache_d[4'b1100*8-1:4'b1100*8-8] <= mem_din;
              q_mem_aout <= {mem2cache_a, 4'b1101};
            end
            4'b1011: begin
              stage <= 4'b1100;
              mem2cache_d[4'b1011*8-1:4'b1011*8-8] <= mem_din;
              q_mem_aout <= {mem2cache_a, 4'b1100};
            end
            4'b1010: begin
              stage <= 4'b1011;
              mem2cache_d[4'b1010*8-1:4'b1010*8-8] <= mem_din;
              q_mem_aout <= {mem2cache_a, 4'b1011};
            end
            4'b1001: begin
              stage <= 4'b1010;
              mem2cache_d[4'b1001*8-1:4'b1001*8-8] <= mem_din;
              q_mem_aout <= {mem2cache_a, 4'b1010};
            end
            4'b1000: begin
              stage <= 4'b1001;
              mem2cache_d[4'b1000*8-1:4'b1000*8-8] <= mem_din;
              q_mem_aout <= {mem2cache_a, 4'b1001};
            end
            4'b0111: begin
              stage <= 4'b1000;
              mem2cache_d[4'b0111*8-1:4'b0111*8-8] <= mem_din;
              q_mem_aout <= {mem2cache_a, 4'b1000};
            end
            4'b0110: begin
              stage <= 4'b0111;
              mem2cache_d[4'b0110*8-1:4'b0110*8-8] <= mem_din;
              q_mem_aout <= {mem2cache_a, 4'b0111};
            end
            4'b0101: begin
              stage <= 4'b0110;
              mem2cache_d[4'b0101*8-1:4'b0101*8-8] <= mem_din;
              q_mem_aout <= {mem2cache_a, 4'b0110};
            end
            4'b0100: begin
              stage <= 4'b0101;
              mem2cache_d[4'b0100*8-1:4'b0100*8-8] <= mem_din;
              q_mem_aout <= {mem2cache_a, 4'b0101};
            end
            4'b0011: begin
              stage <= 4'b0100;
              mem2cache_d[4'b0011*8-1:4'b0011*8-8] <= mem_din;
              q_mem_aout <= {mem2cache_a, 4'b0100};
            end
            4'b0010: begin
              stage <= 4'b0011;
              mem2cache_d[4'b0010*8-1:4'b0010*8-8] <= mem_din;
              q_mem_aout <= {mem2cache_a, 4'b0011};
            end
            4'b0001: begin
              stage <= 4'b0010;
              mem2cache_d[4'b0001*8-1:4'b0001*8-8] <= mem_din;
              q_mem_aout <= {mem2cache_a, 4'b0010};
            end
            4'b0000: begin
              stage <= 4'b0001;
              q_mem_aout <= {mem2cache_a, 4'b0001};
            end
          endcase
        end else begin
          case (stage)
            4'b1111: begin
              ls_proceeding <= 0;
              idle          <= 1;
              stage         <= 0;
              ls_done       <= 1;
              q_mem_dout    <= mem2cache_d[16*8-1:16*8-8];
              q_mem_aout    <= {mem2cache_a, 4'b1111};
            end
            4'b1110: begin
              stage <= 4'b1111;
              q_mem_dout <= mem2cache_d[4'b1110*8+7:4'b1110*8];
              q_mem_aout <= {mem2cache_a, 4'b1110};
            end
            4'b1101: begin
              stage <= 4'b1110;
              q_mem_dout <= mem2cache_d[4'b1101*8+7:4'b1101*8];
              q_mem_aout <= {mem2cache_a, 4'b1101};
            end
            4'b1100: begin
              stage <= 4'b1101;
              q_mem_dout <= mem2cache_d[4'b1100*8+7:4'b1100*8];
              q_mem_aout <= {mem2cache_a, 4'b1100};
            end
            4'b1011: begin
              stage <= 4'b1100;
              q_mem_dout <= mem2cache_d[4'b1011*8+7:4'b1011*8];
              q_mem_aout <= {mem2cache_a, 4'b1011};
            end
            4'b1010: begin
              stage <= 4'b1011;
              q_mem_dout <= mem2cache_d[4'b1010*8+7:4'b1010*8];
              q_mem_aout <= {mem2cache_a, 4'b1010};
            end
            4'b1001: begin
              stage <= 4'b1010;
              q_mem_dout <= mem2cache_d[4'b1001*8+7:4'b1001*8];
              q_mem_aout <= {mem2cache_a, 4'b1001};
            end
            4'b1000: begin
              stage <= 4'b1001;
              q_mem_dout <= mem2cache_d[4'b1000*8+7:4'b1000*8];
              q_mem_aout <= {mem2cache_a, 4'b1000};
            end
            4'b0111: begin
              stage <= 4'b1000;
              q_mem_dout <= mem2cache_d[4'b0111*8+7:4'b0111*8];
              q_mem_aout <= {mem2cache_a, 4'b0111};
            end
            4'b0110: begin
              stage <= 4'b0111;
              q_mem_dout <= mem2cache_d[4'b0110*8+7:4'b0110*8];
              q_mem_aout <= {mem2cache_a, 4'b0110};
            end
            4'b0101: begin
              stage <= 4'b0110;
              q_mem_dout <= mem2cache_d[4'b0101*8+7:4'b0101*8];
              q_mem_aout <= {mem2cache_a, 4'b0101};
            end
            4'b0100: begin
              stage <= 4'b0101;
              q_mem_dout <= mem2cache_d[4'b0100*8+7:4'b0100*8];
              q_mem_aout <= {mem2cache_a, 4'b0100};
            end
            4'b0011: begin
              stage <= 4'b0100;
              q_mem_dout <= mem2cache_d[4'b0011*8+7:4'b0011*8];
              q_mem_aout <= {mem2cache_a, 4'b0011};
            end
            4'b0010: begin
              stage <= 4'b0011;
              q_mem_dout <= mem2cache_d[4'b0010*8+7:4'b0010*8];
              q_mem_aout <= {mem2cache_a, 4'b0010};
            end
            4'b0001: begin
              stage <= 4'b0010;
              q_mem_dout <= mem2cache_d[4'b0001*8+7:4'b0001*8];
              q_mem_aout <= {mem2cache_a, 4'b0001};
            end
            4'b0000: begin
              stage <= 4'b0001;
              q_mem_rw <= 1'b1;
              q_mem_dout <= mem2cache_d[4'b0000*8+7:4'b0000*8];
              q_mem_aout <= {mem2cache_a, 4'b0000};
            end
          endcase
        end
      end else if (idle) begin
        // two cycle for mem
        if (idle_) begin
          idle  <= 0;
          idle_ <= 0;
        end else begin
          idle_ <= 1;
        end
      end else if (IO_proceeding) begin
        if (!lsb_rw_conv || !io_buffer_full) begin
          case (IO_status)
            2'b00: begin
              q_mem_aout <= lsb_ain_conv + 1;
              IO_status  <= 2'b01;
              if (lsb_d_type_conv == 2'b01) begin
                IO_done <= 1;
                IO_proceeding <= 0;
              end
            end
            2'b01: begin
              q_mem_aout <= lsb_ain_conv + 2;
              IO_status  <= 2'b10;
              if (!lsb_rw_conv) q_lsb_din[7:0] <= mem_din;
              else q_mem_dout <= lsb_din_conv[15:8];
              if (lsb_d_type_conv == 2'b10) begin
                IO_done <= 1;
                IO_proceeding <= 0;
              end
            end
            2'b10: begin
              q_mem_aout <= lsb_ain_conv + 3;
              IO_status  <= 2'b11;
              if (!lsb_rw_conv) q_lsb_din[15:8] <= mem_din;
              else q_mem_dout <= lsb_din_conv[23:16];
            end
            2'b11: begin
              IO_done <= 1;
              IO_proceeding <= 0;
              if (!lsb_rw_conv) begin
                q_lsb_din[23:16] <= mem_din;
                q_mem_aout       <= 32'b0;
              end else begin
                q_mem_dout <= lsb_din_conv[31:24];
                q_mem_aout <= lsb_ain_conv + 4;
              end
            end
          endcase
        end
      end else if (is_IO && !IO_done) begin
        if (!lsb_rw_conv || !io_buffer_full) begin
          IO_status     <= !lsb_rw_conv ? 2'b00 : 2'b01;
          IO_proceeding <= !lsb_rw_conv == 1 || lsb_d_type_conv != 2'b01;
          IO_done       <= !lsb_rw_conv == 0 && lsb_d_type_conv == 2'b01;
          q_mem_rw      <= lsb_rw_conv;
          q_mem_aout    <= lsb_ain_conv;
          if (lsb_rw_conv) q_mem_dout <= lsb_din_conv[7:0];
        end
      end else if (dCache_miss) begin  // dcache first
        rw  <= dCache_rw_out;
        ID <= 0;
        ls_proceeding    <= 1;
        stage   <= 0;
        if (dCache_rw_out) begin  
          mem2cache_a <= dCache_miss_a;
          q_mem_aout  <= {dCache_miss_a, 4'b0000};
        end else begin  
          mem2cache_a <= dCache_miss_a;
          mem2cache_d <= dcache_write_back_en;
          q_mem_aout  <= 32'b0;
        end
      end else if (!if_instr_out_en) begin
        rw            <= 1; 
        ID            <= 1;
        ls_proceeding <= 1;
        stage         <= 0;
        mem2cache_a   <= if_ain[31:4];
        q_mem_aout    <= {if_ain[31:4], 4'b0000};
      end else begin
        q_mem_aout <= 32'b0;
      end
    end
  end

  assign mem_rw   = q_mem_rw;
  assign mem_dout = q_mem_dout;
  assign mem_aout = q_mem_aout;

endmodule

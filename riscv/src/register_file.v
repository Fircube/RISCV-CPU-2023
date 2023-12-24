`include "./riscv/src/param.v"

module regFile (
    input wire clk,     // system clock signal
    input wire rst_in,  // reset signal
    input wire rdy_in,  // ready signal, pause cpu when low

    input wire roll_back,  // wrong prediction signal

    // decoder
    input wire                  de_in_en,
    input wire [`ROB_IDX_WIDTH] de_rob_idx_in,
    input wire [`REG_IDX_WIDTH] de_dest_in,

    input  wire [`REG_IDX_WIDTH] rs1,
    output wire                  rs1_busy,
    output wire [`ROB_IDX_WIDTH] rs1_rob_idx_out,
    output wire [   `DATA_WIDTH] rs1_val_out,
    input  wire [`REG_IDX_WIDTH] rs2,
    output wire                  rs2_busy,
    output wire [`ROB_IDX_WIDTH] rs2_rob_idx_out,
    output wire [   `DATA_WIDTH] rs2_val_out,

    // rob
    input wire                  rob_in_en,
    input wire [`ROB_IDX_WIDTH] rob_idx_in,
    input wire [`REG_IDX_WIDTH] rob_dest_in,
    input wire [   `DATA_WIDTH] rob_val_in

);

  // inner
  reg                      busy   [`REG_WIDTH];
  reg     [`ROB_IDX_WIDTH] rob_idx[`REG_WIDTH];
  reg     [   `DATA_WIDTH] value  [`REG_WIDTH];

  reg     [`REG_IDX_WIDTH] q_rs1;
  reg     [`REG_IDX_WIDTH] q_rs2;

  integer                  i;
  always @(posedge clk) begin
    if (rst_in) begin
      for (i = 0; i < 32; i = i + 1) begin
        value[i]   <= 32'b0;
        busy[i]    <= 1'b0;
        rob_idx[i] <= {`ROB_IDX_SIZE{1'b0}};
      end
      q_rs1 <= {`REG_SIZE{1'b0}};
      q_rs2 <= {`REG_SIZE{1'b0}};
    end else if (!rdy_in) begin
      // nothing
    end else if (roll_back) begin
      for (i = 0; i < 32; i = i + 1) begin
        busy[i] <= 1'b0;
      end
    end else begin
      q_rs1 <= rs1;
      q_rs2 <= rs2;
      if (de_in_en && de_dest_in != 5'b00000) begin
        busy[de_dest_in] <= 1'b1;
        rob_idx[de_dest_in] <= de_rob_idx_in;
      end
      if (rob_in_en && rob_dest_in != 5'b00000) begin // 注意先后次序！ 此处尝试先commit再issue
        if (rob_idx_in == rob_idx[rob_dest_in] && !((de_in_en && de_dest_in == rob_dest_in))) begin
          busy[rob_dest_in] <= 1'b0;
        end
        value[rob_dest_in] <= rob_val_in;
      end
    end
  end

  // ?
  wire rs1_commit = (rob_in_en && rob_dest_in != 5'b00000 && rob_dest_in == q_rs1 && busy[q_rs1] && rob_idx_in == rob_idx[q_rs1]) ;
  wire rs2_commit = (rob_in_en && rob_dest_in != 5'b00000 && rob_dest_in == q_rs2 && busy[q_rs2] && rob_idx_in == rob_idx[q_rs2]) ;
  assign rs1_busy        = rs1_commit ? 1'b0 : busy[q_rs1];
  assign rs1_rob_idx_out = rs1_commit ? {`ROB_IDX_SIZE{1'b0}} : rob_idx[q_rs1];
  assign rs1_val_out     = rs1_commit ? rob_val_in : value[q_rs1];
  assign rs2_busy        = rs2_commit ? 1'b0 : busy[q_rs2];
  assign rs2_rob_idx_out = rs2_commit ? {`ROB_IDX_SIZE{1'b0}} : rob_idx[q_rs2];
  assign rs2_val_out     = rs2_commit ? rob_val_in : value[q_rs2];


endmodule

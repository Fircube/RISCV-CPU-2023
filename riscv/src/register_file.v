`include "param.v"
// `include "./riscv/src/param.v"

module regFile #(
    parameter REG_SIZE = 32
  )(
    input wire clk,     // system clock signal
    input wire rst_in,  // reset signal
    input wire rdy_in,  // ready signal, pause cpu when low

    input wire roll_back,  // wrong prediction signal

    input  wire [`REG_IDX_WIDTH] rs1,
    input  wire [`REG_IDX_WIDTH] rs2,
    output wire [`ROB_IDX_WIDTH] rs1_dep_out,
    output wire [`ROB_IDX_WIDTH] rs2_dep_out,

    // decoder
    input wire                  de_in_en,
    input wire [`REG_IDX_WIDTH] de_dest_in,
    input wire [`ROB_IDX_WIDTH] de_rob_idx_in,

    output wire               de_rs1_busy_out,
    output wire [`DATA_WIDTH] de_rs1_val_out,
    output wire               de_rs2_busy_out,
    output wire [`DATA_WIDTH] de_rs2_val_out,

    // rob
    input wire                  rob_in_en,
    input wire [`ROB_IDX_WIDTH] rob_idx_in,
    input wire [`REG_IDX_WIDTH] rob_dest_in,
    input wire [   `DATA_WIDTH] rob_val_in,

    input wire               rob_rs1_busy_in,
    input wire [`DATA_WIDTH] rob_rs1_val_in,
    input wire               rob_rs2_busy_in,
    input wire [`DATA_WIDTH] rob_rs2_val_in
);

  // internal storage
  reg busy[REG_SIZE-1:0];
  reg [`ROB_IDX_WIDTH] committed[REG_SIZE-1:0];
  reg [`DATA_WIDTH] value[REG_SIZE-1:0];

  // Interface-related reg
  reg [`REG_IDX_WIDTH] q_rs1;
  reg [`REG_IDX_WIDTH] q_rs2;

  wire rs1_issue = de_in_en && (de_dest_in != 5'b00000) && de_dest_in == q_rs1;
  wire rs2_issue = de_in_en && (de_dest_in != 5'b00000) && de_dest_in == q_rs2;
  wire rs1_dep_commit = rob_in_en && (rob_dest_in != 5'b00000) && rob_dest_in == q_rs1 && busy[q_rs1] && rob_idx_in == committed[q_rs1] ;
  wire rs2_dep_commit = rob_in_en && (rob_dest_in != 5'b00000) && rob_dest_in == q_rs2 && busy[q_rs2] && rob_idx_in == committed[q_rs2] ;
  
  assign rs1_dep_out = rs1_issue ? de_rob_idx_in : committed[q_rs1];
  assign rs2_dep_out = rs2_issue ? de_rob_idx_in : committed[q_rs2];
  
  // 先commit再issue
  assign de_rs1_busy_out = rob_rs1_busy_in & (rs1_issue ? 1'b1 : rs1_dep_commit ? 1'b0 : busy[q_rs1]);
  assign de_rs1_val_out = rs1_issue ? rob_rs1_val_in : rs1_dep_commit ? rob_val_in : busy[q_rs1] ? rob_rs1_val_in : value[q_rs1];
  assign de_rs2_busy_out = rob_rs2_busy_in & (rs2_issue ? 1'b1 : rs2_dep_commit ? 1'b0 : busy[q_rs2]);
  assign de_rs2_val_out = rs2_issue ? rob_rs2_val_in : rs2_dep_commit ? rob_val_in : busy[q_rs2] ? rob_rs2_val_in : value[q_rs2];

  integer i;
  always @(posedge clk) begin
    if (rst_in) begin
      for (i = 0; i < 32; i = i + 1) begin
        busy[i]    <= 1'b0;
        committed[i] <= {`ROB_IDX_SIZE{1'b0}};
        value[i]   <= 32'b0;
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
        committed[de_dest_in] <= de_rob_idx_in;
      end
      if (rob_in_en && rob_dest_in != 5'b00000) begin // 注意先后次序！ 此处尝试先commit再issue
        if (rob_idx_in == committed[rob_dest_in] && !(de_in_en && de_dest_in == rob_dest_in)) begin
          busy[rob_dest_in] <= 1'b0;
        end
        value[rob_dest_in] <= rob_val_in;
      end
    end
  end
endmodule

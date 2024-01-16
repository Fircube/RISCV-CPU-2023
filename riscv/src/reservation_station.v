`include "param.v"
// `include "./riscv/src/param.v"

// alu included
module rs #(
    parameter RS_SIZE = 16
) (
    input wire clk,     // system clock signal
    input wire rst_in,  // reset signal
    input wire rdy_in,  // ready signal, pause cpu when low

    input wire roll_back,  // wrong prediction signal

    output wire                  rs_full,
    output wire                  rs2cdb_out_en,
    output wire [`ROB_IDX_WIDTH] rs2cdb_rob_idx_out,
    output wire [   `DATA_WIDTH] rs2cdb_val_out,

    // decoder
    input wire                    de_in_en,
    input wire [`RS_OPCODE_WIDTH] de_op_in,
    input wire [     `DATA_WIDTH] de_Vj_in,
    input wire                    de_Qj_in_en,
    input wire [  `ROB_IDX_WIDTH] de_Qj_in,
    input wire [     `DATA_WIDTH] de_Vk_in,
    input wire                    de_Qk_in_en,
    input wire [  `ROB_IDX_WIDTH] de_Qk_in,
    input wire [  `ROB_IDX_WIDTH] de_rob_idx_in,

    // lsb
    input wire                  lsb_in_en,
    input wire [`ROB_IDX_WIDTH] lsb_rob_idx_in,
    input wire [   `DATA_WIDTH] lsb_val_in
);

  // alu
  reg                    alu_en;
  reg [     `DATA_WIDTH] alu_v1;
  reg [     `DATA_WIDTH] alu_v2;
  reg [`RS_OPCODE_WIDTH] alu_op;
  reg [  `ROB_IDX_WIDTH] alu_rob_idx;
  reg [     `DATA_WIDTH] alu_result;
  //   reg                    alu_jump;


  always @(*) begin
    case (alu_op)
      `RS_ADD:  alu_result = alu_v1 + alu_v2;
      `RS_SUB:  alu_result = alu_v1 - alu_v2;
      `RS_SLL:  alu_result = alu_v1 << alu_v2;
      `RS_SLT:  alu_result = ($signed(alu_v1) < $signed(alu_v2));
      `RS_SLTU: alu_result = (alu_v1 < alu_v2);
      `RS_XOR:  alu_result = alu_v1 ^ alu_v2;
      `RS_SRL:  alu_result = alu_v1 >> alu_v2;
      `RS_SRA:  alu_result = $signed(alu_v1) >> alu_v2;
      `RS_OR:   alu_result = alu_v1 | alu_v2;
      `RS_AND:  alu_result = alu_v1 & alu_v2;
      `RS_BEQ:  alu_result = (alu_v1 == alu_v2);
      `RS_BNE:  alu_result = (alu_v1 != alu_v2);
      `RS_BLT:  alu_result = ($signed(alu_v1) < $signed(alu_v2));
      `RS_BGE:  alu_result = ($signed(alu_v1) >= $signed(alu_v2));
      `RS_BLTU: alu_result = (alu_v1 < alu_v2);
      `RS_BGEU: alu_result = (alu_v1 >= alu_v2);
    endcase
  end
  // alu end

  // internal storage
  reg busy[RS_SIZE-1:0];
  reg [`RS_OPCODE_WIDTH] op[RS_SIZE-1:0];
  reg [`DATA_WIDTH] Vj[RS_SIZE-1:0];
  reg [`ROB_IDX_WIDTH] Qj[RS_SIZE-1:0];
  reg [`DATA_WIDTH] Vk[RS_SIZE-1:0];
  reg [`ROB_IDX_WIDTH] Qk[RS_SIZE-1:0];
  reg [`ROB_IDX_WIDTH] rob_idx[RS_SIZE-1:0];

  reg [RS_SIZE-1:0] Qj_en;
  reg [RS_SIZE-1:0] Qk_en;
  wire [RS_SIZE-1:0] ready = ~Qj_en & ~Qk_en;
  wire work_nxt = (ready != 0);

  reg [3:0] busy_num;
  wire [3:0] busy_num_nxt = busy_num + (de_in_en ? 1'b1 : 1'b0) - (work_nxt ? 1'b1 : 1'b0);
  assign rs_full = (busy_num > 13);

  reg full;
  reg [4:0] nxt_free_idx;
  reg [4:0] nxt_alu_idx;
  wire [`DATA_WIDTH] d_alu_v1 = Vj[nxt_alu_idx];
  wire [`DATA_WIDTH] d_alu_v2 = Vk[nxt_alu_idx];
  wire [`RS_OPCODE_WIDTH] d_alu_op = op[nxt_alu_idx];
  wire [`ROB_IDX_WIDTH] d_alu_rob_idx = rob_idx[nxt_alu_idx];

  // updated value
  wire lsb_j_updated = lsb_in_en && (de_Qj_in == lsb_rob_idx_in);
  wire lsb_k_updated = lsb_in_en && (de_Qk_in == lsb_rob_idx_in);
  wire alu_j_updated = alu_en && (de_Qj_in == alu_rob_idx);
  wire alu_k_updated = alu_en && (de_Qk_in == alu_rob_idx);
  wire cdb_j_updated = q_rs2cdb_out_en && (de_Qj_in == q_rs2cdb_rob_idx_out);
  wire cdb_k_updated = q_rs2cdb_out_en && (de_Qk_in == q_rs2cdb_rob_idx_out);

  wire de_Qj_en_updated = de_Qj_in_en && !lsb_j_updated && !alu_j_updated && !cdb_j_updated;
  wire de_Qk_en_updated = de_Qk_in_en && !lsb_k_updated && !alu_k_updated && !cdb_k_updated;
  wire [`DATA_WIDTH]de_Vj_updated = de_Qj_in_en ? lsb_j_updated ? lsb_val_in : alu_j_updated ? alu_result : cdb_j_updated ? rs2cdb_val_out : 32'b0 : de_Vj_in;
  wire [`DATA_WIDTH]de_Vk_updated = de_Qk_in_en ? lsb_k_updated ? lsb_val_in : alu_k_updated ? alu_result : cdb_k_updated ? rs2cdb_val_out : 32'b0 : de_Vk_in;

  // Interface-related reg
  reg q_rs2cdb_out_en;
  reg [`ROB_IDX_WIDTH] q_rs2cdb_rob_idx_out;
  reg [`DATA_WIDTH] q_rs2cdb_val_out;

  integer j;
  always @(*) begin
    nxt_free_idx = 5'b10000;
    nxt_alu_idx = 5'b10000;
    full = 1;
    for (j = 0; j < `RS_SIZE; j = j + 1) begin
      if (!busy[j]) begin
        if (!de_in_en || nxt_free_idx != 5'b10000) full = 0;
        nxt_free_idx = j;
      end
      if (busy[j] && ready[j]) begin
        nxt_alu_idx = j;
      end
    end
  end

  integer i;
  always @(posedge clk) begin
    if (rst_in || roll_back) begin
      busy_num <= 0;
      Qj_en <= {RS_SIZE{1'b1}};
      Qk_en <= {RS_SIZE{1'b1}};
      alu_en <= 0;
      alu_v1 <= 0;
      alu_v2 <= 0;
      alu_op <= 0;
      alu_rob_idx <= 0;
      q_rs2cdb_out_en <= 0;
      q_rs2cdb_rob_idx_out <= {`ROB_IDX_SIZE{1'b0}};
      q_rs2cdb_val_out <= 32'b0;
      for (i = 0; i < RS_SIZE; i = i + 1) begin
        busy[i] <= 0;
        rob_idx[i] <= 0;
        op[i] <= 0;
        Vj[i] <= 0;
        Qj[i] <= 0;
        Vk[i] <= 0;
        Qk[i] <= 0;
      end
    end else
    if (!rdy_in) begin

    end else begin
      busy_num <= busy_num_nxt;

      if (de_in_en) begin
        busy[nxt_free_idx] <= 1'b1;
        op[nxt_free_idx] <= de_op_in;
        Vj[nxt_free_idx] <= de_Vj_updated;
        Qj_en[nxt_free_idx] <= de_Qj_en_updated;
        Qj[nxt_free_idx] <= de_Qj_in;
        Vk[nxt_free_idx] <= de_Vk_updated;
        Qk_en[nxt_free_idx] <= de_Qk_en_updated;
        Qk[nxt_free_idx] <= de_Qk_in;
        rob_idx[nxt_free_idx] <= de_rob_idx_in;
      end

      for (i = 0; i < RS_SIZE; i = i + 1) begin
        if (alu_en && busy[i] && Qj_en[i] && (Qj[i] == alu_rob_idx)) begin
          Qj_en[i] <= 0;
          Vj[i] <= alu_result;
        end
        if (alu_en && busy[i] && Qk_en[i] && (Qk[i] == alu_rob_idx)) begin
          Qk_en[i] <= 0;
          Vk[i] <= alu_result;
        end
        if (lsb_in_en && busy[i] && Qj_en[i] && (Qj[i] == lsb_rob_idx_in)) begin
          Qj_en[i] <= 0;
          Vj[i] <= lsb_val_in;
        end
        if (lsb_in_en && busy[i] && Qk_en[i] && (Qk[i] == lsb_rob_idx_in)) begin
          Qk_en[i] <= 0;
          Vk[i] <= lsb_val_in;
        end
      end

      if (work_nxt) begin
        busy[nxt_alu_idx] <= 0;
        Qj_en[nxt_alu_idx] <= 1;
        Qk_en[nxt_alu_idx] <= 1;
        alu_en <= 1;
      end else begin
        alu_en <= 0;
      end

      alu_v1               <= d_alu_v1;
      alu_v2               <= d_alu_v2;
      alu_op               <= d_alu_op;
      alu_rob_idx          <= d_alu_rob_idx;

      q_rs2cdb_out_en      <= alu_en;
      q_rs2cdb_rob_idx_out <= alu_en ? alu_rob_idx : {`ROB_SIZE{1'b0}};
      q_rs2cdb_val_out     <= alu_en ? alu_result : 32'b0;
    end
  end

  assign rs2cdb_out_en      = q_rs2cdb_out_en;
  assign rs2cdb_rob_idx_out = q_rs2cdb_rob_idx_out;
  assign rs2cdb_val_out     = q_rs2cdb_val_out;
endmodule

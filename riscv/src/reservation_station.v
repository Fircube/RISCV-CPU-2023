`include "./riscv/src/param.v"
// alu included
module rs (
    input wire clk,     // system clock signal
    input wire rst_in,  // reset signal
    input wire rdy_in,  // ready signal, pause cpu when low

    input wire roll_back,  // wrong prediction signal

    output wire rs_full,
    output wire                  rs2cdb_out_en,
    output wire [`ROB_IDX_WIDTH] rs2cdb_rob_idx_out,
    output wire [   `DATA_WIDTH] rs2cdb_val_out,

    // decoder
    input wire                    de_in_en,
    input wire [  `ROB_IDX_WIDTH] de_rob_idx_in,
    input wire [`RS_OPCODE_WIDTH] de_op_in,
    input wire [     `DATA_WIDTH] de_Vj_in,
    input wire                    de_Qj_in_en,
    input wire [  `ROB_IDX_WIDTH] de_Qj_in,
    input wire [     `DATA_WIDTH] de_Vk_in,
    input wire                    de_Qk_in_en,
    input wire [  `ROB_IDX_WIDTH] de_Qk_in,


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
  reg [`ROB_IDX_WIDTH] alu_rob_idx;
  reg [     `DATA_WIDTH] alu_result;


  reg                    jump;
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
      `RS_BEQ:  jump = (alu_v1 == alu_v2);
      `RS_BNE:  jump = (alu_v1 != alu_v2);
      `RS_BLT:  jump = ($signed(alu_v1) < $signed(alu_v2));
      `RS_BGE:  jump = ($signed(alu_v1) >= $signed(alu_v2));
      `RS_BLTU: jump = (alu_v1 < alu_v2);
      `RS_BGEU: jump = (alu_v1 >= alu_v2);
    endcase
  end
  // alu end

  reg                  q_rs2cdb_out_en;
  reg [`ROB_IDX_WIDTH] q_rs2cdb_rob_idx_out;
  reg [   `DATA_WIDTH] q_rs2cdb_val_out;

  // inner
  reg [`ROB_IDX_WIDTH]   rob_idx [`RS_WIDTH];
  reg                    busy    [`RS_WIDTH];
  reg [`RS_OPCODE_WIDTH] op      [`RS_WIDTH];
  reg [`DATA_WIDTH]      Vj      [`RS_WIDTH];
  reg [`ROB_IDX_WIDTH]   Qj      [`RS_WIDTH];
  reg [`DATA_WIDTH]      Vk      [`RS_WIDTH];
  reg [`ROB_IDX_WIDTH]   Qk      [`RS_WIDTH];

  reg [`RS_WIDTH]        Qj_en;
  reg [`RS_WIDTH]        Qk_en;
  wire [`RS_WIDTH] ready = ~Qj_en && ~Qk_en;

  reg [`RS_WIDTH] busy_num;
  wire [`RS_WIDTH]    busy_num_nxt=busy_num+(de_in_en?1'b1:1'b0)-((ready!=0)?1'b1:1'b0);
  assign rs_full = (busy_num_nxt >= `RS_SIZE);

  reg full;
  reg [4:0] nxt_free_idx;
  reg [4:0] nxt_alu_idx;
  wire [`DATA_WIDTH] d_alu_v1 = Vj[nxt_alu_idx];
  wire [`DATA_WIDTH] d_alu_v2 = Vk[nxt_alu_idx];
  wire [`RS_OPCODE_WIDTH] d_alu_op = op[nxt_alu_idx];
  wire [`ROB_IDX_WIDTH]   d_alu_rob_idx = rob_idx[nxt_alu_idx];
  integer i;
  always @(*) begin
    nxt_free_idx = 5'b10000;
    nxt_alu_idx = 5'b10000;
    full = 1;
    for (i = 0; i < `RS_SIZE; i = i + 1) begin
      if (!busy[i]) begin
        if(!de_in_en || nxt_free_idx!=5'b10000) full=0;
        nxt_free_idx = i;
      end
      if (busy[i] && ready[i]) begin
        nxt_alu_idx = i;
      end
    end
  end


  always @(posedge clk) begin
    if (rst_in || roll_back) begin
      for (i = 0; i < `RS_SIZE; i = i + 1) begin
        busy[i] <= 0;
      end
      alu_en <= 0;
    end else
    if (!rdy_in) begin

    end else begin
      if (de_in_en) begin
        rob_idx[nxt_free_idx] <= de_rob_idx_in;
        busy[nxt_free_idx] <= 1'b1;
        op[nxt_free_idx] <= de_op_in;
        Vj[nxt_free_idx] <= de_Vj_in;
        Qj_en[nxt_free_idx]<= de_Qj_in_en;
        Qj[nxt_free_idx]<= de_Qj_in;
        Vk[nxt_free_idx]<= de_Vk_in;
        Qk_en[nxt_free_idx]<= de_Qk_in_en;
        Qk[nxt_free_idx]<= de_Qk_in;
      end

      q_rs2cdb_out_en    <= alu_en;
      q_rs2cdb_rob_idx_out <= alu_en ? alu_rob_idx : {`ROB_SIZE{1'b0}};
      q_rs2cdb_val_out     <= alu_en ? alu_result : 32'b0;

      for (i = 0; i < `RS_SIZE; i = i + 1) begin
        if (alu_en && busy[i] && Qj_en[i] && (Qj[i] == alu_rob_idx)) begin
          Qj_en[i] <= 0;
          Vj[i]  <= alu_result;
        end
        if (alu_en && busy[i] && Qk_en[i] && (Qk[i] == alu_rob_idx)) begin
          Qk_en[i] <= 0;
          Vk[i]  <= alu_result;
        end
        if (lsb_in_en && busy[i] && Qj_en[i] && (Qj[i] == lsb_rob_idx_in)) begin
          Qj_en[i] <= 0;
          Vj[i]  <= lsb_val_in;
        end
        if (lsb_in_en && busy[i] && Qk_en[i] && (Qk[i] == alu_rob_idx)) begin
          Qk_en[i] <= 0;
          Vk[i]  <= lsb_val_in;
        end
      end

      alu_en <= (ready!=0);
      alu_v1 <= d_alu_v1;
      alu_v2 <= d_alu_v2;
      alu_op <= d_alu_op;
      alu_rob_idx <= d_alu_rob_idx;
      if (ready!=0) begin
        busy[nxt_alu_idx] <= 0;
        Qj_en[nxt_alu_idx] <= 1;
        Qk_en[nxt_alu_idx] <= 1;
      end
    end
  end
  assign rs2cdb_out_en      = q_rs2cdb_out_en;
  assign rs2cdb_rob_idx_out = q_rs2cdb_rob_idx_out;
  assign rs2cdb_val_out     = q_rs2cdb_val_out;


endmodule

`include "param.v"
// `include "./riscv/src/param.v"

// FIFO structure
module rob (
    input wire clk,     // system clock signal
    input wire rst_in,  // reset signal
    input wire rdy_in,  // ready signal, pause cpu when low

    output wire roll_back,

    output wire rob_full,
    output wire [`ADDR_WIDTH] corr_pc,  // correct pc

    // ifetch
    output wire               if_ready_out,
    output wire [`DATA_WIDTH] if_val_out,

    // Decoder
    input wire                     de_in_en,
    input wire [   `ROB_IDX_WIDTH] de_rob_idx_in,
    input wire                     de_ready_in,
    input wire [`ROB_OPCODE_WIDTH] de_op_in,
    input wire [   `REG_IDX_WIDTH] de_dest_in,
    input wire [      `DATA_WIDTH] de_val_in,
    input wire                     de_jump_in,
    input wire [      `ADDR_WIDTH] de_instr_ain,
    input wire [      `ADDR_WIDTH] de_not_jump_to,

    input  wire [`ROB_IDX_WIDTH] stall_rob_idx_in,
    output wire [`ROB_IDX_WIDTH] rob_idx_nxt,

    // Predictor
    output wire        pre_out_en,
    output wire [31:0] pre_aout,
    output wire        rob_jump,

    // Register File
    output wire                  rf_out_en,
    output wire [`ROB_IDX_WIDTH] rf_rob_idx_out,
    output wire [`REG_IDX_WIDTH] rf_dest_out,
    output wire [   `DATA_WIDTH] rf_val_out,

    input wire [`ROB_IDX_WIDTH] rs1_dep_in,
    input wire [`ROB_IDX_WIDTH] rs2_dep_in,

    output wire rs1_busy_out,
    output wire [`DATA_WIDTH] rs1_val_out,
    output wire rs2_busy_out,
    output wire [`DATA_WIDTH] rs2_val_out,

    // Reservation Station
    input wire                  rs_in_en,
    input wire [`ROB_IDX_WIDTH] rs_rob_idx_in,
    input wire [   `DATA_WIDTH] rs_val_in,

    // LSB
    input wire                  lsb_in_en,
    input wire [`ROB_IDX_WIDTH] lsb_rob_idx_in,
    input wire [   `DATA_WIDTH] lsb_val_in,

    output wire                  rob_committed_en,
    output wire [`ROB_IDX_WIDTH] rob_committed_idx
);

  // Interface-related reg
  reg                     q_roll_back;
  reg [      `ADDR_WIDTH] q_corr_pc;

  reg                     q_pre_out_en;
  reg [      `ADDR_WIDTH] q_pre_aout;
  reg                     q_rob_jump;

  reg                     q_rf_out_en;
  reg [   `ROB_IDX_WIDTH] q_rf_rob_idx_out;
  reg [   `REG_IDX_WIDTH] q_rf_dest_out;
  reg [      `DATA_WIDTH] q_rf_val_out;

  reg                     q_rob_committed_en;
  reg [   `ROB_IDX_WIDTH] q_rob_committed_idx;

  // internal storage
  reg                     busy               [`ROB_WIDTH];
  reg                     ready              [`ROB_WIDTH];
  reg                     jump               [`ROB_WIDTH];
  reg [`ROB_OPCODE_WIDTH] op                 [`ROB_WIDTH];
  reg [   `REG_IDX_WIDTH] dest               [`ROB_WIDTH];
  reg [      `DATA_WIDTH] val                [`ROB_WIDTH];
  reg [      `ADDR_WIDTH] instr_a            [`ROB_WIDTH];
  reg [      `ADDR_WIDTH] not_jump_to        [`ROB_WIDTH];

  // FIFO
  reg [`ROB_IDX_WIDTH] front, rear;
  wire empty = (front == rear);

  // wire commit = !empty && ready[front];
  // wire [`ROB_IDX_WIDTH] nxt_front = front + commit;
  // wire [`ROB_IDX_WIDTH] nxt_rear = rear + de_in_en;
  // wire nxt_empty = (nxt_front == nxt_rear && (empty || commit && !de_in_en));
  // assign rob_full = (nxt_front == nxt_rear && !nxt_empty);
  assign rob_full = (front == rear + 1);

  wire rs_stall_updated = rs_in_en && (rs_rob_idx_in == stall_rob_idx_in);
  wire lsb_stall_updated = lsb_in_en && (lsb_rob_idx_in == stall_rob_idx_in);

  assign if_ready_out = ready[stall_rob_idx_in] || rs_stall_updated || lsb_stall_updated;
  assign if_val_out       = rs_stall_updated ? rs_val_in : lsb_stall_updated ? lsb_val_in : val[stall_rob_idx_in];

  assign rs_rs1_busy_updated = rs_in_en && rs_rob_idx_in == rs1_dep_in;
  assign rs_rs2_busy_updated = rs_in_en && rs_rob_idx_in == rs2_dep_in;
  assign lsb_rs1_busy_updated = lsb_in_en && lsb_rob_idx_in == rs1_dep_in;
  assign lsb_rs2_busy_updated = lsb_in_en && lsb_rob_idx_in == rs2_dep_in;
  assign de_rs1_busy_updated = de_in_en && de_ready_in && de_rob_idx_in == rs1_dep_in;
  assign de_rs2_busy_updated = de_in_en && de_ready_in && de_rob_idx_in == rs2_dep_in;

  assign rs1_busy_out = (!busy[rs1_dep_in] || !ready[rs1_dep_in]) && !rs_rs1_busy_updated && !lsb_rs1_busy_updated && !de_rs1_busy_updated;
  assign rs1_val_out  = rs_rs1_busy_updated ? rs_val_in : lsb_rs1_busy_updated ? lsb_val_in : de_rs1_busy_updated ? de_val_in : val[rs1_dep_in];
  assign rs2_busy_out = (!busy[rs2_dep_in] || !ready[rs2_dep_in]) && !rs_rs2_busy_updated && !lsb_rs2_busy_updated && !de_rs2_busy_updated;
  assign rs2_val_out  = rs_rs2_busy_updated ? rs_val_in : lsb_rs2_busy_updated ? lsb_val_in : de_rs2_busy_updated ? de_val_in : val[rs2_dep_in];

  integer i;
  always @(posedge clk) begin
    if (rst_in) begin
      q_roll_back        <= 1'b0;
      q_corr_pc          <= 32'b0;
      q_pre_out_en       <= 1'b0;
      q_pre_aout         <= 32'b0;
      q_rob_jump         <= 1'b0;
      q_rob_committed_en  <= 1'b0;
      q_rob_committed_idx <= {`ROB_IDX_SIZE{1'b0}};
      q_rf_out_en        <= 1'b0;
      q_rf_rob_idx_out   <= {`ROB_IDX_SIZE{1'b0}};
      q_rf_dest_out      <= 5'b0;
      q_rf_val_out       <= 32'b0;
      front              <= {`ROB_IDX_SIZE{1'b0}};
      rear               <= {`ROB_IDX_SIZE{1'b0}};
      // empty              <= 1'b1;
      for (i = 0; i < `ROB_SIZE; i = i + 1) begin
        busy[i]        <= 1'b0;
        ready[i]       <= 1'b0;
        jump[i]        <= 1'b0;
        op[i]          <= {`ROB_OPCODE_SIZE{1'b0}};
        dest[i]        <= 5'b0;
        val[i]         <= 32'b0;
        instr_a[i]     <= 32'b0;
        not_jump_to[i] <= 32'b0;
      end
    end else if (rdy_in) begin
      // empty <= nxt_empty;
      if (q_roll_back) begin
        q_roll_back        <= 1'b0;
        q_pre_out_en       <= 1'b0;
        q_rob_committed_en  <= 1'b0;
        q_rob_committed_idx <= {`ROB_IDX_SIZE{1'b0}};
        q_rf_out_en        <= 1'b0;
        front              <= {`ROB_IDX_SIZE{1'b0}};
        rear               <= {`ROB_IDX_SIZE{1'b0}};
        for (i = 0; i < `ROB_SIZE; i = i + 1) begin
          busy[i] <= 1'b0;
        end
      end else begin
        if (de_in_en) begin
          busy[de_rob_idx_in]        <= 1'b1;
          ready[de_rob_idx_in]       <= de_ready_in;
          jump[de_rob_idx_in]        <= de_jump_in;
          op[de_rob_idx_in]          <= de_op_in;
          dest[de_rob_idx_in]        <= de_dest_in;
          val[de_rob_idx_in]         <= de_val_in;
          instr_a[de_rob_idx_in]     <= de_instr_ain;
          not_jump_to[de_rob_idx_in] <= de_not_jump_to;
          rear                       <= de_rob_idx_in + 1;
        end

        // rs
        if (rs_in_en) begin
          ready[rs_rob_idx_in] <= 1'b1;
          val[rs_rob_idx_in]   <= rs_val_in;
        end

        // lsb
        if (lsb_in_en) begin
          ready[lsb_rob_idx_in] <= 1'b1;
          val[lsb_rob_idx_in]   <= lsb_val_in;
        end

        if (!empty) begin
          q_pre_out_en       <= (op[front] == `ROB_BR) && ready[front];
          q_rob_committed_en  <= 1'b1;
          q_rob_committed_idx <= front;
          q_rf_out_en        <= (op[front] == `ROB_REG) && ready[front];
          case (op[front])
            `ROB_REG: begin
              if (ready[front]) begin
                front <= front + 1'b1;
                busy[front] <= 1'b0;
                q_rf_rob_idx_out <= front;
                q_rf_dest_out <= dest[front];
                q_rf_val_out <= val[front];
              end
            end
            `ROB_BR: begin  // branch
              if (ready[front]) begin
                front <= front + 1'b1;
                busy[front] <= 1'b0;
                q_pre_aout <= instr_a[front];
                q_rob_jump <= val[front][0];
                if (jump[front] != val[front][0]) begin
                  q_roll_back <= 1'b1;
                  q_corr_pc   <= not_jump_to[front];
                  front       <= {`ROB_IDX_SIZE{1'b0}};
                  rear        <= {`ROB_IDX_SIZE{1'b0}};
                  for (i = 0; i < `ROB_SIZE; i = i + 1) begin
                    busy[i] <= 1'b0;
                  end
                end
              end
            end
            `ROB_MEM: begin
              front <= front + 1'b1;
            end
          endcase
        end else begin
          q_pre_out_en       <= 1'b0;
          q_rob_committed_en  <= 1'b0;
          q_rob_committed_idx <= {`ROB_IDX_SIZE{1'b0}};
          q_rf_out_en        <= 1'b0;
        end
      end
    end
  end

  assign roll_back        = q_roll_back;
  assign corr_pc          = q_corr_pc;

  assign rob_idx_nxt      = de_in_en ? rear + 1 : rear;



  assign pre_out_en       = q_pre_out_en;
  assign pre_aout         = q_pre_aout;
  assign rob_jump         = q_rob_jump;

  assign rf_out_en        = q_rf_out_en;
  assign rf_rob_idx_out   = q_rf_rob_idx_out;
  assign rf_dest_out      = q_rf_dest_out;
  assign rf_val_out       = q_rf_val_out;

  assign rob_committed_en  = q_rob_committed_en;
  assign rob_committed_idx = q_rob_committed_idx;
endmodule

`include "param.v"
// `include "./riscv/src/param.v"

// FIFO structure
module lsb (
    input wire clk,     // system clock signal
    input wire rst_in,  // reset signal
    input wire rdy_in,  // commit signal, pause cpu when low

    input wire roll_back,  // wrong prediction signal

    output wire                  lsb_full,             // load store buffer full signal
    output wire                  lsb2cdb_out_en,
    output wire [`ROB_IDX_WIDTH] lsb2cdb_rob_idx_out,
    output wire [   `DATA_WIDTH] lsb2cdb_val_out,

    // MemCtrl
    input  wire               mem_din_en,
    input  wire [`DATA_WIDTH] mem_din,
    input  wire               mem_w_done,
    output wire               mem_rw,      // write/read signal (1 for write)
    output wire [        1:0] mem_d_type,
    output wire [`ADDR_WIDTH] mem_aout,
    output wire [`DATA_WIDTH] mem_dout,

    // IF
    input wire                     de_in_en,
    input wire                     de_rw_in,
    input wire [`LSB_OPCODE_WIDTH] de_op_in,
    input wire [      `DATA_WIDTH] de_Vj_in,
    input wire                     de_Qj_in_en,
    input wire [   `ROB_IDX_WIDTH] de_Qj_in,
    input wire [      `DATA_WIDTH] de_Vk_in,
    input wire                     de_Qk_in_en,
    input wire [   `ROB_IDX_WIDTH] de_Qk_in,
    input wire [      `DATA_WIDTH] de_offset_in,
    input wire [   `ROB_IDX_WIDTH] de_rob_idx_in,

    // RS
    input wire                  rs_in_en,
    input wire [`ROB_IDX_WIDTH] rs_rob_idx_in,
    input wire [   `DATA_WIDTH] rs_val_in,

    // ROB
    input wire rob_committed_en,
    input wire [`ROB_IDX_WIDTH] rob_committed_idx
);
  localparam IDLE = 0, WAIT_MC = 1;
  reg status;
  reg [`LSB_OPCODE_WIDTH] q_op;


  // internal storage
  reg [`ROB_IDX_WIDTH] rob_idx[`LSB_WIDTH];
  reg busy[`LSB_WIDTH];
  reg ls[`LSB_WIDTH];  // store 1
  reg [`LSB_OPCODE_WIDTH] op[`LSB_WIDTH];
  reg [`ROB_IDX_WIDTH] Qj[`LSB_WIDTH];
  reg [`DATA_WIDTH] Vj[`LSB_WIDTH];
  reg [`ROB_IDX_WIDTH] Qk[`LSB_WIDTH];
  reg [`DATA_WIDTH] Vk[`LSB_WIDTH];
  reg [`DATA_WIDTH] offset[`LSB_WIDTH];
  reg commit[`LSB_WIDTH];

  reg [`LSB_WIDTH] Qj_en;
  reg [`LSB_WIDTH] Qk_en;
  wire [`LSB_WIDTH] ready = ~Qj_en & ~Qk_en;

  // FIFO
  reg [`LSB_IDX_WIDTH] front;
  reg [`LSB_IDX_WIDTH] rear;
  reg [4:0] last;
  wire empty = (front == rear);
  wire head_ready = busy[front] && !ready[front] && (commit[front] || (!ls[front] && !is_io));

  // wire pop = mem_din_en && status == WAIT_MC;
  // wire [`LSB_IDX_WIDTH] nxt_front = front + pop;
  // wire [`LSB_IDX_WIDTH] nxt_rear = rear + de_in_en; 
  // wire nxt_empty = (nxt_front == nxt_rear && (empty || pop && !de_in_en));
  assign lsb_full = (front == rear + 1);

  wire [`ADDR_WIDTH] head_addr = Vj[front] + offset[front];
  wire is_io = (head_addr[17:16] == 2'b11);

  // updated value
  wire mem_j_updated = mem_din_en && (de_Qj_in == lsb2cdb_rob_idx);
  wire mem_k_updated = mem_din_en && (de_Qk_in == lsb2cdb_rob_idx);
  wire rs_j_updated = rs_in_en && (de_Qj_in == rs_rob_idx_in);
  wire rs_k_updated = rs_in_en && (de_Qk_in == rs_rob_idx_in);

  wire Qj_en_updated = de_Qj_in_en && !mem_j_updated && !rs_j_updated;
  wire Qk_en_updated = de_Qk_in_en && !mem_k_updated && !rs_k_updated;
  wire [`DATA_WIDTH] Vj_updated =  de_Qj_in_en ? mem_j_updated ? mem_din : rs_j_updated ? rs_val_in : 32'b0 : de_Vj_in;
  wire [`DATA_WIDTH] Vk_updated =  de_Qk_in_en ? mem_k_updated ? mem_din : rs_k_updated ? rs_val_in : 32'b0 : de_Vk_in;

  // Interface-related reg
  reg q_mem_rw;
  reg [1:0] q_mem_d_type;
  reg [`ADDR_WIDTH] q_mem_aout;
  reg [`DATA_WIDTH] q_mem_dout;

  reg [`ROB_IDX_WIDTH] lsb2cdb_rob_idx;
  reg [`ROB_IDX_WIDTH] lsb2cdb_rob_idx_nxt;

  integer i;
  always @(posedge clk) begin
    if (rst_in) begin
      status <= IDLE;
      lsb2cdb_rob_idx <= 0;
      lsb2cdb_rob_idx_nxt <= 0;
      q_op <= 0;
      q_mem_rw <= 0;
      q_mem_d_type <= 0;
      q_mem_aout <= 0;
      q_mem_dout <= 0;
      front <= 0;
      rear <= 0;
      last <= 5'b10000;
      for (i = 0; i < `LSB_SIZE; i = i + 1) begin
        rob_idx[i] <= 0;
        busy[i]    <= 0;
        ls[i]      <= 0;
        op[i]      <= 0;
        Qj_en[i]   <= 1;
        Qj[i]      <= 0;
        Vj[i]      <= 0;
        Qk_en[i]   <= 1;
        Qk[i]      <= 0;
        Vk[i]      <= 0;
        offset[i]  <= 0;
        commit[i]  <= 0;
      end
    end else if (!rdy_in) begin
      //
    end else if (roll_back) begin
      for (i = 0; i < `LSB_SIZE; i = i + 1) begin
        if (!commit[i]) begin
          busy[i] <= 0;
          if (i == front && !empty) begin
            front <= front + 1;
          end
        end
      end
      if (status == WAIT_MC && (!q_mem_rw || mem_w_done)) begin
        status <= IDLE;
      end
      q_mem_d_type <= 0;
    end else begin
      if (de_in_en) begin
        rob_idx[rear] <= de_rob_idx_in;
        busy[rear]    <= 1;
        ls[rear]      <= de_rw_in;
        op[rear]      <= de_op_in;
        Qj_en[rear]   <= Qj_en_updated;
        Qj[rear]      <= de_Qj_in;
        Vj[rear]      <= Vj_updated;
        Qk_en[rear]   <= Qk_en_updated;
        Qk[rear]      <= de_Qk_in;
        Vk[rear]      <= Vk_updated;
        offset[rear]  <= de_offset_in;
        commit[rear]  <= 0;
        rear          <= rear + 1;
      end


      if (rob_committed_en) begin
        for (i = 0; i < `LSB_SIZE; i = i + 1) begin
          if (busy[i] && rob_idx[i] == rob_committed_idx) begin
            commit[i] <= 1;
          end
        end
      end

      if (mem_din_en) begin
        for (i = 0; i < `LSB_SIZE; i = i + 1) begin
          if (busy[i]) begin
            if (Qj_en[i] && lsb2cdb_rob_idx == Qj[i]) begin
              Qj_en[i] <= 0;
              Vj[i] <= mem_din;
            end
            if (Qk_en[i] && lsb2cdb_rob_idx == Qk[i]) begin
              Qk_en[i] <= 0;
              Vk[i] <= mem_din;
            end
          end
        end
      end

      if (rs_in_en) begin
        for (i = 0; i < `LSB_SIZE; i = i + 1) begin
          if (busy[i]) begin
            if (Qj_en[i] && rs_rob_idx_in == Qj[i]) begin
              Qj_en[i] <= 0;
              Vj[i] <= rs_val_in;
            end
            if (Qk_en[i] && rs_rob_idx_in == Qk[i]) begin
              Qk_en[i] <= 0;
              Vk[i] <= rs_val_in;
            end
          end
        end
      end

      lsb2cdb_rob_idx <= lsb2cdb_rob_idx_nxt;
      if (!empty && head_ready && (status == IDLE || mem_din_en || mem_w_done)) begin
        status <= WAIT_MC;
        lsb2cdb_rob_idx_nxt <= rob_idx[front];
        q_mem_rw <= ls[front];
        case (op[front])
          `LSB_B:  q_mem_d_type <= 2'b01;
          `LSB_H:  q_mem_d_type <= 2'b10;
          `LSB_W:  q_mem_d_type <= 2'b11;
          `LSB_BU: q_mem_d_type <= 2'b01;
          `LSB_HU: q_mem_d_type <= 2'b10;
        endcase
        q_mem_aout <= head_addr;
        q_mem_dout <= Vk[front];
        q_op <= op[front];
        commit[front] <= 1'b0;
        front <= front + 1;
      end else begin
        q_mem_d_type <= 2'b00;
        if (mem_din_en || mem_w_done) begin
          status <= IDLE;
        end
        if (!empty && !busy[front]) begin
          commit[front] <= 1'b0;
          front <= front + 1;
        end
      end
    end
  end

  assign mem_rw = q_mem_rw;
  assign mem_d_type = q_mem_d_type;
  assign mem_aout = q_mem_aout;
  assign mem_dout = q_mem_dout;

  assign lsb2cdb_out_en = mem_din_en;
  assign lsb2cdb_rob_idx_out = lsb2cdb_rob_idx;
  assign lsb2cdb_val_out = (q_op == `LSB_B) ? {{24{mem_din[7]}},  mem_din[7:0]} : (q_op == `LSB_H) ? {{16{mem_din[15]}}, mem_din[15:0]} : mem_din;
endmodule

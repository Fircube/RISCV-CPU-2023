`include "./riscv/src/param.v"
module iFetch (
    input wire clk,     // system clock signal
    input wire rst_in,  // reset signal
    input wire rdy_in,  // ready signal, pause cpu when low

    input wire roll_back,  // wrong prediction signal
    input wire [`ADDR_WIDTH] corr_pc,  // correct pc

    // Memory Controller
    input  wire                mc_instr_in_en,  // enable signal from memory controller
    input  wire [`INSTR_WIDTH] mc_instr_in,     // instruction from memory controller
    output wire                mc_aout_en,      // enable signal to memory controller
    output wire [ `ADDR_WIDTH] mc_aout,         // address to memory controller

    //Decoder
    input wire stall_reset,
    input wire [`ADDR_WIDTH] new_pc,

    output wire                de_out_en,         // enable signal to decoder
    output wire                de_pred_jump_out,  // prediction jump signal to decoder
    output wire [ `ADDR_WIDTH] de_pc_out,         // pc to decoder
    output wire [`INSTR_WIDTH] de_instr_out,      // instruction to decoder


    // Reservation Station
    input wire rs_full,  // reservation station full signal

    // Load Store Buffer
    input wire lsb_full,  // load store buffer full signal

    // Reorder Buffer
    input wire rob_full,     // reorder buffer full signal
    input wire rob_ready_in, // reorder buffer ready signal
    input wire [   `DATA_WIDTH] rob_din // reorder buffer data in
);
  reg [`ADDR_WIDTH] pc;
  reg stall;
  reg stall_jalr;

  reg pred_jump;
  reg [`ADDR_WIDTH] pred_pc;

  reg q_mc_out_en;
  reg [`ADDR_WIDTH] q_mc_aout;

  reg q_de_out_en;
  reg [`INSTR_WIDTH] q_de_instr_out;
  reg [`ADDR_WIDTH] q_de_pc_out;
  reg q_de_pred_jump_out;

  wire lsb_add = (mc_instr_in[`OPCODE_RANGE] == `OPCODE_L) || (mc_instr_in[`OPCODE_RANGE] == `OPCODE_S);
  wire rs_add = (mc_instr_in[`OPCODE_RANGE] == `OPCODE_R) || (mc_instr_in[`OPCODE_RANGE] == `OPCODE_I);
  wire full = rob_full || (lsb_add && lsb_full) || (rs_add && rs_full);

  always @(posedge clk) begin
    if (rst_in || roll_back) begin
      pc <= roll_back ? corr_pc : 32'b0;
      stall <= 1'b0;
      q_mc_out_en <= 1'b0;
      q_mc_aout <= 32'b0;
      q_de_out_en <= 1'b0;
    end else if (!rdy_in) begin
      // nothing
    end else begin
      // if (stall_jalr) begin
      //   if (rob_ready_in) begin
      //     stall_jalr  <= 1'b0;
      //     q_de_out_en <= 1'b1;
      //     pc          <= rob_din + {{21{mc_instr_in[31]}}, mc_instr_in[30:20]};
      //   end else begin
      //     q_de_out_en <= 1'b0;
      //   end
      // end else 
      if (stall && stall_reset) begin
        stall <= 1'b0;
        pc <= new_pc;
      end else if (mc_instr_in_en && !full && !stall) begin
        q_de_out_en <= 1;
        q_de_pred_jump_out <= pred_jump;
        q_de_pc_out <= pc;
        q_de_instr_out <= mc_instr_in;
        case (mc_instr_in[`OPCODE_RANGE])
          `OPCODE_B:    stall <= 1'b1;  // branch
          `OPCODE_JAL:  stall <= 1'b1;  // JAL
          `OPCODE_JALR: stall <= 1'b1;  // JALR
          default: pc <= pc + 4;  // Others
        endcase
      end else begin
        q_de_out_en <= 0;
      end
    end
  end

  assign mc_out_en = q_mc_out_en;
  assign mc_aout   = q_mc_aout;
  assign de_out_en = q_de_out_en;
endmodule

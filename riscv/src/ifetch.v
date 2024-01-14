`include "param.v"
// `include "./riscv/src/param.v"

module iFetch (
    input wire clk,     // system clock signal
    input wire rst_in,  // reset signal
    input wire rdy_in,  // ready signal, pause cpu when low

    input wire roll_back,  // wrong prediction signal

    // Memory Controller
    input  wire                mc_instr_in_en,  // enable signal from memory controller
    input  wire [`INSTR_WIDTH] mc_instr_in,     // instruction from memory controller
    output wire [ `ADDR_WIDTH] mc_aout,         // address to memory controller

    // Decoder
    input wire stall_reset,
    input wire [`ADDR_WIDTH] new_pc,

    output wire                de_out_en,    // enable signal to decoder
    output wire [ `ADDR_WIDTH] de_pc_out,    // pc to decoder
    output wire [`INSTR_WIDTH] de_instr_out, // instruction to decoder

    // Reservation Station
    input wire rs_full,  // reservation station full signal

    // Load Store Buffer
    input wire lsb_full,  // load store buffer full signal

    // Reorder Buffer
    input wire rob_full,  // reorder buffer full signal
    input wire rob_ready_in,  // reorder buffer ready signal
    input wire [`DATA_WIDTH] rob_val_in,  // reorder buffer data in
    input wire [`ADDR_WIDTH] corr_pc  // correct pc
);
  reg [`ADDR_WIDTH] pc;
  reg stall;

  reg q_de_out_en;
  reg [`INSTR_WIDTH] q_de_instr_out;
  reg [`ADDR_WIDTH] q_de_pc_out;

  wire lsb_add = (mc_instr_in[`OPCODE_RANGE] == `OPCODE_L) || (mc_instr_in[`OPCODE_RANGE] == `OPCODE_S);
  wire rs_add = (mc_instr_in[`OPCODE_RANGE] == `OPCODE_R) || (mc_instr_in[`OPCODE_RANGE] == `OPCODE_I);
  wire full = rob_full || (lsb_add && lsb_full) || (rs_add && rs_full);

  always @(posedge clk) begin
    if (rst_in || roll_back) begin
      pc <= roll_back ? corr_pc : 32'b0;
      stall <= 1'b0;
      q_de_out_en <= 1'b0;
      q_de_instr_out <= 32'b0;
      q_de_pc_out <= 32'b0;
    end else if (!rdy_in) begin
      // nothing
    end else begin
      if (stall) begin
        if (stall_reset) begin
          stall <= 1'b0;
          pc <= new_pc;
          // q_de_out_en <= 1'b1;
          // q_de_pc_out <= new_pc;
          // q_de_instr_out <= mc_instr_in;
          // case (mc_instr_in[`OPCODE_RANGE])
          //   `OPCODE_B: begin
          //     stall <= 1'b1;  // branch
          //     pc <= new_pc;
          //   end
          //   `OPCODE_JAL: begin
          //     stall <= 1'b1;  // JAL
          //     pc <= new_pc;
          //   end
          //   `OPCODE_JALR: begin
          //     stall <= 1'b1;  // JALR
          //     pc <= new_pc;
          //   end
          //   default: begin
          //     stall <= 1'b0;
          //     pc <= new_pc + 4;  // Others
          //   end
          // endcase
        end else if (rob_ready_in) begin
          // To speed up, decode with rob data directly
          stall <= 1'b0;
          q_de_out_en <= 1'b1;
          pc <= (rob_val_in + {{21{pc[31]}}, pc[30:20]}) & 32'b11111111111111111111111111111110;
        end else begin
          stall <= 1'b1;
          q_de_out_en <= 1'b0;
        end
      end else if (!full && mc_instr_in_en) begin
        q_de_out_en <= 1'b1;
        q_de_pc_out <= pc;
        q_de_instr_out <= mc_instr_in;
        case (mc_instr_in[`OPCODE_RANGE])
          `OPCODE_B: stall <= 1'b1;  // branch
          `OPCODE_JAL: stall <= 1'b1;  // JAL
          `OPCODE_JALR: stall <= 1'b1;  // JALR
          default: pc <= pc + 4;  // Others
        endcase
      end else begin
        q_de_out_en <= 1'b0;
      end
    end
  end

  assign mc_aout = stall_reset ? new_pc : pc;
  assign de_out_en = q_de_out_en;
  assign de_pc_out = q_de_pc_out;
  assign de_instr_out = q_de_instr_out;
endmodule

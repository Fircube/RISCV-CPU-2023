`include "param.v"
// `include "./riscv/src/param.v"

module issue (
    input wire clk,  // system clock signal
    input wire rst_in,  // reset signal
    input wire rdy_in,  // ready signal, pause cpu when low

    input wire roll_back,  // wrong prediction signal
    input wire [`ADDR_WIDTH] corr_pc,  // correct pc

    // Memory Controller
    input  wire                mc_instr_in_en,  // enable signal from memory controller
    input  wire [`INSTR_WIDTH] mc_instr_in,     // instruction from memory controller
    output wire [ `ADDR_WIDTH] mc_aout,         // address to memory controller

    // Reservation Station
    input wire rs_full,  // reservation station full signal

    // Load Store Buffer
    input wire lsb_full,  // load store buffer full signal

    // Reorder Buffer
    input wire rob_full,  // reorder buffer full signal
    input wire rob_ready_in,  // reorder buffer ready signal
    input wire [`DATA_WIDTH] rob_val_in,  // reorder buffer data in

    // --------------------------
    // Predictor
    input wire jump,  // prediction jump signal from predictor

    // Register File
    input wire                  rs1_busy,
    input wire [`ROB_IDX_WIDTH] rs1_dep_in,
    input wire [   `DATA_WIDTH] rs1_val_in,
    input wire                  rs2_busy,
    input wire [`ROB_IDX_WIDTH] rs2_dep_in,
    input wire [   `DATA_WIDTH] rs2_val_in,

    output wire                  rf_out_en,
    output wire [`REG_IDX_WIDTH] rf_dest_out,
    output wire [`ROB_IDX_WIDTH] rf_rob_idx_out,

    // Reservation Station
    input wire                  rs_in_en,
    input wire [`ROB_IDX_WIDTH] rs_rob_idx_in,
    input wire [   `DATA_WIDTH] rs_val_in,

    output wire                    rs_out_en,
    output wire [`RS_OPCODE_WIDTH] rs_op_out,
    output wire [     `DATA_WIDTH] rs_Vj_out,
    output wire                    rs_Qj_out_en,
    output wire [  `ROB_IDX_WIDTH] rs_Qj_out,
    output wire [     `DATA_WIDTH] rs_Vk_out,
    output wire                    rs_Qk_out_en,
    output wire [  `ROB_IDX_WIDTH] rs_Qk_out,
    output wire [  `ROB_IDX_WIDTH] rs_rob_idx_out,

    // Load Store Buffer
    input wire                  lsb_in_en,
    input wire [`ROB_IDX_WIDTH] lsb_rob_idx_in,
    input wire [   `DATA_WIDTH] lsb_val_in,

    output wire                     lsb_out_en,
    output wire                     lsb_rw_out,
    output wire [`LSB_OPCODE_WIDTH] lsb_op_out,
    output wire [      `DATA_WIDTH] lsb_Vj_out,
    output wire                     lsb_Qj_out_en,
    output wire [   `ROB_IDX_WIDTH] lsb_Qj_out,
    output wire [      `DATA_WIDTH] lsb_Vk_out,
    output wire                     lsb_Qk_out_en,
    output wire [   `ROB_IDX_WIDTH] lsb_Qk_out,
    output wire [      `DATA_WIDTH] lsb_offset_out,
    output wire [   `ROB_IDX_WIDTH] lsb_rob_idx_out,

    // Reorder Buffer
    input  wire [`ROB_IDX_WIDTH] rob_idx_nxt,
    output wire [`ROB_IDX_WIDTH] stall_rob_idx_out,

    output wire                     rob_out_en,
    output wire [   `ROB_IDX_WIDTH] rob_idx_out,
    output wire                     rob_ready_out,
    output wire [`ROB_OPCODE_WIDTH] rob_op_out,
    output wire [   `REG_IDX_WIDTH] rob_dest_out,
    output wire [      `DATA_WIDTH] rob_val_out,
    output wire                     rob_jump_out,
    output wire [      `ADDR_WIDTH] rob_instr_aout,
    output wire [      `ADDR_WIDTH] rob_not_jump_to
);

  reg [      `ADDR_WIDTH] pc;
  reg                     q_ifde_en;
  reg [     `INSTR_WIDTH] q_ifde_instr;
  reg [      `ADDR_WIDTH] q_ifde_addr;
  reg                     stall;
  reg                     stall_temp;

  // RF
  reg                     q_rf_out_en;

  // RS
  reg                     q_rs_out_en;
  reg [ `RS_OPCODE_WIDTH] q_rs_op_out;
  reg [      `DATA_WIDTH] q_rs_Vj_out;
  reg                     q_rs_Qj_out_en;
  reg [   `ROB_IDX_WIDTH] q_rs_Qj_out;
  reg [      `DATA_WIDTH] q_rs_Vk_out;
  reg                     q_rs_Qk_out_en;
  reg [   `ROB_IDX_WIDTH] q_rs_Qk_out;
  reg [   `ROB_IDX_WIDTH] q_rs_rob_idx_out;

  // LSB
  reg                     q_lsb_out_en;
  reg                     q_lsb_rw_out;
  reg [`LSB_OPCODE_WIDTH] q_lsb_op_out;
  reg [      `DATA_WIDTH] q_lsb_Vj_out;
  reg                     q_lsb_Qj_out_en;
  reg [   `ROB_IDX_WIDTH] q_lsb_Qj_out;
  reg [      `DATA_WIDTH] q_lsb_Vk_out;
  reg                     q_lsb_Qk_out_en;
  reg [   `ROB_IDX_WIDTH] q_lsb_Qk_out;
  reg [      `DATA_WIDTH] q_lsb_offset_out;
  reg [   `ROB_IDX_WIDTH] q_lsb_rob_idx_out;

  // ROB
  reg [   `ROB_IDX_WIDTH] q_stall_rob_idx_out;

  reg                     q_rob_out_en;
  reg [   `ROB_IDX_WIDTH] q_rob_idx_out;
  reg                     q_rob_ready_out;
  reg [`ROB_OPCODE_WIDTH] q_rob_op_out;
  reg [   `REG_IDX_WIDTH] q_rob_dest_out;
  reg [      `DATA_WIDTH] q_rob_val_out;
  reg                     q_rob_jump_out;
  reg [      `ADDR_WIDTH] q_rob_instr_aout;
  reg [      `ADDR_WIDTH] q_rob_not_jump_to;

  wire [`OPCODE_WIDTH] opcode = q_ifde_instr[`OPCODE_RANGE];
  wire [`FUNCT3_WIDTH] func3 = q_ifde_instr[`FUNCT3_RANGE];
  wire [`FUNCT7_WIDTH] func7 = q_ifde_instr[`FUNCT7_RANGE];
  wire [`REG_WIDTH] rd = q_ifde_instr[`RD_RANGE];

  wire rs_update_rs1 = rs_in_en && (rs1_dep_in == rs_rob_idx_in);
  wire rs_update_rs2 = rs_in_en && (rs2_dep_in == rs_rob_idx_in);
  wire lsb_update_rs1 = lsb_in_en && (rs1_dep_in == lsb_rob_idx_in);
  wire lsb_update_rs2 = lsb_in_en && (rs2_dep_in == lsb_rob_idx_in);

  wire rs1_busy_now = rs1_busy && !rs_update_rs1 && !lsb_update_rs1;
  wire rs2_busy_now = rs2_busy && !rs_update_rs2 && !lsb_update_rs2;
  wire [`DATA_WIDTH] rs1_val = rs1_busy_now?0:(rs1_busy?(rs_update_rs1?rs_val_in:lsb_val_in):rs1_val_in);
  wire [`DATA_WIDTH] rs2_val = rs2_busy_now?0:(rs2_busy?(rs_update_rs2?rs_val_in:lsb_val_in):rs2_val_in);

  wire lsb_add = (mc_instr_in[`OPCODE_RANGE] == `OPCODE_L) || (mc_instr_in[`OPCODE_RANGE] == `OPCODE_S);
  wire rs_add = (mc_instr_in[`OPCODE_RANGE] == `OPCODE_R) || (mc_instr_in[`OPCODE_RANGE] == `OPCODE_I);
  wire full = rob_full || (lsb_add && lsb_full) || (rs_add && rs_full);

  always @(posedge clk) begin
    q_rob_idx_out <= rob_idx_nxt;
    if (rst_in || roll_back) begin
      pc                  <= roll_back ? corr_pc : 32'b0;
      q_ifde_instr        <= 32'b0;
      q_ifde_addr         <= 32'b0;
      q_ifde_en           <= 1'b0;
      stall               <= 1'b0;
      stall_temp          <= 1'b0;

      q_stall_rob_idx_out <= {`ROB_IDX_SIZE{1'b0}};
      q_rf_out_en         <= 1'b0;

      q_rs_out_en         <= 1'b0;
      q_rs_op_out         <= {`RS_OPCODE_SIZE{1'b0}};
      q_rs_Vj_out         <= 32'b0;
      q_rs_Qj_out_en      <= 1'b0;
      q_rs_Qj_out         <= {`ROB_IDX_SIZE{1'b0}};
      q_rs_Vk_out         <= 32'b0;
      q_rs_Qk_out_en      <= 1'b0;
      q_rs_Qk_out         <= {`ROB_IDX_SIZE{1'b0}};
      q_rs_rob_idx_out    <= {`ROB_IDX_SIZE{1'b0}};

      q_lsb_out_en        <= 1'b0;
      q_lsb_rw_out        <= 1'b0;
      q_lsb_op_out        <= {`LSB_OPCODE_SIZE{1'b0}};
      q_lsb_Vj_out        <= 32'b0;
      q_lsb_Qj_out_en     <= 1'b0;
      q_lsb_Qj_out        <= {`ROB_IDX_SIZE{1'b0}};
      q_lsb_Vk_out        <= 32'b0;
      q_lsb_Qk_out_en     <= 1'b0;
      q_lsb_Qk_out        <= {`ROB_IDX_SIZE{1'b0}};
      q_lsb_offset_out    <= 32'b0;
      q_lsb_rob_idx_out   <= {`ROB_IDX_SIZE{1'b0}};

      q_rob_out_en        <= 1'b0;
      q_rob_idx_out       <= {`ROB_IDX_SIZE{1'b0}};
      q_rob_ready_out     <= 1'b0;
      q_rob_op_out        <= {`ROB_OPCODE_SIZE{1'b0}};
      q_rob_dest_out      <= 5'b0;
      q_rob_val_out       <= 32'b0;
      q_rob_jump_out      <= 1'b0;
      q_rob_instr_aout    <= 32'b0;
      q_rob_not_jump_to   <= 32'b0;
    end else if (rdy_in) begin
      if (stall) begin
        if (rob_ready_in) begin
          stall     <= 1'b0;
          q_ifde_en <= 1'b1;
          pc        <= rob_val_in + {q_ifde_instr[31:12], 12'b0};
        end else begin
          stall     <= 1'b1;
          q_ifde_en <= 1'b0;
        end
      end else begin
        // Fetch
        if (~full && mc_instr_in_en && ~stall_temp) begin
          q_ifde_instr <= mc_instr_in;
          q_ifde_addr  <= pc;
          q_ifde_en    <= 1'b1;
          case (mc_instr_in[6:0])
            7'b1100011: stall_temp <= 1'b1; // branch
            7'b1101111: stall_temp <= 1'b1; // JAL
            7'b1100111: stall_temp <= 1'b1; // JALR
            default:    pc <= pc + 4; // Other instructions
          endcase

        end else begin
          q_ifde_en <= 1'b0;
        end
      end

      // Decode and issue
      if (q_ifde_en) begin
        q_rs_rob_idx_out <= rob_idx_nxt;
        q_rob_instr_aout <= q_ifde_addr;
        case (opcode)
          `OPCODE_R: begin
            q_rob_out_en <= 1'b1;
            q_rob_ready_out <= 1'b0;
            q_rob_op_out <= `ROB_REG;
            q_rob_dest_out <= rd;

            q_rf_out_en <= (rd != 5'b00000);
            q_rs_out_en <= 1'b1;
            q_lsb_out_en <= 1'b0;

            q_rs_Vj_out <= rs1_val;
            q_rs_Qj_out_en <= rs1_busy_now;
            q_rs_Qj_out <= rs1_dep_in;
            q_rs_Vk_out <= rs2_val;
            q_rs_Qk_out_en <= rs2_busy_now;
            q_rs_Qk_out <= rs2_dep_in;

            // q_stall_reset <= 1'b0;

            case (func3)
              `FUNCT3_ADD: begin  // ADD && SUB
                case (func7)
                  `FUNCT7_ADD: q_rs_op_out <= `RS_ADD;
                  `FUNCT7_SUB: q_rs_op_out <= `RS_SUB;
                endcase
              end
              `FUNCT3_SLL:  q_rs_op_out <= `RS_SLL;
              `FUNCT3_SLT:  q_rs_op_out <= `RS_SLT;
              `FUNCT3_SLTU: q_rs_op_out <= `RS_SLTU;
              `FUNCT3_XOR:  q_rs_op_out <= `RS_XOR;
              `FUNCT3_SRL: begin  // SRL && SRA
                case (func7)
                  `FUNCT7_SRL: q_rs_op_out <= `RS_SRL;
                  `FUNCT7_SRA: q_rs_op_out <= `RS_SRA;
                endcase
              end
              `FUNCT3_OR:   q_rs_op_out <= `RS_OR;
              `FUNCT3_AND:  q_rs_op_out <= `RS_AND;
            endcase
          end
          `OPCODE_I: begin
            q_rob_out_en    <= 1'b1;
            q_rob_ready_out <= 1'b0;
            q_rob_op_out    <= `ROB_REG;
            q_rob_dest_out  <= rd;

            q_rf_out_en     <= (rd != 5'b00000);
            q_rs_out_en     <= 1'b1;
            q_lsb_out_en    <= 1'b0;

            q_rs_Vj_out     <= rs1_val;
            q_rs_Qj_out_en  <= rs1_busy_now;
            q_rs_Qj_out     <= rs1_dep_in;
            q_rs_Qk_out_en  <= 1'b0;

            // q_stall_reset   <= 1'b0;

            case (func3)
              `FUNCT3_ADDI: begin
                q_rs_op_out <= `RS_ADD;
                q_rs_Vk_out <= {{21{q_ifde_instr[31]}}, q_ifde_instr[30:20]};
              end
              `FUNCT3_SLTI: begin
                q_rs_op_out <= `RS_SLT;
                q_rs_Vk_out <= {{21{q_ifde_instr[31]}}, q_ifde_instr[30:20]};
              end
              `FUNCT3_SLTIU: begin
                q_rs_op_out <= `RS_SLTU;
                q_rs_Vk_out <= {20'b0, q_ifde_instr[31:20]};
              end
              `FUNCT3_XORI: begin
                q_rs_op_out <= `RS_XOR;
                q_rs_Vk_out <= {{21{q_ifde_instr[31]}}, q_ifde_instr[30:20]};
              end
              `FUNCT3_ORI: begin
                q_rs_op_out <= `RS_OR;
                q_rs_Vk_out <= {{21{q_ifde_instr[31]}}, q_ifde_instr[30:20]};
              end
              `FUNCT3_ANDI: begin
                q_rs_op_out <= `RS_AND;
                q_rs_Vk_out <= {{21{q_ifde_instr[31]}}, q_ifde_instr[30:20]};
              end
              `FUNCT3_SLLI: begin
                q_rs_op_out <= `RS_SLL;
                q_rs_Vk_out <= {27'b0, q_ifde_instr[24:20]};
              end
              `FUNCT3_SRLI: begin  // SRLI && SRAI
                case (func7)
                  `FUNCT7_SRLI: begin
                    q_rs_op_out <= `RS_SRL;
                    q_rs_Vk_out <= {27'b0, q_ifde_instr[24:20]};
                  end
                  `FUNCT7_SRAI: begin
                    q_rs_op_out <= `RS_SRA;
                    q_rs_Vk_out <= {27'b0, q_ifde_instr[24:20]};
                  end
                endcase
              end
            endcase
          end
          `OPCODE_L: begin
            q_rob_out_en <= 1'b1;
            q_rob_ready_out <= 1'b0;
            q_rob_op_out <= `ROB_REG;
            q_rob_dest_out <= rd;
            // q_rob_val_out <= {q_ifde_instr[31:12], 12'b0};

            q_rf_out_en <= 1'b1;
            q_rs_out_en <= 1'b0;
            q_lsb_out_en <= 1'b1;

            q_lsb_rw_out <= 1'b0;
            q_lsb_Vj_out <= rs1_val;
            q_lsb_Qj_out_en <= rs1_busy_now;
            q_lsb_Qj_out <= rs1_dep_in;
            q_lsb_Qk_out_en <= 1'b0;
            q_lsb_offset_out <= {{21{q_ifde_instr[31]}}, q_ifde_instr[30:20]};
            q_lsb_rob_idx_out <= rob_idx_nxt;

            // q_stall_reset <= 1'b0;

            case (func3)
              `FUNCT3_LB:  q_lsb_op_out <= `LSB_B;
              `FUNCT3_LH:  q_lsb_op_out <= `LSB_H;
              `FUNCT3_LW:  q_lsb_op_out <= `LSB_W;
              `FUNCT3_LBU: q_lsb_op_out <= `LSB_BU;
              `FUNCT3_LHU: q_lsb_op_out <= `LSB_HU;
            endcase
          end
          `OPCODE_S: begin
            q_rob_out_en <= 1'b1;
            q_rob_ready_out <= 1'b0;
            q_rob_op_out <= `ROB_MEM;

            q_rf_out_en <= 1'b0;
            q_rs_out_en <= 1'b0;
            q_lsb_out_en <= 1'b1;

            q_lsb_rw_out <= 1'b1;
            q_lsb_Vj_out <= rs1_val;
            q_lsb_Qj_out_en <= rs1_busy_now;
            q_lsb_Qj_out <= rs1_dep_in;
            q_lsb_Vk_out <= rs2_val;
            q_lsb_Qk_out_en <= rs2_busy_now;
            q_lsb_Qk_out <= rs2_dep_in;
            q_lsb_offset_out <= {{21{q_ifde_instr[31]}}, q_ifde_instr[30:25], q_ifde_instr[11:7]};
            q_lsb_rob_idx_out <= rob_idx_nxt;

            // q_stall_reset <= 1'b0;

            case (func3)
              `FUNCT3_SB: q_lsb_op_out <= `LSB_B;
              `FUNCT3_SH: q_lsb_op_out <= `LSB_H;
              `FUNCT3_SW: q_lsb_op_out <= `LSB_W;
            endcase
          end
          `OPCODE_B: begin
            q_rob_out_en <= 1'b1;
            q_rob_ready_out <= 1'b0;
            q_rob_op_out <= `ROB_BR;
            q_rob_jump_out <= jump;
            q_rob_not_jump_to <= jump ?  pc + 4 : pc + {{20{q_ifde_instr[31]}}, q_ifde_instr[7], q_ifde_instr[30:25], q_ifde_instr[11:8], 1'b0};

            q_rf_out_en <= 1'b0;
            q_rs_out_en <= 1'b1;
            q_lsb_out_en <= 1'b0;

            q_rs_Vj_out <= rs1_val;
            q_rs_Qj_out_en <= rs1_busy_now;
            q_rs_Qj_out <= rs1_dep_in;
            q_rs_Vk_out <= rs2_val;
            q_rs_Qk_out_en <= rs2_busy_now;
            q_rs_Qk_out <= rs2_dep_in;

            stall_temp <= 1'b0;
            pc               <= jump ? pc + {{20{q_ifde_instr[31]}}, q_ifde_instr[7], q_ifde_instr[30:25], q_ifde_instr[11:8], 1'b0} : pc + 4;
            // q_stall_reset <= 1'b1;
            // q_new_pc  <= jump ? if_pc_in + {{20{q_ifde_instr[31]}}, q_ifde_instr[7], q_ifde_instr[30:25],q_ifde_instr[11:8], 1'b0} : if_pc_in+4;

            case (func3)
              `FUNCT3_BEQ:  q_rs_op_out <= `RS_BEQ;
              `FUNCT3_BNE:  q_rs_op_out <= `RS_BNE;
              `FUNCT3_BLT:  q_rs_op_out <= `RS_BLT;
              `FUNCT3_BGE:  q_rs_op_out <= `RS_BGE;
              `FUNCT3_BLTU: q_rs_op_out <= `RS_BLTU;
              `FUNCT3_BGEU: q_rs_op_out <= `RS_BGEU;
            endcase
          end
          `OPCODE_LUI: begin
            q_rob_out_en <= (rd != 5'b00000);
            q_rob_ready_out <= 1'b1;
            q_rob_op_out <= `ROB_REG;
            q_rob_dest_out <= rd;
            q_rob_val_out <= {q_ifde_instr[31:12], 12'b0};

            q_rf_out_en <= (rd != 5'b00000);
            q_rs_out_en <= 1'b0;
            q_lsb_out_en <= 1'b0;

            // q_stall_reset <= 1'b0;
          end
          `OPCODE_AUIPC: begin
            q_rob_out_en <= (rd != 5'b00000);
            q_rob_ready_out <= 1'b1;
            q_rob_op_out <= `ROB_REG;
            q_rob_dest_out <= rd;
            q_rob_val_out <= q_ifde_addr + {q_ifde_instr[31:12], 12'b0};

            q_rf_out_en <= (rd != 5'b00000);
            q_rs_out_en <= 1'b0;
            q_lsb_out_en <= 1'b0;

            // q_stall_reset <= 1'b0;
          end
          `OPCODE_JAL: begin
            q_rob_out_en <= (rd != 5'b00000);
            q_rob_ready_out <= 1'b1;
            q_rob_op_out <= `ROB_REG;
            q_rob_dest_out <= rd;
            q_rob_val_out <= q_ifde_addr + 4;

            q_rf_out_en <= (rd != 5'b00000);
            q_rs_out_en <= 1'b0;
            q_lsb_out_en <= 1'b0;

            stall_temp <= 1'b0;
            pc <= pc + {{12{q_ifde_instr[31]}}, q_ifde_instr[19:12], q_ifde_instr[20], q_ifde_instr[30:21], 1'b0};

            // q_stall_reset <= 1'b1;
            // q_new_pc  <= if_pc_in +  {{12{q_ifde_instr[31]}}, q_ifde_instr[19:12], q_ifde_instr[20], q_ifde_instr[30:21], 1'b0};
          end
          `OPCODE_JALR: begin
            q_rob_out_en    <= (rd != 5'b00000);
            q_rob_ready_out <= 1'b1;
            q_rob_op_out    <= `ROB_REG;
            q_rob_dest_out  <= rd;
            q_rob_val_out   <= q_ifde_addr + 4;

            q_rf_out_en     <= (rd != 5'b00000);
            q_rs_out_en     <= 1'b0;
            q_lsb_out_en    <= 1'b0;

            stall_temp      <= 1'b0;
            if (rs1_busy_now) begin
              // q_stall_reset <= 1'b0;
              stall               <= 1'b1;
              q_stall_rob_idx_out <= rs1_dep_in;
            end else begin
              pc <= (rs1_val + {{21{q_ifde_instr[31]}}, q_ifde_instr[30:20]})& 32'b11111111111111111111111111111110;
              // q_stall_reset <= 1'b1;
              // q_new_pc <= (rs1_val + {{21{q_ifde_instr[31]}}, q_ifde_instr[30:20]}) & 32'b11111111111111111111111111111110;
            end
          end
        endcase
      end else begin
        // q_stall_reset <= 1'b0;
        q_rob_out_en <= 1'b0;
        q_rf_out_en  <= 1'b0;
        q_rs_out_en  <= 1'b0;
        q_lsb_out_en <= 1'b0;
      end
    end
  end

  assign mc_aout = pc;

  // RF
  assign rf_out_en         = q_rf_out_en;
  assign rf_dest_out       = q_rob_dest_out;
  assign rf_rob_idx_out    = q_rob_idx_out;

  // RS
  assign rs_out_en         = q_rs_out_en;
  assign rs_op_out         = q_rs_op_out;
  assign rs_Vj_out         = q_rs_Vj_out;
  assign rs_Qj_out_en      = q_rs_Qj_out_en;
  assign rs_Qj_out         = q_rs_Qj_out;
  assign rs_Vk_out         = q_rs_Vk_out;
  assign rs_Qk_out_en      = q_rs_Qk_out_en;
  assign rs_Qk_out         = q_rs_Qk_out;
  assign rs_rob_idx_out    = q_rs_rob_idx_out;

  // LSB
  assign lsb_out_en        = q_lsb_out_en;
  assign lsb_rw_out        = q_lsb_rw_out;
  assign lsb_op_out        = q_lsb_op_out;
  assign lsb_Vj_out        = q_lsb_Vj_out;
  assign lsb_Qj_out_en     = q_lsb_Qj_out_en;
  assign lsb_Qj_out        = q_lsb_Qj_out;
  assign lsb_Vk_out        = q_lsb_Vk_out;
  assign lsb_Qk_out_en     = q_lsb_Qk_out_en;
  assign lsb_Qk_out        = q_lsb_Qk_out;
  assign lsb_offset_out    = q_lsb_offset_out;
  assign lsb_rob_idx_out   = q_lsb_rob_idx_out;

  // ROB
  assign stall_rob_idx_out = q_stall_rob_idx_out;

  assign rob_out_en        = q_rob_out_en;
  assign rob_idx_out       = q_rob_idx_out;
  assign rob_ready_out     = q_rob_ready_out;
  assign rob_op_out        = q_rob_op_out;
  assign rob_dest_out      = q_rob_dest_out;
  assign rob_val_out       = q_rob_val_out;
  assign rob_jump_out      = q_rob_jump_out;
  assign rob_instr_aout    = q_rob_instr_aout;
  assign rob_not_jump_to   = q_rob_not_jump_to;
endmodule

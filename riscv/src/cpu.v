// RISCV32I CPU top module
// port modification allowed for debugging purposes

`include "param.v"
// `include "./riscv/src/mem_ctrl.v"
// `include "./riscv/src/ifetch.v"
// `include "./riscv/src/decoder.v"
// `include "./riscv/src/predictor.v"
// `include "./riscv/src/register_file.v"
// `include "./riscv/src/reservation_station.v"
// `include "./riscv/src/load_store_buffer.v"
// `include "./riscv/src/reorder_buffer.v"

module cpu (
    input wire clk_in,  // system clock signal
    input wire rst_in,  // reset signal
    input wire rdy_in,  // ready signal, pause cpu when low

    input  wire [ 7:0] mem_din,   // data input bus
    output wire [ 7:0] mem_dout,  // data output bus
    output wire [31:0] mem_a,     // address bus (only 17:0 is used)
    output wire        mem_wr,    // write/read signal (1 for write)

    input wire io_buffer_full,  // 1 if uart buffer is full

    output wire [31:0] dbgreg_dout  // cpu register output (debugging demo)
);

  // implementation goes here

  // Specifications:
  // - Pause cpu(freeze pc, registers, etc.) when rdy_in is low
  // - Memory read result will be returned in the next cycle. Write takes 1 cycle(no need to wait)
  // - Memory is of size 128KB, with valid address ranging from 0x0 to 0x20000
  // - I/O port is mapped to address higher than 0x30000 (mem_a[17:16]==2'b11)
  // - 0x30000 read: read a byte from input
  // - 0x30000 write: write a byte to output (write 0x00 is ignored)
  // - 0x30004 read: read clocks passed since cpu starts (in dword, 4 bytes)
  // - 0x30004 write: indicates program stop (will output '\0' through uart tx)


  // rob wrong prediction signal
  wire                                    roll_back;
  wire               [      `ADDR_WIDTH]  corr_pc;

  // CDB

  // rs
  wire                                    rs_full;
  wire                                    rs2cdb_en;
  wire               [   `ROB_IDX_WIDTH]  rs2cdb_rob_idx;
  wire               [      `DATA_WIDTH]  rs2cdb_val;

  wire               [   `ROB_IDX_WIDTH]  rs1_dep;
  wire               [   `ROB_IDX_WIDTH]  rs2_dep;

  // lsb
  wire                                    lsb_full;
  wire                                    lsb2cdb_en;
  wire               [   `ROB_IDX_WIDTH]  lsb2cdb_rob_idx;
  wire               [      `DATA_WIDTH]  lsb2cdb_val;

  // rob
  wire                                    rob_full;

  // mc & if
  wire                                    mc2if_instr_en;
  wire               [     `INSTR_WIDTH]  mc2if_instr;

  wire               [      `ADDR_WIDTH]  if2mc_a;

  // mc & lsb
  wire                                    mc2lsb_d_en;
  wire               [      `DATA_WIDTH]  mc2lsb_d;
  wire                                    mc2lsb_w_done;

  wire                                    lsb2mc_rw;
  wire               [              1:0 ] lsb2mc_d_type;
  wire               [      `ADDR_WIDTH]  lsb2mc_a;
  wire               [      `DATA_WIDTH]  lsb2mc_d;

  // if & de
  wire                                    if2de_en;
  wire                                    if2de_pred_jump;
  wire               [      `ADDR_WIDTH]  if2de_pc;
  wire               [     `INSTR_WIDTH]  if2de_instr;

  wire                                    de2if_stall_reset;
  wire               [      `ADDR_WIDTH]  de2if_new_pc;

  // if & rob
  wire                                    rob2if_ready;
  wire               [      `DATA_WIDTH]  rob2if_val;

  // decoder & predictor
  wire                                    jump;

  // decoder & rf
  wire                                    de2rf_en;
  wire               [   `ROB_IDX_WIDTH]  de2rf_rob_idx;
  wire               [   `REG_IDX_WIDTH]  de2rf_dest;

  wire                                    rf2de_rs1_busy;
  wire               [      `DATA_WIDTH]  rf2de_rs1_val;
  wire                                    rf2de_rs2_busy;
  wire               [      `DATA_WIDTH]  rf2de_rs2_val;

  // decoder & rs
  wire                                    de2rs_en;
  wire               [   `ROB_IDX_WIDTH]  de2rs_rob_idx;
  wire               [ `RS_OPCODE_WIDTH]  de2rs_op;
  wire               [      `DATA_WIDTH]  de2rs_Vj;
  wire                                    de2rs_Qj_en;
  wire               [   `ROB_IDX_WIDTH]  de2rs_Qj;
  wire               [      `DATA_WIDTH]  de2rs_Vk;
  wire                                    de2rs_Qk_en;
  wire               [   `ROB_IDX_WIDTH]  de2rs_Qk;

  // decoder & lsb
  wire                                    de2lsb_en;
  wire                                    de2lsb_rw;
  wire               [   `ROB_IDX_WIDTH]  de2lsb_rob_idx;
  wire               [`LSB_OPCODE_WIDTH]  de2lsb_op;
  wire               [      `DATA_WIDTH]  de2lsb_Vj;
  wire                                    de2lsb_Qj_en;
  wire               [   `ROB_IDX_WIDTH]  de2lsb_Qj;
  wire               [      `DATA_WIDTH]  de2lsb_Vk;
  wire                                    de2lsb_Qk_en;
  wire               [   `ROB_IDX_WIDTH]  de2lsb_Qk;
  wire               [      `DATA_WIDTH]  de2lsb_offset;

  // decoder & rob
  wire                                    de2rob_en;
  wire               [   `ROB_IDX_WIDTH]  de2rob_rob_idx;
  wire                                    de2rob_ready;
  wire               [`ROB_OPCODE_WIDTH]  de2rob_op;
  wire               [   `REG_IDX_WIDTH]  de2rob_dest;
  wire               [      `DATA_WIDTH]  de2rob_val;
  wire                                    de2rob_jump;
  wire               [      `ADDR_WIDTH]  de2rob_instr_a;
  wire               [      `ADDR_WIDTH]  de2rob_not_jump_to;

  wire               [   `ROB_IDX_WIDTH]  stall_rob_idx;
  wire               [   `ROB_IDX_WIDTH]  rob_idx_nxt;

  // predictor & rob
  wire                                    rob2pre_en;
  wire               [      `ADDR_WIDTH]  rob2pre_a;
  wire                                    rob2pre_jump;

  // lsb & rob
  wire                                    rob2lsb_committed_en;
  wire               [   `ROB_IDX_WIDTH]  rob2lsb_committed_idx;

  // rf & rob
  wire                                    rob2rf_en;
  wire               [   `ROB_IDX_WIDTH]  rob2rf_idx;
  wire               [   `REG_IDX_WIDTH]  rob2rf_dest;
  wire               [      `DATA_WIDTH]  rob2rf_val;
  wire                                    rob2rf_rs1_busy;
  wire               [      `DATA_WIDTH]  rob2rf_rs1_val;
  wire                                    rob2rf_rs2_busy;
  wire               [      `DATA_WIDTH]  rob2rf_rs2_val;


  wire [`REG_IDX_WIDTH] rs1 = mc2if_instr[`RS1_RANGE];
  wire [`REG_IDX_WIDTH] rs2 = mc2if_instr[`RS2_RANGE];

  wire empty = 1'b0;

  memCtrl MemCtrl (
      .clk(clk_in),
      .rst_in(rst_in),
      .rdy_in(rdy_in),
      .roll_back(roll_back),
      .io_buffer_full(empty),

      // For RAM
      .mem_din (mem_din),
      .mem_rw  (mem_wr),
      .mem_dout(mem_dout),
      .mem_aout(mem_a),

      // For iFetch
      .if_ain(if2mc_a),
      .if_instr_out_en(mc2if_instr_en),
      .if_instr_out(mc2if_instr),

      // for LSB
      .lsb_rw(lsb2mc_rw),
      .lsb_d_type(lsb2mc_d_type),
      .lsb_ain(lsb2mc_a),
      .lsb_din(lsb2mc_d),
      
      .lsb_dout_en(mc2lsb_d_en),
      .lsb_dout(mc2lsb_d),
      .lsb_w_done(mc2lsb_w_done)
  );

  issue Issue (
      .rst_in(rst_in),
      .clk   (clk_in),
      .rdy_in(rdy_in),

      .roll_back(roll_back),
      .corr_pc  (corr_pc),

      // For Cache
      .mc_instr_in_en(mc2if_instr_en),
      .mc_instr_in   (mc2if_instr),
      .mc_aout       (if2mc_a),

      // For Reservation Station
      .rs_full      (rs_full),
      .rs_in_en     (rs2cdb_en),
      .rs_rob_idx_in(rs2cdb_rob_idx),
      .rs_val_in    (rs2cdb_val),

      .rs_out_en     (de2rs_en),
      .rs_op_out     (de2rs_op),
      .rs_rob_idx_out(de2rs_rob_idx),
      .rs_Vj_out     (de2rs_Vj),
      .rs_Qj_out_en  (de2rs_Qj_en),
      .rs_Qj_out     (de2rs_Qj),
      .rs_Vk_out     (de2rs_Vk),
      .rs_Qk_out_en  (de2rs_Qk_en),
      .rs_Qk_out     (de2rs_Qk),

      // For Reorder Buffer
      .rob_full    (rob_full),
      .rob_idx_nxt (rob_idx_nxt),
      .rob_ready_in(rob2if_ready),
      .rob_val_in  (rob2if_val),

      .stall_rob_idx_out(stall_rob_idx),

      .rob_out_en     (de2rob_en),
      .rob_idx_out    (de2rob_rob_idx),
      .rob_op_out     (de2rob_op),
      .rob_ready_out  (de2rob_ready),
      .rob_val_out    (de2rob_val),
      .rob_jump_out   (de2rob_jump),
      .rob_dest_out   (de2rob_dest),
      .rob_not_jump_to(de2rob_not_jump_to),
      .rob_instr_aout (de2rob_instr_a),

      // For Load & Store Buffer
      .lsb_full      (lsb_full),
      .lsb_in_en     (lsb2cdb_en),
      .lsb_rob_idx_in(lsb2cdb_rob_idx),
      .lsb_val_in    (lsb2cdb_val),

      .lsb_out_en     (de2lsb_en),
      .lsb_rw_out     (de2lsb_rw),
      .lsb_rob_idx_out(de2lsb_rob_idx),
      .lsb_Qj_out_en  (de2lsb_Qj_en),
      .lsb_Vj_out     (de2lsb_Vj),
      .lsb_Qj_out     (de2lsb_Qj),
      .lsb_offset_out (de2lsb_offset),
      .lsb_Qk_out_en  (de2lsb_Qk_en),
      .lsb_Vk_out     (de2lsb_Vk),
      .lsb_Qk_out     (de2lsb_Qk),
      .lsb_op_out     (de2lsb_op),

      // For Register File
      .rs1_busy  (rf2de_rs1_busy),
      .rs1_dep_in(rs1_dep),
      .rs1_val_in(rf2de_rs1_val),
      .rs2_busy  (rf2de_rs2_busy),
      .rs2_dep_in(rs2_dep),
      .rs2_val_in(rf2de_rs2_val),

      .rf_out_en     (de2rf_en),
      .rf_dest_out   (de2rf_dest),
      .rf_rob_idx_out(de2rf_rob_idx),

      // For Predictor
      .jump(jump)
  );

  // iFetch Ifetch (
  //     .clk(clk_in),
  //     .rst_in(rst_in),
  //     .rdy_in(rdy_in),

  //     .roll_back(roll_back),

  //     .mc_instr_in_en(mc2if_instr_en),
  //     .mc_instr_in(mc2if_instr),
  //     .mc_aout(if2mc_a),

  //     .stall_reset(de2if_stall_reset),
  //     .new_pc(de2if_new_pc),

  //     .de_out_en(if2de_en),
  //     .de_pc_out(if2de_pc),
  //     .de_instr_out(if2de_instr),

  //     .rs_full(rs_full),
  //     .lsb_full(lsb_full),
  //     .rob_full(rob_full),
  //     .rob_ready_in(rob2if_ready),
  //     .rob_val_in(rob2if_val),
  //     .corr_pc(corr_pc)
  // );

  // decoder Decoder (
  //     .clk(clk_in),
  //     .rst_in(rst_in),
  //     .rdy_in(rdy_in),
  //     .roll_back(roll_back),

  //     .if_in_en(if2de_en),
  //     .if_pc_in(if2de_pc),
  //     .if_instr_in(if2de_instr),

  //     .stall_reset(de2if_stall_reset),
  //     .new_pc(de2if_new_pc),

  //     .jump(jump),

  //     .rs1_busy(rf2de_rs1_busy),
  //     .rs1_dep_in(rs1_dep),
  //     .rs1_val_in(rf2de_rs1_val),
  //     .rs2_busy(rf2de_rs2_busy),
  //     .rs2_dep_in(rs2_dep),
  //     .rs2_val_in(rf2de_rs2_val),

  //     .rf_out_en(de2rf_en),
  //     .rf_dest_out(de2rf_dest),
  //     .rf_rob_idx_out(de2rf_rob_idx),

  //     .rs_in_en(rs2cdb_en),
  //     .rs_rob_idx_in(rs2cdb_rob_idx),
  //     .rs_val_in(rs2cdb_val),

  //     .rs_out_en(de2rs_en),
  //     .rs_op_out(de2rs_op),
  //     .rs_Vj_out(de2rs_Vj),
  //     .rs_Qj_out_en(de2rs_Qj_en),
  //     .rs_Qj_out(de2rs_Qj),
  //     .rs_Vk_out(de2rs_Vk),
  //     .rs_Qk_out_en(de2rs_Qk_en),
  //     .rs_Qk_out(de2rs_Qk),
  //     .rs_rob_idx_out(de2rs_rob_idx),

  //     .lsb_in_en(lsb2cdb_en),
  //     .lsb_rob_idx_in(lsb2cdb_rob_idx),
  //     .lsb_val_in(lsb2cdb_val),

  //     .lsb_out_en(de2lsb_en),
  //     .lsb_rw_out(de2lsb_rw),
  //     .lsb_op_out(de2lsb_op),
  //     .lsb_Vj_out(de2lsb_Vj),
  //     .lsb_Qj_out_en(de2lsb_Qj_en),
  //     .lsb_Qj_out(de2lsb_Qj),
  //     .lsb_Vk_out(de2lsb_Vk),
  //     .lsb_Qk_out_en(de2lsb_Qk_en),
  //     .lsb_Qk_out(de2lsb_Qk),
  //     .lsb_offset_out(de2lsb_offset),
  //     .lsb_rob_idx_out(de2lsb_rob_idx),

  //     .rob_idx_nxt(rob_idx_nxt),
  //     .stall_rob_idx_out(stall_rob_idx),

  //     .rob_out_en(de2rob_en),
  //     .rob_idx_out(de2rob_rob_idx),
  //     .rob_ready_out(de2rob_ready),
  //     .rob_op_out(de2rob_op),
  //     .rob_dest_out(de2rob_dest),
  //     .rob_val_out(de2rob_val),
  //     .rob_jump_out(de2rob_jump),
  //     .rob_instr_aout(de2rob_instr_a),
  //     .rob_not_jump_to(de2rob_not_jump_to)
  // );

  predictor Predictor (
      .clk(clk_in),
      .rst_in(rst_in),
      .rdy_in(rdy_in),

      .mem_ain(if2mc_a),

      // For RoB
      .rob_in_en(rob2pre_en),
      .rob_ain(rob2pre_a),
      .rob_jump(rob2pre_jump),

      .jump(jump)
  );

  regFile RegFile (
      .clk(clk_in),
      .rst_in(rst_in),
      .rdy_in(rdy_in),

      .roll_back(roll_back),

      // CDB
      .rs1(rs1),
      .rs2(rs2),
      .rs1_dep_out(rs1_dep),
      .rs2_dep_out(rs2_dep),

      // For decoder
      .de_in_en(de2rf_en),
      .de_dest_in(de2rf_dest),
      .de_rob_idx_in(de2rf_rob_idx),

      // For Reservation Station
      .de_rs1_busy_out(rf2de_rs1_busy),
      .de_rs1_val_out (rf2de_rs1_val),
      .de_rs2_busy_out(rf2de_rs2_busy),
      .de_rs2_val_out (rf2de_rs2_val),

      // For RoB
      .rob_in_en  (rob2rf_en),
      .rob_idx_in (rob2rf_idx),
      .rob_dest_in(rob2rf_dest),
      .rob_val_in (rob2rf_val),

      .rob_rs1_busy_in(rob2rf_rs1_busy),
      .rob_rs1_val_in (rob2rf_rs1_val),
      .rob_rs2_busy_in(rob2rf_rs2_busy),
      .rob_rs2_val_in (rob2rf_rs2_val)
  );

  rs RS (
      .clk(clk_in),
      .rst_in(rst_in),
      .rdy_in(rdy_in),

      .roll_back(roll_back),

      // CDB
      .rs_full(rs_full),
      .rs2cdb_out_en(rs2cdb_en),
      .rs2cdb_rob_idx_out(rs2cdb_rob_idx),
      .rs2cdb_val_out(rs2cdb_val),

      // For Decoder
      .de_in_en(de2rs_en),
      .de_op_in(de2rs_op),
      .de_Vj_in(de2rs_Vj),
      .de_Qj_in_en(de2rs_Qj_en),
      .de_Qj_in(de2rs_Qj),
      .de_Vk_in(de2rs_Vk),
      .de_Qk_in_en(de2rs_Qk_en),
      .de_Qk_in(de2rs_Qk),
      .de_rob_idx_in(de2rs_rob_idx),

      // For LSB
      .lsb_in_en(lsb2cdb_en),
      .lsb_rob_idx_in(lsb2cdb_rob_idx),
      .lsb_val_in(lsb2cdb_val)
  );

  lsb LSB (
      .clk(clk_in),
      .rst_in(rst_in),
      .rdy_in(rdy_in),

      .roll_back(roll_back),

      // CDB
      .lsb_full(lsb_full),
      .lsb2cdb_out_en(lsb2cdb_en),
      .lsb2cdb_rob_idx_out(lsb2cdb_rob_idx),
      .lsb2cdb_val_out(lsb2cdb_val),

      // For MC
      .mem_din_en(mc2lsb_d_en),
      .mem_din(mc2lsb_d),
      .mem_w_done(mc2lsb_w_done),
      .mem_rw(lsb2mc_rw),
      .mem_d_type(lsb2mc_d_type),
      .mem_aout(lsb2mc_a),
      .mem_dout(lsb2mc_d),

      // For Decoder
      .de_in_en(de2lsb_en),
      .de_rw_in(de2lsb_rw),
      .de_op_in(de2lsb_op),
      .de_Vj_in(de2lsb_Vj),
      .de_Qj_in_en(de2lsb_Qj_en),
      .de_Qj_in(de2lsb_Qj),
      .de_Vk_in(de2lsb_Vk),
      .de_Qk_in_en(de2lsb_Qk_en),
      .de_Qk_in(de2lsb_Qk),
      .de_offset_in(de2lsb_offset),
      .de_rob_idx_in(de2lsb_rob_idx),

      // For RS
      .rs_in_en(rs2cdb_en),
      .rs_rob_idx_in(rs2cdb_rob_idx),
      .rs_val_in(rs2cdb_val),

      // For RoB
      .rob_committed_en (rob2lsb_committed_en),
      .rob_committed_idx(rob2lsb_committed_idx)
  );

  rob ROB (
      .clk(clk_in),
      .rst_in(rst_in),
      .rdy_in(rdy_in),

      .roll_back(roll_back),

      .rob_full(rob_full),
      .corr_pc (corr_pc),

      // For iFetch
      .if_ready_out(rob2if_ready),
      .if_val_out  (rob2if_val),

      // For Decoder
      .de_in_en(de2rob_en),
      .de_rob_idx_in(de2rob_rob_idx),
      .de_ready_in(de2rob_ready),
      .de_op_in(de2rob_op),
      .de_dest_in(de2rob_dest),
      .de_val_in(de2rob_val),
      .de_jump_in(de2rob_jump),
      .de_instr_ain(de2rob_instr_a),
      .de_not_jump_to(de2rob_not_jump_to),

      .stall_rob_idx_in(stall_rob_idx),
      .rob_idx_nxt(rob_idx_nxt),

      // For Predictor
      .pre_out_en(rob2pre_en),
      .pre_aout  (rob2pre_a),
      .rob_jump  (rob2pre_jump),

      // For Register File
      .rf_out_en(rob2rf_en),
      .rf_rob_idx_out(rob2rf_idx),
      .rf_dest_out(rob2rf_dest),
      .rf_val_out(rob2rf_val),

      // For Reservation Station
      .rs1_dep_in(rs1_dep),
      .rs2_dep_in(rs2_dep),

      .rs1_busy_out(rob2rf_rs1_busy),
      .rs1_val_out (rob2rf_rs1_val),
      .rs2_busy_out(rob2rf_rs2_busy),
      .rs2_val_out (rob2rf_rs2_val),

      .rs_in_en(rs2cdb_en),
      .rs_rob_idx_in(rs2cdb_rob_idx),
      .rs_val_in(rs2cdb_val),

      // For LSB
      .lsb_in_en(lsb2cdb_en),
      .lsb_rob_idx_in(lsb2cdb_rob_idx),
      .lsb_val_in(lsb2cdb_val),

      .rob_committed_en (rob2lsb_committed_en),
      .rob_committed_idx(rob2lsb_committed_idx)
  );
endmodule

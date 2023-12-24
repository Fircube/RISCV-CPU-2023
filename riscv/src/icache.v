`include "./riscv/src/param.v"

module iCache (
    input wire clk,    // system clock signal
    input wire rst_in, // reset signal

    // RAM
    input wire                     mem_in_en,
    input wire [      `ADDR_WIDTH] mem_ain,
    input wire [`ICACHE_BLK_WIDTH] mem_din,

    // IF
    input  wire [ `ADDR_WIDTH] if_ain,       // address from IF
    output wire                miss,
    output wire                if_out_en,
    output wire [`INSTR_WIDTH] if_instr_out
);

  // inner
  reg cacheValid[`ICACHE_SIZE-1:0];
  reg [`ICACHE_TAG_WIDTH] cacheTag[`ICACHE_SIZE-1:0];
  reg [`ICACHE_BLK_WIDTH] cacheData[`ICACHE_SIZE-1:0];

  // utensils
  wire [`ICACHE_OFFSET_WIDTH] pc_offset = if_ain[`ICACHE_OFFSET_RANGE];
  wire [`ICACHE_IDX_WIDTH] pc_idx = if_ain[`ICACHE_IDX_RANGE];
  wire [`ICACHE_TAG_WIDTH] pc_tag = if_ain[`ICACHE_TAG_RANGE];
  wire hit = cacheValid[pc_idx] && (cacheTag[pc_idx] == pc_tag);

  wire [`ICACHE_IDX_WIDTH] mem_pc_idx = mem_ain[`ICACHE_IDX_RANGE];
  wire [`ICACHE_TAG_WIDTH] mem_pc_tag = mem_ain[`ICACHE_TAG_RANGE];

  wire [`ICACHE_BLK_WIDTH] cur_block = cacheData[pc_idx];
  wire [`INSTR_WIDTH] cur_instrs[`ICACHE_BLK_INSTR-1:0];
  wire [`INSTR_WIDTH] cur_instr = cur_block[pc_offset];

  genvar _i;
  generate
    for (_i = 0; _i < `ICACHE_BLK_INSTR; _i = _i + 1) begin
      assign cur_instrs[_i] = cur_block[_i*32+31:_i*32];
    end
  endgenerate

  assign miss = ~hit;
  assign if_out_en = hit;
  assign if_instr_out = cur_instr;

  integer i;

  always @(posedge clk) begin
    if (rst_in) begin
      for (i = 0; i < `ICACHE_SIZE; i = i + 1) begin
        cacheValid[i] <= 0;
        cacheTag[i]   <= 0;
        cacheData[i]  <= 0;
      end
    end else if (mem_in_en) begin
      cacheValid[mem_pc_idx] <= 1'b1;
      cacheTag[mem_pc_idx]   <= mem_pc_tag;
      cacheData[mem_pc_idx]  <= mem_din;
    end
  end

endmodule

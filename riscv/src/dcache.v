`include "param.v"
// `include "./riscv/src/param.v"

// 8行cache
// 可能出现跨行访问
module dCache #(
    parameter DCACHE_SIZE = 8,
    parameter DCACHE_BLK_DATA = 16
) (
    input wire clk,       // system clock signal
    input wire rst_in,    // reset signal
    input wire rdy_in,    // ready signal, pause cpu when low
    input wire roll_back, // wrong prediction signal

    input wire               lsb_rw,
    input wire [        1:0] lsb_d_type,
    input wire [`ADDR_WIDTH] lsb_ain,
    input wire [`DATA_WIDTH] lsb_din,

    // RAM
    input wire mem_in_en,
    input wire [31:4] mem_ain,
    input wire [`CACHE_BLK_WIDTH] mem_din,

    input wire mem_w_done,

    // IO
    input wire IO_din_en,
    input wire [`DATA_WIDTH] IO_din,
    input wire IO_w_done,

    output wire miss,
    output wire [31:4] miss_a,
    output wire mem_rw,
    output wire [`CACHE_BLK_WIDTH] write_back_en,

    // LSB
    output wire lsb_dout_en,
    output wire [`DATA_WIDTH] lsb_dout,
    output wire lsb_w_done
);

  // internal storage
  reg cacheValid[DCACHE_SIZE-1:0];
  reg cacheDirty[DCACHE_SIZE-1:0];
  reg [`DCACHE_TAG_WIDTH] cacheTag[DCACHE_SIZE-1:0];
  reg [`CACHE_BLK_WIDTH] cacheData[DCACHE_SIZE-1:0];

  // conserve LOAD/STORE status
  reg q_lsb_rw;
  reg [1:0] q_lsb_d_type;
  reg [`ADDR_WIDTH] q_lsb_ain;
  reg [`DATA_WIDTH] q_lsb_din;

  wire lsb_rw_conv = (lsb_d_type != 2'b00) ? lsb_rw : q_lsb_rw;
  wire [1:0] lsb_d_type_conv = (lsb_d_type != 2'b00) ? lsb_d_type : q_lsb_d_type;
  wire [`ADDR_WIDTH] lsb_ain_conv = (lsb_d_type != 2'b00) ? lsb_ain : q_lsb_ain;
  wire [`DATA_WIDTH] lsb_din_conv = (lsb_d_type != 2'b00) ? lsb_din : q_lsb_din;

  wire [`DCACHE_TAG_RANGE] data_tag = lsb_ain_conv[`DCACHE_TAG_RANGE];
  wire [`DCACHE_IDX_WIDTH] data_idx = lsb_ain_conv[`DCACHE_IDX_RANGE];
  wire [`DCACHE_OFFSET_WIDTH] data_offset = lsb_ain_conv[`DCACHE_OFFSET_RANGE];
  wire hit = cacheValid[data_idx] && (cacheTag[data_idx] == data_tag);

  wire [`DCACHE_IDX_WIDTH] mem_idx = mem_ain[`DCACHE_IDX_RANGE];

  wire [`CACHE_BLK_WIDTH] cur_block = cacheData[data_idx];
  wire [`DATA_WIDTH] cur_datas[DCACHE_BLK_DATA-1:0];
  // 写回完成或读取当前行则dirty置0
  wire cur_dirty = cacheDirty[data_idx] && (!mem_w_done || mem_idx != data_idx);

  genvar _i;
  generate
    for (_i = 0; _i < DCACHE_BLK_DATA; _i = _i + 1) begin
      assign cur_datas[_i] = cur_block[_i*8+7:_i*8];
    end
  endgenerate

  // 处理跨行
  wire if_nxt  = (lsb_d_type_conv == 2'b11) ? (data_offset > 12) : (lsb_d_type_conv == 2'b10) ? (data_offset > 14) : 1'b0;
  wire lastDataInBlk = (data_idx == 7);
  wire [`DCACHE_TAG_RANGE] data_tag_nxt = lsb_ain_conv[`DCACHE_TAG_RANGE] + lastDataInBlk;
  wire [`DCACHE_IDX_WIDTH] data_idx_nxt = lsb_ain_conv[`DCACHE_IDX_RANGE] + 1;
  wire hit_nxt = cacheValid[data_idx_nxt] && (cacheTag[data_idx_nxt] == data_tag_nxt);
  wire [`CACHE_BLK_WIDTH] nxt_block = cacheData[data_idx_nxt];
  wire nxt_dirty = cacheDirty[data_idx_nxt] && (!mem_w_done || mem_idx != data_idx_nxt);

  wire is_io = (lsb_d_type_conv == 2'b00) ? 1'b0 : (lsb_ain_conv[17:16] == 2'b11);

  wire load = !hit || (if_nxt && !hit_nxt);
  wire write_back = !is_io && (lsb_d_type_conv != 2'b00) && (cur_dirty || (if_nxt && nxt_dirty)) && (!hit || (if_nxt && !hit_nxt));
  wire [31:4] load_a = hit ? {data_tag_nxt, data_idx_nxt} : {data_tag, data_idx};
  wire [31:4] write_back_a = cur_dirty ? {cacheTag[data_idx], data_idx} : {cacheTag[data_idx_nxt], data_idx_nxt};
  wire ready       = (!mem_in_en && hit) && (lsb_d_type_conv != 2'b00) && (!if_nxt || hit_nxt);
  reg dCache_d_en;
  reg [`DATA_WIDTH] dCache_d;
  reg dCache_w_done;
  wire d_dCache_d_en = ready && !lsb_rw_conv;
  wire d_dCache_w_done = ready && lsb_rw_conv;
  
  assign lsb_dout     = is_io ? IO_din : dCache_d;
  assign lsb_dout_en  = IO_din_en | dCache_d_en;
  assign lsb_w_done   = IO_w_done | dCache_w_done;

  assign miss         = (write_back | load) & ~is_io & (lsb_d_type_conv != 2'b00);
  assign miss_a       = write_back ? write_back_a : load_a;
  assign mem_rw       = ~write_back;
  // opt?
  assign write_back_en = cur_dirty ? cur_block : nxt_block;

  integer i;
  always @(posedge clk) begin
    if (rst_in) begin
      dCache_d_en   <= 0;
      dCache_w_done <= 0;
      q_lsb_rw      <= 1'b1;
      q_lsb_d_type  <= 2'b00;
      q_lsb_ain     <= 32'b0;
      q_lsb_din     <= 32'b0;
      dCache_d      <= 32'b0;
      for (i = 0; i < 8; i = i + 1) begin
        cacheValid[i] <= 0;
        cacheDirty[i] <= 0;
        cacheTag[i]   <= 0;
        cacheData[i]  <= 0;
      end
    end else if (rdy_in) begin
      if (mem_in_en && !cacheDirty[mem_idx]) begin
        cacheValid[mem_idx] <= 1;
        cacheTag[mem_idx]   <= mem_ain[31:3+4];
        cacheData[mem_idx]  <= mem_din;
      end
      if (mem_w_done) begin
        cacheDirty[mem_idx] <= 0;
      end
      if (roll_back && lsb_rw_conv == 0) begin
        // abort memory read operation when there is a wrong branch prediction
        dCache_d_en   <= 0;
        dCache_w_done <= 0;
        q_lsb_d_type  <= 2'b00;
      end else begin
        if (lsb_d_type != 2'b00) begin
          q_lsb_ain    <= lsb_ain;
          q_lsb_d_type <= lsb_d_type;
          q_lsb_din    <= lsb_din;
          q_lsb_rw     <= lsb_rw;
        end
        dCache_d_en   <= d_dCache_d_en;
        dCache_w_done <= d_dCache_w_done;
        if (ready) begin
          q_lsb_d_type <= 2'b00;
          case (lsb_d_type_conv)
            2'b01: begin  // byte
              if (lsb_rw_conv) begin
                // write
                cacheDirty[data_idx] <= 1;
                case (data_offset)
                  4'b0000: cacheData[data_idx][7:0] <= lsb_din_conv[7:0];
                  4'b0001: cacheData[data_idx][15:8] <= lsb_din_conv[7:0];
                  4'b0010: cacheData[data_idx][23:16] <= lsb_din_conv[7:0];
                  4'b0011: cacheData[data_idx][31:24] <= lsb_din_conv[7:0];
                  4'b0100: cacheData[data_idx][39:32] <= lsb_din_conv[7:0];
                  4'b0101: cacheData[data_idx][47:40] <= lsb_din_conv[7:0];
                  4'b0110: cacheData[data_idx][55:48] <= lsb_din_conv[7:0];
                  4'b0111: cacheData[data_idx][63:56] <= lsb_din_conv[7:0];
                  4'b1000: cacheData[data_idx][71:64] <= lsb_din_conv[7:0];
                  4'b1001: cacheData[data_idx][79:72] <= lsb_din_conv[7:0];
                  4'b1010: cacheData[data_idx][87:80] <= lsb_din_conv[7:0];
                  4'b1011: cacheData[data_idx][95:88] <= lsb_din_conv[7:0];
                  4'b1100: cacheData[data_idx][103:96] <= lsb_din_conv[7:0];
                  4'b1101: cacheData[data_idx][111:104] <= lsb_din_conv[7:0];
                  4'b1110: cacheData[data_idx][119:112] <= lsb_din_conv[7:0];
                  4'b1111: cacheData[data_idx][127:120] <= lsb_din_conv[7:0];
                endcase
              end else begin
                // read
                dCache_d <= {24'b0, cur_datas[data_offset]};
              end
            end
            2'b10: begin  // half word
              if (lsb_rw_conv) begin
                // write
                cacheDirty[data_idx] <= 1;
                case (data_offset)
                  4'b0000: cacheData[data_idx][15:0] <= lsb_din_conv[15:0];
                  4'b0001: cacheData[data_idx][23:8] <= lsb_din_conv[15:0];
                  4'b0010: cacheData[data_idx][31:16] <= lsb_din_conv[15:0];
                  4'b0011: cacheData[data_idx][39:24] <= lsb_din_conv[15:0];
                  4'b0100: cacheData[data_idx][47:32] <= lsb_din_conv[15:0];
                  4'b0101: cacheData[data_idx][55:40] <= lsb_din_conv[15:0];
                  4'b0110: cacheData[data_idx][63:48] <= lsb_din_conv[15:0];
                  4'b0111: cacheData[data_idx][71:56] <= lsb_din_conv[15:0];
                  4'b1000: cacheData[data_idx][79:64] <= lsb_din_conv[15:0];
                  4'b1001: cacheData[data_idx][87:72] <= lsb_din_conv[15:0];
                  4'b1010: cacheData[data_idx][95:80] <= lsb_din_conv[15:0];
                  4'b1011: cacheData[data_idx][103:88] <= lsb_din_conv[15:0];
                  4'b1100: cacheData[data_idx][111:96] <= lsb_din_conv[15:0];
                  4'b1101: cacheData[data_idx][119:104] <= lsb_din_conv[15:0];
                  4'b1110: cacheData[data_idx][127:112] <= lsb_din_conv[15:0];
                  4'b1111: begin
                    cacheData[data_idx][127:120] <= lsb_din_conv[7:0];
                    cacheDirty[data_idx_nxt]     <= 1;
                    cacheData[data_idx_nxt][7:0] <= lsb_din_conv[15:8];
                  end
                endcase
              end else begin
                // read
                if (data_offset == 4'b1111) begin
                  dCache_d <= {16'b0, nxt_block[7:0], cur_datas[4'b1111]};
                end else begin
                  dCache_d <= {16'b0, cur_datas[data_offset+1'b1], cur_datas[data_offset]};
                end
              end
            end

            2'b11: begin  // word
              if (lsb_rw_conv) begin
                // write
                cacheDirty[data_idx] <= 1;
                case (data_offset)
                  4'b0000: cacheData[data_idx][31:0] <= lsb_din_conv[31:0];
                  4'b0001: cacheData[data_idx][39:8] <= lsb_din_conv[31:0];
                  4'b0010: cacheData[data_idx][47:16] <= lsb_din_conv[31:0];
                  4'b0011: cacheData[data_idx][55:24] <= lsb_din_conv[31:0];
                  4'b0100: cacheData[data_idx][63:32] <= lsb_din_conv[31:0];
                  4'b0101: cacheData[data_idx][71:40] <= lsb_din_conv[31:0];
                  4'b0110: cacheData[data_idx][79:48] <= lsb_din_conv[31:0];
                  4'b0111: cacheData[data_idx][87:56] <= lsb_din_conv[31:0];
                  4'b1000: cacheData[data_idx][95:64] <= lsb_din_conv[31:0];
                  4'b1001: cacheData[data_idx][103:72] <= lsb_din_conv[31:0];
                  4'b1010: cacheData[data_idx][111:80] <= lsb_din_conv[31:0];
                  4'b1011: cacheData[data_idx][119:88] <= lsb_din_conv[31:0];
                  4'b1100: cacheData[data_idx][127:96] <= lsb_din_conv[31:0];
                  4'b1101: begin
                    cacheData[data_idx][127:104] <= lsb_din_conv[23:0];
                    cacheDirty[data_idx_nxt]     <= 1;
                    cacheData[data_idx_nxt][7:0] <= lsb_din_conv[31:24];
                  end
                  4'b1110: begin
                    cacheData[data_idx][127:112]  <= lsb_din_conv[15:0];
                    cacheDirty[data_idx_nxt]      <= 1;
                    cacheData[data_idx_nxt][15:0] <= lsb_din_conv[31:16];
                  end
                  4'b1111: begin
                    cacheData[data_idx][127:120]  <= lsb_din_conv[7:0];
                    cacheDirty[data_idx_nxt]      <= 1;
                    cacheData[data_idx_nxt][23:0] <= lsb_din_conv[31:8];
                  end
                endcase
              end else begin
                // if (data_offset == 4'b1111) begin
                //   // dCache_d <= {nxt_datas[4'b0010], nxt_datas[4'b0001], nxt_datas[4'b0000], cur_datas[data_offset]};
                // dCache_d <= {nxt_block[23:0], cur_block[127:120]};
                // end else if (data_offset == 4'b1110) begin
                //   // dCache_d <= {nxt_datas[4'b0001], nxt_datas[4'b0000], cur_datas[data_offset+1'b1], cur_datas[data_offset]};
                //    dCache_d <= {nxt_block[15:0], cur_block[127:112]};
                // end else if (data_offset == 4'b1101) begin
                //   dCache_d <= {nxt_block[7:0], cur_block[127:104]};
                //   // dCache_d <= {nxt_datas[4'b0000], cur_datas[data_offset+2'b10], cur_datas[data_offset+1'b1], cur_datas[data_offset]};
                // end  else begin
                //   dCache_d <= {cur_datas[data_offset+2'b11], cur_datas[data_offset+2'b10], cur_datas[data_offset+1'b1], cur_datas[data_offset]};
                // end
                // read
                case (data_offset)
                  4'b0000: dCache_d <= cur_block[31:0];
                  4'b0001: dCache_d <= cur_block[39:8];
                  4'b0010: dCache_d <= cur_block[47:16];
                  4'b0011: dCache_d <= cur_block[55:24];
                  4'b0100: dCache_d <= cur_block[63:32];
                  4'b0101: dCache_d <= cur_block[71:40];
                  4'b0110: dCache_d <= cur_block[79:48];
                  4'b0111: dCache_d <= cur_block[87:56];
                  4'b1000: dCache_d <= cur_block[95:64];
                  4'b1001: dCache_d <= cur_block[103:72];
                  4'b1010: dCache_d <= cur_block[111:80];
                  4'b1011: dCache_d <= cur_block[119:88];
                  4'b1100: dCache_d <= cur_block[127:96];
                  4'b1101: dCache_d <= {nxt_block[7:0], cur_block[127:104]};
                  4'b1110: dCache_d <= {nxt_block[15:0], cur_block[127:112]};
                  4'b1111: dCache_d <= {nxt_block[23:0], cur_block[127:120]};
                endcase
              end
            end
          endcase
        end
      end
    end
  end

endmodule

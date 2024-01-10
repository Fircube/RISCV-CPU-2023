// `include "param.v"
`include "./riscv/src/param.v"

module predictor (
        input wire clk,     // system clock signal
        input wire rst_in,  // reset signal
        input wire rdy_in,  // ready signal, pause cpu when low
        input  wire [`ADDR_WIDTH]     mem_ain,    // address from memory controller
        input  wire                   rob_in_en,
        input  wire [`ADDR_WIDTH]     rob_ain,
        input  wire                   rob_jump,
        output wire                   jump         // jump signal
    );

    reg [1:0]             bht[`BHT_WIDTH];

    // wire [`BHT_WIDTH] pre_idx    = mem_ain[`BHT_IDX_RANGE]; // ?
    reg [`BHT_WIDTH] pre_idx;
    wire [`BHT_WIDTH] update_idx = rob_ain[`BHT_IDX_RANGE];

    assign jump = bht[pre_idx][1];

    integer i;

    always @(posedge clk) begin
        if (rst_in) begin
            pre_idx = 0;
            for (i = 0; i < `BHT_SIZE; i = i + 1) begin
                bht[i] <= 2'b01;
            end
        end
        else if (!rdy_in) begin
        end
        else begin
            pre_idx <= mem_ain[`BHT_IDX_RANGE];
            if (rob_in_en) begin
                case (bht[update_idx])
                    2'b00:
                        bht[update_idx] <= rob_jump ? 2'b01 : 2'b00;
                    2'b01:
                        bht[update_idx] <= rob_jump ? 2'b10 : 2'b00;
                    2'b10:
                        bht[update_idx] <= rob_jump ? 2'b11 : 2'b01;
                    2'b11:
                        bht[update_idx] <= rob_jump ? 2'b11 : 2'b10;
                endcase
            end
        end
    end
endmodule

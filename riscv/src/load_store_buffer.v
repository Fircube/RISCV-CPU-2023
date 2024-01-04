`include "./riscv/src/param.v"

module lsb (
        input wire clk,     // system clock signal
        input wire rst_in,  // reset signal
        input wire rdy_in,  // ready signal, pause cpu when low

        input wire roll_back,  // wrong prediction signal

        output wire lsb_full,  // load store buffer full signal
        output wire                  lsb2cdb_out_en,
        output wire [`ROB_IDX_WIDTH] lsb2cdb_rob_idx_out,
        output wire [   `DATA_WIDTH] lsb2cdb_val_out,

        // MemCtrl
        input  wire               mem_in_en,
        input  wire [`DATA_WIDTH] mem_din,
        output wire               mem_out_en,
        output wire               mem_rw,          // write/read signal (1 for write)
        output wire [        1:0] mem_data_width,
        output wire [`ADDR_WIDTH] mem_aout,
        output wire [`DATA_WIDTH] mem_dout,

        // IF
        input wire                     de_in_en,
        input wire                     de_rw_in,
        input wire [   `ROB_IDX_WIDTH] de_rob_idx_in,
        input wire [`LSB_OPCODE_WIDTH] de_op_in,
        input wire [      `DATA_WIDTH] de_V_mem_in,
        input wire                     de_Q_mem_in_en,
        input wire [   `ROB_IDX_WIDTH] de_Q_mem_in,
        input wire [      `DATA_WIDTH] de_V_reg_in,
        input wire                     de_Q_reg_in_en,
        input wire [   `ROB_IDX_WIDTH] de_Q_reg_in,
        input wire [      `DATA_WIDTH] de_offset_in,

        // ROB
        input wire rob_front_en,
        input wire [`ROB_IDX_WIDTH] rob_front_idx,

        // RS
        input wire                  rs_in_en,
        input wire [`ROB_IDX_WIDTH] rs_rob_idx_in,
        input wire [   `DATA_WIDTH] rs_val_in
    );
    localparam IDLE=0,WAIT_MC=1;
    reg status;

    reg               q_mem_out_en;
    reg               q_mem_rw;
    reg [        1:0] q_mem_data_width;
    reg [`ADDR_WIDTH] q_mem_aout;
    reg [`DATA_WIDTH] q_mem_dout;

    reg q_cdb_out_en;
    reg [`ROB_IDX_WIDTH] q_cdb_rob_idx;
    reg [`LSB_OPCODE_WIDTH] q_op;

    // inner
    reg [`ROB_IDX_WIDTH]    rob_idx     [`LSB_WIDTH];
    reg                     busy        [`LSB_WIDTH];
    reg                     rw          [`LSB_WIDTH];
    reg [`LSB_OPCODE_WIDTH] op          [`LSB_WIDTH];
    reg                     mem_rob_en  [`LSB_WIDTH];
    reg [   `ROB_IDX_WIDTH] mem_rob_idx [`LSB_WIDTH];
    reg [      `DATA_WIDTH] mem_val     [`LSB_WIDTH];
    reg                     reg_rob_en  [`LSB_WIDTH];
    reg [   `ROB_IDX_WIDTH] reg_rob_idx [`LSB_WIDTH];
    reg [   `DATA_WIDTH]    reg_val     [`LSB_WIDTH];
    reg [   `DATA_WIDTH]    offset      [`LSB_WIDTH];
    reg                     ready       [`LSB_WIDTH];

    // FIFO
    reg [`LSB_IDX_WIDTH]    front;
    reg [`LSB_IDX_WIDTH]    rear;
    reg [4:0]               last;
    reg empty;
    wire head_ready = busy[front] && !mem_rob_en[front] &&(rw[front]?(ready[front]&&!reg_rob_en[front]):(ready[front]||!is_io));

    wire pop = mem_in_en && status==WAIT_MC;
    wire [`LSB_IDX_WIDTH] nxt_front = front + pop;
    wire [`LSB_IDX_WIDTH] nxt_rear = rear + de_in_en;
    wire nxt_empty = (nxt_front == nxt_rear && (empty || pop && !de_in_en));
    assign lsb_full = (nxt_front == nxt_rear && !nxt_empty);

    wire [`ADDR_WIDTH] head_addr=mem_val[front]+offset[front];
    wire is_io = head_addr[17:16] == 2'b11;


    integer i;
    always @(posedge clk) begin
        if(rst_in) begin
            status<=IDLE;
            q_mem_out_en<=0;
            front<=0;
            rear<=0;
            last<=5'b10000;
            empty<=1;
            for (i = 0; i < `LSB_SIZE; i = i + 1) begin
                rob_idx[i]    <= 0;
                busy[i]       <= 0;
                rw[i]         <= 0;
                op[i]         <= 0;
                mem_rob_en[i] <= 0;
                mem_rob_idx[i]<= 0;
                mem_val[i]    <= 0;
                reg_rob_en[i] <= 0;
                reg_rob_idx[i]<= 0;
                reg_val[i]    <= 0;
                offset[i]     <= 0;
                ready[i]      <= 0;
            end
        end
        else if(roll_back) begin
            if(last==5'b10000) begin
                status<=IDLE;
                q_mem_out_en<=0;
                front<=0;
                rear<=0;
                empty<=1;
                for (i = 0; i < `LSB_SIZE; i = i + 1) begin
                    rob_idx[i]    <= 0;
                    busy[i]       <= 0;
                    rw[i]         <= 0;
                    op[i]         <= 0;
                    mem_rob_en[i] <= 0;
                    mem_rob_idx[i]<= 0;
                    mem_val[i]    <= 0;
                    reg_rob_en[i] <= 0;
                    reg_rob_idx[i]<= 0;
                    reg_val[i]    <= 0;
                    offset[i]     <= 0;
                    ready[i]      <= 0;
                end
            end
            else begin
                for (i = 0; i < `LSB_SIZE; i = i + 1) begin
                    busy[i]<=ready[i];
                end
                rear<=last+1;
                if(status==WAIT_MC && mem_in_en) begin
                    status<=IDLE;
                    q_mem_out_en<=0;
                    busy[front]<=0;
                    ready[front]<=0;
                    front<=front+1;
                    if(last[`LSB_IDX_WIDTH]==front) begin
                        empty<=1;
                        last<=5'b10000;
                    end
                end
            end
        end
        else if(!rdy_in) begin
            //
        end
        else begin
            if(de_in_en) begin
                rob_idx[rear]    <= de_rob_idx_in;
                busy[rear]       <= 1;
                rw[rear]         <= de_rw_in;
                op[rear]         <= de_op_in;
                mem_rob_en[rear] <= de_Q_mem_in_en;
                mem_rob_idx[rear]<= de_Q_mem_in;
                mem_val[rear]    <= de_V_mem_in;
                reg_rob_en[rear] <= de_Q_reg_in_en;
                reg_rob_idx[rear]<= de_Q_reg_in;
                reg_val[rear]    <= de_V_reg_in;
                offset[rear]     <= de_offset_in;
                ready[rear]      <= 0;
                rear<=rear+1;
            end


            if(rob_front_en) begin
                for (i = 0; i < `LSB_SIZE; i = i + 1) begin
                    if(busy[i]&&rob_idx[i]==rob_front_idx) begin
                        ready[i]<=1;
                        last <= {1'b0, i[`LSB_IDX_WIDTH]};
                    end
                end
            end

            if(rs_in_en) begin
                for (i = 0; i < `LSB_SIZE; i = i + 1) begin
                    if(busy[i]) begin
                        if(mem_rob_en[i] && rs_rob_idx_in == mem_rob_idx[i]) begin
                            mem_rob_en[i]<=0;
                            mem_val[i]<=rs_val_in;
                        end
                        if(reg_rob_en[i] && rs_rob_idx_in == reg_rob_idx[i]) begin
                            reg_rob_en[i]<=0;
                            reg_val[i]<=rs_val_in;
                        end
                    end
                end
            end

            q_cdb_out_en<=0;
            if(status==WAIT_MC) begin
                if(mem_in_en) begin
                    status<=IDLE;
                    q_mem_out_en<=0;
                    busy[front]<=0;
                    ready[front]<=0;
                    if(!rw[front]) begin
                        q_cdb_out_en<=1;
                        q_cdb_rob_idx<=rob_idx[front];
                    end
                    if(last[`LSB_IDX_WIDTH]==front) begin
                        last<=5'b10000;
                    end
                end
            end
            else begin
                q_mem_out_en<=0;
                if(head_ready) begin
                    status<=WAIT_MC;
                    q_mem_out_en<=1;
                    q_mem_aout<=head_addr;
                    q_mem_rw<=rw[front];
                    q_mem_dout<=reg_val[front];
                end
            end

            empty<=nxt_empty;
            front<=nxt_front;
            rear<=nxt_rear;
        end
    end

    assign mem_out_en = q_mem_out_en;
    assign mem_rw = q_mem_rw;
    assign mem_data_width = q_mem_data_width;
    assign mem_aout = q_mem_aout;
    assign mem_dout = q_mem_dout;

    assign lsb2cdb_out_en = q_cdb_out_en;
    assign lsb2cdb_rob_idx_out = q_cdb_rob_idx;
    assign lsb2cdb_val_out = (q_op == 3'b000) ? {{24{mem_din[7]}},  mem_din[7:0]} :
           (q_op == 3'b001) ? {{16{mem_din[15]}}, mem_din[15:0]} :
           mem_din;
endmodule

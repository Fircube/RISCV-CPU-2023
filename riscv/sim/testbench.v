// testbench top module file
// for simulation only

`timescale 1ns/1ps
module testbench;

// `define DEBUG

reg clk;
reg rst;

riscv_top #(.SIM(1)) top(
    .EXCLK(clk),
    .btnC(rst),
    .Tx(),
    .Rx(),
    .led()
);

initial begin
  clk=0;
  rst=1;
  repeat(50) #1 clk=!clk;
  rst=0; 
  forever #1 clk=!clk;

  $finish;
end

initial begin
`ifdef DEBUG
     $dumpfile("test.vcd");
     $dumpvars(0, testbench);
`endif
     #30000000 $finish;
end

endmodule

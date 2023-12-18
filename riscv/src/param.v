`define ADDR_WIDTH  31:0
`define DATA_WIDTH  31:0
`define INSTR_WIDTH 31:0 // RISCV 指令长度
`define MEM_WIDTH   31:0


// ICache
// 16 Blocks * 16 Instr per block * 4 Bype per Instr
`define ICACHE_SIZE         16
`define ICACHE_BLK_INSTR    16
`define ICACHE_BLK_SIZE     64
`define ICACHE_BLK_WIDTH    511:0
// 0x0 - 0x20000 
`define ICACHE_TAG_RANGE    31:10 
`define ICACHE_TAG_WIDTH    21:0
`define ICACHE_IDX_RANGE    9:6 
`define ICACHE_IDX_WIDTH    3:0
`define ICACHE_OFFSET_RANGE 5:2 // last 2 bit can be ignore
`define ICACHE_OFFSET_WIDTH 3:0

// size
`define ROB_SIZE 16
`define REG_SIZE 32

// index width
`define ROB_IDX_WIDTH 3:0
`define REG_IDX_WIDTH 4:0

// opcode
`define OPCODE_RANGE 6:0
`define OPCODE_WIDTH 6:0
// R-type
`define OPCODE_R 7'b0110011
// I-type
`define OPCODE_I 7'b0010011
`define OPCODE_L 7'b0000011
// S-type
`define OPCODE_S 7'b0100011
// B-type
`define OPCODE_B 7'b1100011
// U-type
`define OPCODE_LUI   7'b0110111
`define OPCODE_AUIPC 7'b0010111
// J-type
`define OPCODE_JAL  7'b1101111
`define OPCODE_JALR 7'b1100111

// funct
`define FUNCT3_RANGE 14:12
`define FUNCT3_WIDTH 2:0
`define FUNCT7_RANGE 31:25
`define FUNCT7_WIDTH 6:0

`define FUNCT3_ADD  3'b000
`define FUNCT3_SUB  3'b000
`define FUNCT3_SLL  3'b001
`define FUNCT3_SLT  3'b010
`define FUNCT3_SLTU 3'b011
`define FUNCT3_XOR  3'b100
`define FUNCT3_SRL  3'b101
`define FUNCT3_SRA  3'b101
`define FUNCT3_OR   3'b110
`define FUNCT3_AND  3'b111

`define FUNCT7_ADD 7'b0000000
`define FUNCT7_SUB 7'b0100000
`define FUNCT7_SRL 7'b0000000
`define FUNCT7_SRA 7'b0100000

`define FUNCT3_ADDI  3'b000
`define FUNCT3_SLTI  3'b010
`define FUNCT3_SLTIU 3'b011
`define FUNCT3_XORI  3'b100
`define FUNCT3_ORI   3'b110
`define FUNCT3_ANDI  3'b111
`define FUNCT3_SLLI  3'b001
`define FUNCT3_SRLI  3'b101
`define FUNCT3_SRAI  3'b101

`define FUNCT7_SRLI 7'b0000000
`define FUNCT7_SRAI 7'b0100000

`define FUNCT3_LB  3'b000
`define FUNCT3_LH  3'b001
`define FUNCT3_LW  3'b010
`define FUNCT3_LBU 3'b100
`define FUNCT3_LHU 3'b101

`define FUNCT3_SB 3'b000
`define FUNCT3_SH 3'b001
`define FUNCT3_SW 3'b010

`define FUNCT3_BEQ  3'b000
`define FUNCT3_BNE  3'b001
`define FUNCT3_BLT  3'b100
`define FUNCT3_BGE  3'b101
`define FUNCT3_BLTU 3'b110
`define FUNCT3_BGEU 3'b111

// rs rd
`define RS1_RANGE 19:15
`define RS2_RANGE 24:20
`define RD_RANGE 11:7

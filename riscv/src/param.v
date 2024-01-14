`define ADDR_WIDTH 31:0
`define DATA_WIDTH 31:0
`define INSTR_WIDTH 31:0 // RISCV 指令长度
`define MEM_WIDTH 31:0


// ICache
// direct mapped
// 16 Blocks * 16 Instr per block * 4 Bype per Instr
// `define ICACHE_SIZE 16
// `define ICACHE_BLK_INSTR 16
// `define ICACHE_BLK_SIZE 64
`define ICACHE_BLK_WIDTH 511:0
// 0x0 - 0x20000 
`define ICACHE_TAG_RANGE 31:10 
`define ICACHE_TAG_WIDTH 21:0
`define ICACHE_IDX_RANGE 9:6 
`define ICACHE_IDX_WIDTH 3:0
`define ICACHE_OFFSET_RANGE 5:2 // last 2 bit can be ignore
`define ICACHE_OFFSET_WIDTH 3:0

// size
`define ROB_SIZE 16
`define REG_SIZE 32
`define RS_SIZE 16
`define LSB_SIZE 16

// width
`define ROB_WIDTH 15:0
`define REG_WIDTH 31:0
`define RS_WIDTH 15:0
`define LSB_WIDTH 15:0

// index width
`define ROB_IDX_SIZE 4
`define ROB_IDX_WIDTH 3:0
`define REG_IDX_WIDTH 4:0
`define RS_IDX_WIDTH 3:0
`define LSB_IDX_WIDTH 3:0

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
`define OPCODE_LUI 7'b0110111
`define OPCODE_AUIPC 7'b0010111
// J-type
`define OPCODE_JAL 7'b1101111
`define OPCODE_JALR 7'b1100111

// funct
`define FUNCT3_RANGE 14:12
`define FUNCT3_WIDTH 2:0
`define FUNCT7_RANGE 31:25
`define FUNCT7_WIDTH 6:0

`define FUNCT3_ADD 3'b000
`define FUNCT3_SUB 3'b000
`define FUNCT3_SLL 3'b001
`define FUNCT3_SLT 3'b010
`define FUNCT3_SLTU 3'b011
`define FUNCT3_XOR 3'b100
`define FUNCT3_SRL 3'b101
`define FUNCT3_SRA 3'b101
`define FUNCT3_OR 3'b110
`define FUNCT3_AND 3'b111

`define FUNCT7_ADD 7'b0000000
`define FUNCT7_SUB 7'b0100000
`define FUNCT7_SRL 7'b0000000
`define FUNCT7_SRA 7'b0100000

`define FUNCT3_ADDI 3'b000
`define FUNCT3_SLTI 3'b010
`define FUNCT3_SLTIU 3'b011
`define FUNCT3_XORI 3'b100
`define FUNCT3_ORI 3'b110
`define FUNCT3_ANDI 3'b111
`define FUNCT3_SLLI 3'b001
`define FUNCT3_SRLI 3'b101
`define FUNCT3_SRAI 3'b101

`define FUNCT7_SRLI 7'b0000000
`define FUNCT7_SRAI 7'b0100000

`define FUNCT3_LB 3'b000
`define FUNCT3_LH 3'b001
`define FUNCT3_LW 3'b010
`define FUNCT3_LBU 3'b100
`define FUNCT3_LHU 3'b101

`define FUNCT3_SB 3'b000
`define FUNCT3_SH 3'b001
`define FUNCT3_SW 3'b010

`define FUNCT3_BEQ 3'b000
`define FUNCT3_BNE 3'b001
`define FUNCT3_BLT 3'b100
`define FUNCT3_BGE 3'b101
`define FUNCT3_BLTU 3'b110
`define FUNCT3_BGEU 3'b111

`define RS_OPCODE_WIDTH 3:0
`define RS_OPCODE_SIZE 4

`define RS_ADD 4'b0000
`define RS_SUB 4'b0001
`define RS_SLL 4'b0010
`define RS_SLT 4'b0011
`define RS_SLTU 4'b0100
`define RS_XOR 4'b0101
`define RS_SRL 4'b0110
`define RS_SRA 4'b0111
`define RS_OR 4'b1000
`define RS_AND 4'b1001
`define RS_BEQ 4'b1010
`define RS_BNE 4'b1011
`define RS_BLT 4'b1100
`define RS_BGE 4'b1101
`define RS_BLTU 4'b1110
`define RS_BGEU 4'b1111

`define LSB_OPCODE_WIDTH 2:0
`define LSB_OPCODE_SIZE 3

`define LSB_B 3'b000
`define LSB_H 3'b001
`define LSB_W 3'b010
`define LSB_BU 3'b011
`define LSB_HU 3'b100

`define ROB_OPCODE_WIDTH 1:0
`define ROB_OPCODE_SIZE 2

`define ROB_REG 2'b00
`define ROB_BR 2'b01
`define ROB_MEM 2'b10

// rs rd
`define RS1_RANGE 19:15
`define RS2_RANGE 24:20
`define RD_RANGE 11:7
`define REG_WIDTH 4:0

// predictor
// `define BHT_SIZE 256
`define BHT_IDX_RANGE 9:2
`define BHT_IDX_WIDTH 7:0
`define BHT_WIDTH 255:0

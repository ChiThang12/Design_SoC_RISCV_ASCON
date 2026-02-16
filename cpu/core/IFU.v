// // ============================================================================
// // Module: IFU - Instruction Fetch Unit (FIXED v2)
// // ============================================================================
// // FIX LOG:
// //   BUG #1 FIX: Instruction_Code output là COMBINATIONAL từ imem_rdata khi
// //               imem_ready=1 và !stall. Không còn registered latch gây +1 cycle.
// //
// //   BUG #3 FIX: PC_out xuất ra next_pc (combinational) thay vì PC register,
// //               để IF/ID pipeline register nhận đúng PC của instruction đang fetch
// //               ngay trong cycle hiện tại.
// //
// // Pipeline timing đúng sau fix:
// //   Cycle N:   imem_addr = PC → ICache hit → imem_ready=1
// //              Instruction_Code = imem_rdata (COMBINATIONAL, không delay)
// //              IF/ID latch instruction ngay cuối Cycle N
// //   Cycle N+1: PC đã cập nhật = PC+4, fetch instruction tiếp theo ngay lập tức
// // ============================================================================

// module IFU (
//     input wire clock,
//     input wire reset,
    
//     // Control signals
//     input wire pc_src,              // 0: PC+4 (sequential), 1: target_pc (branch/jump)
//     input wire stall,               // 1: giữ nguyên PC (pipeline stall)
    
//     // Branch/Jump target address
//     input wire [31:0] target_pc,    // Địa chỉ nhảy đến
    
//     // AXI-Like Instruction Memory Interface
//     output wire [31:0] imem_addr,   // Address to instruction memory (COMBINATIONAL)
//     output wire        imem_valid,  // Request valid
//     input wire [31:0]  imem_rdata,  // Instruction data from memory
//     input wire         imem_ready,  // Memory ready signal
    
//     // Outputs
//     output wire [31:0] PC_out,          // Current PC (combinational từ PC register)
//     output wire [31:0] Instruction_Code // Instruction được fetch (COMBINATIONAL)
// );

//     // ========================================================================
//     // Program Counter Register
//     // ========================================================================
//     reg [31:0] PC;
    
//     // ========================================================================
//     // Next PC Calculation (Combinational)
//     // ========================================================================
//     wire [31:0] next_pc;
//     assign next_pc = pc_src ? target_pc : (PC + 32'd4);
    
//     // ========================================================================
//     // [FIX #1] imem_addr - COMBINATIONAL output từ PC register
//     // Không cần register thêm, ICache nhận địa chỉ ngay lập tức
//     // ========================================================================
//     assign imem_addr  = PC;
//     assign imem_valid = 1'b1;  // Luôn request, ICache tự handle
    
//     // ========================================================================
//     // Program Counter Update
//     // Chỉ cập nhật PC khi: không stall VÀ imem_ready=1
//     // ========================================================================
//     always @(posedge clock or posedge reset) begin
//         if (reset) begin
//             PC <= 32'h00000000;
//         end else begin
//             if (!stall && imem_ready) begin
//                 PC <= next_pc;
//             end
//             // Nếu stall hoặc memory chưa ready: giữ nguyên PC
//         end
//     end
    
//     // ========================================================================
//     // [FIX #2] Instruction_Code - HOÀN TOÀN COMBINATIONAL
//     // ============================================================
//     // BUG CŨ: Instruction_Code là reg, được latch ở posedge clock SAU KHI
//     //         imem_ready=1. Điều này tạo ra 1 cycle delay vô ích:
//     //           Cycle N:   imem_ready=1  → latch vào reg
//     //           Cycle N+1: Instruction_Code mới có giá trị đúng
//     //                      → IF/ID mới nhận được instruction
//     //
//     // FIX MỚI: Instruction_Code là wire combinational:
//     //           Cycle N:   imem_ready=1  → Instruction_Code = imem_rdata NGAY LẬP TỨC
//     //                      IF/ID latch instruction cuối Cycle N (không mất cycle)
//     //
//     // Khi stall=1: imem_ready sẽ =0 (hazard stall PC không cho cập nhật),
//     //              nên IF/ID register tự giữ giá trị cũ do stall=1
//     // ========================================================================
    
//     // Hold register: giữ instruction cuối cùng hợp lệ khi imem_ready=0
//     reg [31:0] instr_hold;
//     always @(posedge clock or posedge reset) begin
//         if (reset) begin
//             instr_hold <= 32'h00000013; // NOP
//         end else if (imem_ready && !stall) begin
//             instr_hold <= imem_rdata;   // Ghi lại instruction hợp lệ
//         end
//     end
    
//     // Combinational output: khi ready → dùng data trực tiếp từ memory/cache
//     //                       khi không ready → giữ instruction cũ từ hold register
//     assign Instruction_Code = (imem_ready && !stall) ? imem_rdata : instr_hold;
    
//     // ========================================================================
//     // [FIX #3] PC_out - COMBINATIONAL từ PC register
//     // IF/ID pipeline register cần PC của instruction hiện tại đang được fetch
//     // ========================================================================
//     assign PC_out = PC;

// endmodule

// ============================================================================
// IFU.v - Instruction Fetch Unit (FINAL CORRECT VERSION)
// ============================================================================
// Compatible với COMBINATIONAL imem (testbench style)
// ============================================================================

module IFU (
    input  wire        clock,
    input  wire        reset,
    input  wire        pc_src,        // Branch/jump taken
    input  wire        stall,         // Pipeline stall signal
    input  wire [31:0] target_pc,     // Branch/jump target
    
    // Instruction Memory Interface  
    output wire [31:0] imem_addr,
    output wire        imem_valid,
    input  wire [31:0] imem_rdata,
    input  wire        imem_ready,
    
    // Outputs to pipeline
    output wire [31:0] PC_out,              // PC of current instruction
    output wire [31:0] Instruction_Code
);

    // ========================================================================
    // PC Registers
    // ========================================================================
    reg [31:0] pc_reg;          // Current PC (used for fetching)
    reg [31:0] pc_of_instr;     // PC của instruction hiện tại trong instr_reg
    
    always @(posedge clock or posedge reset) begin
        if (reset) begin
            pc_reg       <= 32'h0;
            pc_of_instr  <= 32'h0;
        end else if (!stall) begin
            // Save PC BEFORE incrementing
            // Đây chính là PC của instruction sẽ được latch trong cycle này
            pc_of_instr <= pc_reg;
            
            // Then update PC for next fetch
            if (pc_src)
                pc_reg <= target_pc;
            else
                pc_reg <= pc_reg + 32'd4;
        end
        // stall: giữ nguyên cả 2 PC registers
    end
    
    // Output PC of instruction currently in instruction register
    assign PC_out = pc_of_instr;

    // ========================================================================
    // Instruction Memory Access
    // ========================================================================
    assign imem_valid = !stall;
    assign imem_addr  = pc_reg;  // Fetch from current PC
    
    // ========================================================================
    // Instruction Register
    // ========================================================================
    reg [31:0] instr_reg;
    
    always @(posedge clock or posedge reset) begin
        if (reset) begin
            instr_reg <= 32'h00000013;  // NOP
        end else if (imem_valid && imem_ready && !stall) begin
            instr_reg <= imem_rdata;
        end
    end
    
    assign Instruction_Code = instr_reg;

endmodule
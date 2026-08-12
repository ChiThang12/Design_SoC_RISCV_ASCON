`timescale 1ns/1ps

// ============================================================================
// Module  : plic_priority_encoder
// Project : RISC-V SoC — PLIC
//
// Tìm source ID có priority cao nhất trong số các source pending & enabled.
// Output: ID của source thắng (0 = không có), priority của source đó.
//
// Algorithm: linear scan XUÔI từ source 1..NUM_SRC-1, giữ max priority.
// Ghi đè chỉ khi prio[i] STRICTLY cao hơn winner hiện tại.
// Tie-break: source ID nhỏ hơn thắng — vì loop xuôi, source ID nhỏ
// được ghi trước và không bị ghi đè khi priority bằng nhau.
//
// WHY combinational: PLIC spec yêu cầu claim/complete phải phản ánh
// trạng thái hiện tại ngay lập tức. Latency 1 cycle nếu dùng FF sẽ
// làm CPU đọc stale value ngay sau khi IRQ assert.
// ============================================================================

module plic_priority_encoder #(
    parameter NUM_SRC = 32,   // số nguồn IRQ (source 0 luôn reserved)
    parameter PRIO_W  = 3     // số bit priority (0..7)
)(
    input  wire [NUM_SRC-1:0]          pending,    // pending[i] = source i có IRQ
    input  wire [NUM_SRC-1:0]          enabled,    // enabled[i] = context 0 enable
    input  wire [PRIO_W-1:0]           threshold,  // priority threshold context 0
    input  wire [PRIO_W*NUM_SRC-1:0]   priority_flat, // priority[i] = [PRIO_W*i+:PRIO_W]

    output reg  [$clog2(NUM_SRC)-1:0]  claim_id,   // source ID thắng (0=none)
    output reg  [PRIO_W-1:0]           claim_prio, // priority của winner
    output wire                         irq_pending // =1 nếu có source vượt threshold
);

    localparam ID_W = $clog2(NUM_SRC);

    integer i;
    always @(*) begin
        claim_id   = {ID_W{1'b0}};
        claim_prio = {PRIO_W{1'b0}};

        // Source 0 always reserved — bắt đầu từ i=1
        //
        // BUG FIX: Loop gốc chạy NGƯỢC (NUM_SRC-1 → 1) với điều kiện:
        //   if (prio[i] > claim_prio || claim_id == 0)
        //
        // Lỗi: khi claim_id==0 (chưa có winner), điều kiện || luôn true
        // → mọi source hợp lệ đều ghi đè → source cuối cùng được xét
        // (source ID nhỏ nhất trong loop ngược) thắng.
        // Nhưng vì loop NGƯỢC, source cuối cùng được xét là source 1 (nhỏ nhất)...
        // ... trừ khi có source có priority bằng nhau ở bước giữa.
        //
        // Ví dụ: src2(prio=5), src3(prio=5), loop ngược:
        //   i=31..4: không có pending
        //   i=3: pending, prio=5>0 → ghi claim_id=3, claim_prio=5
        //   i=2: pending, prio=5 > claim_prio(5)? NO. claim_id==0? NO (=3).
        //        → không ghi đè → claim_id=3 THẮNG (sai! ID nhỏ phải thắng)
        //
        // FIX ĐÚNG: Loop XUÔI từ 1 → NUM_SRC-1
        //   Chỉ ghi đè khi prio[i] > claim_prio (strictly higher, không có ||).
        //   - Source đầu tiên hợp lệ (ID nhỏ nhất) ghi vào vì claim_prio=0
        //     và prio[i] > 0 (đã pass threshold check).
        //   - Source sau chỉ ghi đè khi priority CAO HƠN.
        //   - Tie-break: source ID nhỏ không bị ghi đè → thắng. ✓
        //
        // WHY "prio[i] > 0" luôn đúng ở bước đầu:
        //   Điều kiện eligible đã có "prio[i] > threshold".
        //   Nếu threshold=0 thì prio[i] >= 1 → prio[i] > claim_prio(0) ✓
        //   Nếu threshold>0 thì prio[i] > threshold > 0 ✓
        for (i = 1; i < NUM_SRC; i = i + 1) begin
            // Eligible: pending AND enabled AND priority > threshold
            if (pending[i] && enabled[i] && (priority_flat[PRIO_W*i +: PRIO_W] > threshold)) begin
                // Ghi đè chỉ khi STRICTLY higher priority
                // Tie → giữ nguyên claim_id (ID nhỏ hơn đã ghi trước thắng)
                if (priority_flat[PRIO_W*i +: PRIO_W] > claim_prio) begin
                    claim_id   = i[ID_W-1:0];
                    claim_prio = priority_flat[PRIO_W*i +: PRIO_W];
                end
            end
        end
    end

    assign irq_pending = (claim_id != {ID_W{1'b0}});

endmodule
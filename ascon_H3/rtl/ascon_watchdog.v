`timescale 1ns/1ps

// ============================================================================
// Module  : ascon_watchdog
// Project : ASCON Crypto Accelerator IP
// Version : 1.0
//
// Description:
//   Countdown watchdog timer để phát hiện trường hợp DMA hoặc CORE bị treo
//   (deadlock khi AXI slave không phản hồi hoặc FSM rơi vào trạng thái không
//   hợp lệ).
//
// Cách hoạt động:
//   - Khi enable=1 VÀ busy=1: bộ đếm đếm lùi từ cfg về 0.
//   - Khi đếm về 0: assert timeout=1 (sticky cho đến khi clear).
//   - Khi clear=1: bộ đếm reset về cfg, timeout=0.
//   - Khi enable=0 hoặc busy=0: bộ đếm bị giữ (không đếm), timeout không thay đổi.
//
// Firmware:
//   1. Ghi WDT_CFG = số cycle timeout (ví dụ: 50000 = 500µs tại 100MHz).
//   2. Ghi WDT_CTRL[0] = 1 để enable.
//   3. Nếu WDT timeout → STATUS[7]=1, IRQ assert (nếu IRQ_EN[3]=1).
//   4. Firmware phải ghi CTRL[1]=SOFT_RST để clear timeout và restart.
//
// Interface:
//   cfg    [31:0] : số clock cycle trước khi timeout (từ WDT_CFG register).
//                  Khi cfg=0: watchdog disabled hoàn toàn.
//   enable        : từ WDT_CTRL[0]. Enable counting.
//   busy          : từ core_busy | dma_busy. Chỉ đếm khi hệ thống đang bận.
//   clear         : pulse khi core_done hoặc soft_rst. Reset bộ đếm và clear timeout.
//   timeout       : sticky output → kết nối vào STATUS[7].
// ============================================================================

module ascon_watchdog (
    input  wire         clk,
    input  wire         rst_n,

    input  wire [31:0]  cfg,       // WDT_CFG: timeout threshold (0 = disabled)
    input  wire         enable,    // WDT_CTRL[0]: enable watchdog
    input  wire         busy,      // core_busy | dma_busy
    input  wire         clear,     // pulse: reset counter and clear timeout flag

    output reg          timeout    // sticky: 1 when counter expired
);

    reg [31:0] counter;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= 32'h0;
            timeout <= 1'b0;
        end else begin
            if (clear) begin
                // Sync clear: reset counter, deassert timeout
                counter <= cfg;
                timeout <= 1'b0;
            end else if (!enable || cfg == 32'h0) begin
                // Disabled: hold counter at cfg, don't count
                counter <= cfg;
            end else if (busy) begin
                // Active and busy: count down
                if (counter == 32'h0) begin
                    // Already expired
                    timeout <= 1'b1;
                end else begin
                    counter <= counter - 32'h1;
                    if (counter == 32'h1) begin
                        // Will reach 0 next cycle → assert timeout now
                        timeout <= 1'b1;
                    end
                end
            end else begin
                // Not busy: reload counter (pause counting)
                counter <= cfg;
            end
        end
    end

endmodule

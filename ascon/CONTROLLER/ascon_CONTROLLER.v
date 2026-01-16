// ============================================================================
// ASCON_CONTROLLER (FSM)
// Mô tả: FSM điều khiển toàn bộ flow của ASCON
// Hỗ trợ: AEAD Encryption/Decryption và Hash mode
// ============================================================================

module ASCON_CONTROLLER (
    // Clock và Reset
    input  wire        clk,
    input  wire        rst_n,
    
    // Control inputs
    input  wire [1:0]  mode,           // 00: Encrypt, 01: Decrypt, 10: Hash, 11: Reserved
    input  wire        start,
    
    // Data flow control
    input  wire        data_valid,
    input  wire        data_last,
    input  wire        ad_valid,
    input  wire        ad_last,
    
    // Permutation status
    input  wire        perm_done,
    
    // Outputs - FSM state
    output reg  [4:0]  state,
    
    // Outputs - Control signals for state register
    output reg         load_init,
    output reg  [2:0]  init_select,
    
    // Outputs - Control signals for permutation
    output reg         start_perm,
    output reg  [3:0]  perm_rounds,
    
    // Outputs - Control signals for XOR operations
    output reg         xor_enable,
    output reg  [2:0]  xor_position,
    
    // Outputs - Data flow
    output reg         output_enable,
    
    // Outputs - Status
    output reg         ready,
    output reg         busy
);

    // ========================================================================
    // State encoding
    // ========================================================================
    localparam [4:0] IDLE         = 5'd0;
    localparam [4:0] INIT         = 5'd1;
    localparam [4:0] INIT_PERM    = 5'd2;
    localparam [4:0] PROCESS_AD   = 5'd3;
    localparam [4:0] AD_PERM      = 5'd4;
    localparam [4:0] AD_FINAL     = 5'd5;
    localparam [4:0] PROCESS_DATA = 5'd6;
    localparam [4:0] DATA_PERM    = 5'd7;
    localparam [4:0] FINALIZE     = 5'd8;
    localparam [4:0] FINAL_PERM   = 5'd9;
    localparam [4:0] OUTPUT_TAG   = 5'd10;
    localparam [4:0] HASH_INIT    = 5'd11;
    localparam [4:0] HASH_ABSORB  = 5'd12;
    localparam [4:0] HASH_SQUEEZE = 5'd13;
    localparam [4:0] WAIT_PERM    = 5'd14;
    
    // ========================================================================
    // Mode encoding
    // ========================================================================
    localparam [1:0] MODE_ENCRYPT = 2'b00;
    localparam [1:0] MODE_DECRYPT = 2'b01;
    localparam [1:0] MODE_HASH    = 2'b10;
    
    // ========================================================================
    // Init select encoding
    // ========================================================================
    localparam [2:0] INIT_IV_KEY_NONCE = 3'd0;
    localparam [2:0] INIT_HASH_IV      = 3'd1;
    localparam [2:0] INIT_KEY_XOR      = 3'd2;
    localparam [2:0] INIT_DOMAIN_SEP   = 3'd3;
    
    // ========================================================================
    // Internal registers
    // ========================================================================
    reg [4:0]  next_state;
    reg [1:0]  mode_reg;
    reg        has_ad;           // Track if there is Associated Data
    reg        data_phase_done;  // Track if data processing is complete
    
    // ========================================================================
    // FSM State Register
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            mode_reg <= 2'b00;
            has_ad <= 1'b0;
            data_phase_done <= 1'b0;
        end
        else begin
            state <= next_state;
            
            // Latch mode when starting
            if (state == IDLE && start) begin
                mode_reg <= mode;
            end
            
            // Track if we have AD
            if (state == PROCESS_AD && ad_valid) begin
                has_ad <= 1'b1;
            end
            
            // Track data phase completion
            if (state == PROCESS_DATA && data_last) begin
                data_phase_done <= 1'b1;
            end
            
            // Reset flags when returning to IDLE
            if (state == OUTPUT_TAG || state == HASH_SQUEEZE) begin
                if (next_state == IDLE) begin
                    has_ad <= 1'b0;
                    data_phase_done <= 1'b0;
                end
            end
        end
    end
    
    // ========================================================================
    // FSM Next State Logic
    // ========================================================================
    always @(*) begin
        // Default: stay in current state
        next_state = state;
        
        case (state)
            IDLE: begin
                if (start) begin
                    if (mode == MODE_HASH) begin
                        next_state = HASH_INIT;
                    end
                    else begin
                        next_state = INIT;
                    end
                end
            end
            
            // ================================================================
            // AEAD Flow (Encryption/Decryption)
            // ================================================================
            INIT: begin
                next_state = INIT_PERM;
            end
            
            INIT_PERM: begin
                if (perm_done) begin
                    next_state = PROCESS_AD;
                end
            end
            
            PROCESS_AD: begin
                if (ad_valid) begin
                    next_state = AD_PERM;
                end
                else if (ad_last || !ad_valid) begin
                    next_state = AD_FINAL;
                end
            end
            
            AD_PERM: begin
                if (perm_done) begin
                    if (ad_last) begin
                        next_state = AD_FINAL;
                    end
                    else begin
                        next_state = PROCESS_AD;
                    end
                end
            end
            
            AD_FINAL: begin
                next_state = PROCESS_DATA;
            end
            
            PROCESS_DATA: begin
                if (data_valid) begin
                    next_state = DATA_PERM;
                end
                else if (data_last) begin
                    next_state = FINALIZE;
                end
            end
            
            DATA_PERM: begin
                if (perm_done) begin
                    if (data_last) begin
                        next_state = FINALIZE;
                    end
                    else begin
                        next_state = PROCESS_DATA;
                    end
                end
            end
            
            FINALIZE: begin
                next_state = FINAL_PERM;
            end
            
            FINAL_PERM: begin
                if (perm_done) begin
                    next_state = OUTPUT_TAG;
                end
            end
            
            OUTPUT_TAG: begin
                next_state = IDLE;
            end
            
            // ================================================================
            // Hash Flow
            // ================================================================
            HASH_INIT: begin
                next_state = WAIT_PERM;
            end
            
            WAIT_PERM: begin
                if (perm_done) begin
                    next_state = HASH_ABSORB;
                end
            end
            
            HASH_ABSORB: begin
                if (data_valid) begin
                    if (data_last) begin
                        next_state = HASH_SQUEEZE;
                    end
                    else begin
                        next_state = WAIT_PERM;
                    end
                end
            end
            
            HASH_SQUEEZE: begin
                next_state = IDLE;
            end
            
            default: begin
                next_state = IDLE;
            end
        endcase
    end
    
    // ========================================================================
    // FSM Output Logic
    // ========================================================================
    always @(*) begin
        // Default values
        load_init      = 1'b0;
        init_select    = 3'd0;
        start_perm     = 1'b0;
        perm_rounds    = 4'd0;
        xor_enable     = 1'b0;
        xor_position   = 3'd0;
        output_enable  = 1'b0;
        ready          = 1'b0;
        busy           = 1'b1;
        
        case (state)
            IDLE: begin
                ready = 1'b1;
                busy  = 1'b0;
            end
            
            INIT: begin
                load_init   = 1'b1;
                init_select = INIT_IV_KEY_NONCE;
            end
            
            INIT_PERM: begin
                if (next_state == INIT_PERM && state != INIT) begin
                    // Stay in perm, don't restart
                end
                else begin
                    start_perm  = 1'b1;
                    perm_rounds = 4'd12;  // p^12 for initialization
                end
            end
            
            PROCESS_AD: begin
                if (ad_valid) begin
                    xor_enable   = 1'b1;
                    xor_position = 3'd0;  // XOR into x0
                end
            end
            
            AD_PERM: begin
                if (next_state == AD_PERM && state != PROCESS_AD) begin
                    // Stay in perm
                end
                else begin
                    start_perm  = 1'b1;
                    perm_rounds = 4'd6;   // p^6 for AD processing
                end
            end
            
            AD_FINAL: begin
                xor_enable   = 1'b1;
                xor_position = 3'd4;      // Domain separation in x4
            end
            
            PROCESS_DATA: begin
                if (data_valid) begin
                    xor_enable    = 1'b1;
                    xor_position  = 3'd0;  // XOR into x0
                    output_enable = 1'b1;  // Output ciphertext/plaintext
                end
            end
            
            DATA_PERM: begin
                if (next_state == DATA_PERM && state != PROCESS_DATA) begin
                    // Stay in perm
                end
                else begin
                    start_perm  = 1'b1;
                    perm_rounds = 4'd6;    // p^6 for data processing
                end
            end
            
            FINALIZE: begin
                xor_enable   = 1'b1;
                xor_position = 3'd1;       // XOR key into x1 and x2
            end
            
            FINAL_PERM: begin
                if (next_state == FINAL_PERM && state != FINALIZE) begin
                    // Stay in perm
                end
                else begin
                    start_perm  = 1'b1;
                    perm_rounds = 4'd12;   // p^12 for finalization
                end
            end
            
            OUTPUT_TAG: begin
                output_enable = 1'b1;      // Output authentication tag
            end
            
            // ================================================================
            // Hash mode outputs
            // ================================================================
            HASH_INIT: begin
                load_init   = 1'b1;
                init_select = INIT_HASH_IV;
                start_perm  = 1'b1;
                perm_rounds = 4'd12;
            end
            
            WAIT_PERM: begin
                // Just wait for permutation to complete
            end
            
            HASH_ABSORB: begin
                if (data_valid) begin
                    xor_enable   = 1'b1;
                    xor_position = 3'd0;
                    
                    if (!data_last) begin
                        start_perm  = 1'b1;
                        perm_rounds = 4'd12;
                    end
                end
            end
            
            HASH_SQUEEZE: begin
                output_enable = 1'b1;      // Output hash
            end
            
            default: begin
                // Keep default values
            end
        endcase
    end

endmodule
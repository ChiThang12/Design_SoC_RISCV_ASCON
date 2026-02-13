module ASCON_SBOX (
    input  wire [4:0] in,
    output reg  [4:0] out
);
    // Temporary variables
    reg [4:0] x;  // State after initial XORs
    reg [4:0] t;  // T array for Chi layer
    
    always @(*) begin
        // ============================================================
        // STEP 1: Initial XORs
        // ============================================================
        // x[0] ^= x[4]
        // x[4] ^= x[3]
        // x[2] ^= x[1]
        
        x[0] = in[0] ^ in[4];
        x[1] = in[1];
        x[2] = in[2] ^ in[1];
        x[3] = in[3];
        x[4] = in[4] ^ in[3];
        
        // ============================================================
        // STEP 2: Chi layer (non-linear)
        // ============================================================
        // Compute T[i] = (~x[i]) & x[(i+1) % 5]
        
        t[0] = (~x[0]) & x[1];  // T[0] = (~x[0]) & x[1]
        t[1] = (~x[1]) & x[2];  // T[1] = (~x[1]) & x[2]
        t[2] = (~x[2]) & x[3];  // T[2] = (~x[2]) & x[3]
        t[3] = (~x[3]) & x[4];  // T[3] = (~x[3]) & x[4]
        t[4] = (~x[4]) & x[0];  // T[4] = (~x[4]) & x[0]
        
        // Apply: x[i] ^= T[(i+1) % 5]
        x[0] = x[0] ^ t[1];  // x[0] ^= T[1]
        x[1] = x[1] ^ t[2];  // x[1] ^= T[2]
        x[2] = x[2] ^ t[3];  // x[2] ^= T[3]
        x[3] = x[3] ^ t[4];  // x[3] ^= T[4]
        x[4] = x[4] ^ t[0];  // x[4] ^= T[0]
        
        // ============================================================
        // STEP 3: Final XORs
        // ============================================================
        // CRITICAL: These must use ORIGINAL values before modification!
        // x[1] ^= x[0]
        // x[0] ^= x[4]  
        // x[3] ^= x[2]
        // x[2] = ~x[2]
        
        // Save originals for dependencies
        out[1] = x[1] ^ x[0];  // x[1] ^= x[0] (using current x[0])
        out[0] = x[0] ^ x[4];  // x[0] ^= x[4]
        out[3] = x[3] ^ x[2];  // x[3] ^= x[2] (using current x[2])
        out[2] = ~x[2];        // x[2] = ~x[2]
        out[4] = x[4];         // x[4] unchanged
    end

endmodule
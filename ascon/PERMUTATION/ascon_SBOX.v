module ASCON_SBOX (
    input  wire [4:0] in,
    output reg  [4:0] out
);
    reg [4:0] t;
    reg [4:0] x;
    always @(*) begin
        // S-box implementation - Chi layer
        // x0 ^= x4; x4 ^= x3; x2 ^= x1;
        // t0 = x0; t1 = x1; t2 = x2; t3 = x3; t4 = x4;
        // t0 = t0 ^ (~t1 & t2);
        // t1 = t1 ^ (~t2 & t3);
        // t2 = t2 ^ (~t3 & t4);
        // t3 = t3 ^ (~t4 & t0_orig);
        // t4 = t4 ^ (~t0_orig & t1_orig);
        // x1 ^= x0; x0 ^= x4; x3 ^= x2; x2 = ~x2;
        

        
        // Initial XORs
        x[4] = in[4] ^ in[0];  // x0 ^= x4
        x[0] = in[0] ^ in[1];  // x4 ^= x3
        x[2] = in[2] ^ in[3];  // x2 ^= x1
        x[3] = in[3];
        x[1] = in[1];
        
        // Non-linear layer (Chi)
        t[4] = x[4] ^ (~x[1] & x[2]);
        t[1] = x[1] ^ (~x[2] & x[0]);
        t[2] = x[2] ^ (~x[0] & x[3]);
        t[0] = x[0] ^ (~x[3] & in[4]); // Use original x0
        t[3] = x[3] ^ (~in[4] & in[3]); // Use original x0 and x1
        
        // Final XORs
        out[3] = t[1] ^ t[4];  // x1 ^= x0
        out[4] = t[4] ^ t[0];  // x0 ^= x4
        out[1] = t[0] ^ t[2];  // x3 ^= x2
        out[2] = ~t[2];        // x2 = ~x2
        out[0] = t[3];
    end

endmodule

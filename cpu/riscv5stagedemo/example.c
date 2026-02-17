// ============================================
// RISC-V CPU Functional Test
// ============================================

volatile int global_array[16];
volatile int result = 0;

// --------------------------------------------------
// Test ALU operations
// --------------------------------------------------
int test_alu(int a, int b) {
    int r = 0;

    r += a + b;        // ADD
    r += a - b;        // SUB
    r += a & b;        // AND
    r += a | b;        // OR
    r += a ^ b;        // XOR
    r += a << 2;       // SLL
    r += a >> 1;       // SRL (logical if unsigned)
    r += (a < b);      // SLT
    r += (a != b);     // compare

    return r;
}

// --------------------------------------------------
// Test Load / Store
// --------------------------------------------------
int test_memory() {
    for (int i = 0; i < 16; i++) {
        global_array[i] = i * 3;
    }

    int sum = 0;
    for (int i = 0; i < 16; i++) {
        sum += global_array[i];
    }

    return sum;
}

// --------------------------------------------------
// Test Branch
// --------------------------------------------------
int test_branch(int x) {
    int r = 0;

    if (x == 10) {
        r = 100;
    } else {
        r = 50;
    }

    if (x < 5) {
        r += 1;
    } else {
        r += 2;
    }

    return r;
}

// --------------------------------------------------
// Test Loop + Hazard
// --------------------------------------------------
int test_loop() {
    int acc = 0;

    for (int i = 0; i < 20; i++) {
        acc += i;       // RAW hazard
    }

    return acc;
}

// --------------------------------------------------
// Recursive Function (stack + jal/jalr)
// --------------------------------------------------
int factorial(int n) {
    if (n <= 1)
        return 1;

    return n * factorial(n - 1);
}

// --------------------------------------------------
// MAIN
// --------------------------------------------------
int main() {

    int a = 15;
    int b = 7;

    int alu_res   = test_alu(a, b);
    int mem_res   = test_memory();
    int br_res    = test_branch(10);
    int loop_res  = test_loop();
    int fact_res  = factorial(5);

    result = alu_res + mem_res + br_res + loop_res + fact_res;

    // Infinite loop để giữ CPU không chạy rác
    while (1);

    return 0;
}


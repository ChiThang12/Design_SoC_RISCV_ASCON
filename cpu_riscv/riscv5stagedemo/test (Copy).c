int main() {
    int a = 5;
    int b = 10;
    int c = 0;

    // Kiểm tra ALU
    c = a + b;       // add
    c = c - 3;       // sub
    c = c * 2;       // mul (nếu có M-extension)
    c = c / 3;       // div (nếu có M-extension)

    // Kiểm tra memory (store/load)
    int mem[4];
    mem[0] = c;
    mem[1] = a;
    mem[2] = b;
    mem[3] = mem[0] + mem[1] + mem[2];

    // Kiểm tra loop và branch
    int sum = 0;
    for (int i = 1; i <= 10; i++) {
        sum += i;
    }

    // Kiểm tra điều kiện (branch)
    if (sum > 50)
        c = sum - 50;
    else
        c = sum + 50;

    return c;  // giá trị này nằm ở x10 (a0)
}

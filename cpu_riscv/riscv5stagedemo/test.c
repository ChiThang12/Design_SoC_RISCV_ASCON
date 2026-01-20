volatile int a = 10;
volatile int b = 20;
volatile int c;

void _start() {
    c = a + b;
    while (1);   // loop để CPU không chạy lung tung
}


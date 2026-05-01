# Kế hoạch Thiết kế IO Path cho soc_hs.v

> Mục tiêu: Thiết kế các IO path để biến thiết kế `soc_top.v` hiện tại thành một chip silicon chuẩn hoàn thiện với tên gọi `soc_hs.v`.

## 1. Vấn đề của `soc_top.v` hiện tại
Hiện tại, các IO trong `soc_top.v` đang được tách ra để dễ mô phỏng mức RTL. Ví dụ điển hình nhất là GPIO:
```verilog
output wire [31:0] gpio_out,   // pad output data
output wire [31:0] gpio_oe,    // output enable (1=drive, 0=hi-Z)
input  wire [31:0] gpio_in,    // pad input data
```
Tương tự cho tín hiệu JTAG `tdo` và `tdo_en`. Một chip thực tế (silicon hoặc FPGA) sẽ dùng các pad 2 chiều (inout) và các bộ đệm 3 trạng thái (tri-state buffer) ở vòng ngoài cùng (Pad Ring).

## 2. Thiết kế IO cho `soc_hs.v`

File `soc_hs.v` sẽ đóng vai trò là "Pad Ring" wrapper, bọc lấy core logic (`soc_top`) và khởi tạo các cell vật lý (Physical IO Pads).

### 2.1. Cấu trúc Port của `soc_hs.v`
```verilog
module soc_hs (
    // ── Clock & Reset ──────────────────────────────
    input  wire clk_in,      // Hoặc XTAL_IN (dao động thạch anh)
    input  wire por_n,       // Power-On Reset pad
    input  wire ext_rst_n,   // External reset pad

    // ── UART ───────────────────────────────────────
    output wire uart_tx,
    input  wire uart_rx,

    // ── JTAG (Debug) ───────────────────────────────
    input  wire tck,
    input  wire tms,
    input  wire tdi,
    inout  wire tdo,         // Inout pad do dùng tri-state

    // ── SPI (Mở rộng cho ngoại vi) ─────────────────
    output wire spi_sck,
    output wire spi_mosi,
    input  wire spi_miso,
    output wire spi_cs_n,

    // ── GPIO ───────────────────────────────────────
    inout  wire [31:0] gpio  // Inout pad vật lý (Bi-directional)
);
```

### 2.2. Khởi tạo IO Pad Cells
Trong `soc_hs.v`, ta khởi tạo các cell IO tương ứng với thư viện công nghệ (Ví dụ: `IOBUF`, `IBUF`, `OBUFT`).

**Cho GPIO (Bi-directional):**
```verilog
wire [31:0] core_gpio_out;
wire [31:0] core_gpio_oe;
wire [31:0] core_gpio_in;

genvar i;
generate
    for (i = 0; i < 32; i = i + 1) begin : gen_gpio_pad
        // IOBUF logic: if (oe) pad = out else pad = Z; in = pad
        IOBUF u_iobuf (
            .IO (gpio[i]),        // Nối ra chân chip
            .I  (core_gpio_out[i]), // Tín hiệu từ core
            .O  (core_gpio_in[i]),  // Tín hiệu vào core
            .T  (~core_gpio_oe[i])  // Active-low output enable
        );
    end
endgenerate
```

**Cho JTAG TDO (Tri-state):**
```verilog
wire core_tdo;
wire core_tdo_en;

OBUFT u_tdo_pad (
    .O (tdo),
    .I (core_tdo),
    .T (~core_tdo_en) // Khi tdo_en = 1 -> enable output
);
```

### 2.3. Các chân phụ trợ (Strapping & Power)
- **Power Pads:** Thiết kế chip chuẩn cần thêm khai báo các chân VDD (Core), VDDIO (Pad), VSS. Ở mức Verilog, các chân này thường được implicit hoặc khai báo dạng `inout` nếu netlist yêu cầu.
- **Boot Strapping:** Có thể cấu hình GPIO[2:0] để lấy trạng thái lúc `por_n` vừa được thả ra (Boot Mode Selection).

## 3. Các bước thực hiện
1. Tạo file `soc_hs.v`.
2. Định nghĩa các port với kiểu `inout` cho các tín hiệu 2 chiều.
3. Instantiation các IO primitives (IOBUF, OBUFT).
4. Instantiate `soc_top` bên trong `soc_hs.v` và nối các wire tương ứng vào IO primitives.
5. Sửa testbench `run_soc_ascon.v` để simulate theo interface inout mới.

# Kịch Bản Demo H

## Mục tiêu

Demo phải cho thấy rõ 3 lớp:

1. `H3` là reference control-plane
2. `Dot C` là baseline payload datapath
3. `H` là streaming headline datapath

## Kịch bản

### Cảnh 1: Chốt baseline control-plane

- Mở `h3_results.md`
- Chỉ ra `test_dualcore_h3_context` PASS
- Chỉ ra `test_dualcore_h3_benchmark` PASS
- Nhấn mạnh H3 chỉ là reference

### Cảnh 2: Chốt baseline payload

- Mở `golden_data_H.md`
- Chỉ ra baseline payload:
  - `128B = 91 cyc, 1125.27 Mbps`
  - `256B = 159 cyc, 1288.05 Mbps`
  - `512B = 295 cyc, 1388.47 Mbps`
  - `1024B = 567 cyc, 1444.80 Mbps`
- Nhấn mạnh đây là mốc tham chiếu của Dot C

### Cảnh 3: Chốt streaming headline

- Mở `golden_data_H.md`
- Chỉ ra `peak accepted outstanding AR = 2`
- Chỉ ra `peak pending BRESP = 2`
- Chỉ ra performance mode `COH_CTRL=1`:
  - `128B = 95 cyc, 1077.89 Mbps`
  - `256B = 165 cyc, 1241.21 Mbps`
  - `512B = 357 cyc, 1147.34 Mbps`
  - `1024B = 629 cyc, 1302.38 Mbps`
- Nhấn mạnh headline đến từ `streaming DMA + overlap + selective coherence`

### Cảnh 4: Chốt output policy

- Chạy hoặc trích kết quả `run_output_cachehit.sh 128`
- `COH_CTRL=1`: `94 cyc`, `1089.36 Mbps`, giữ stale output contract
- `COH_CTRL=3`: `315 cyc`, `325.08 Mbps`, cho fresh output contract

### Cảnh 5: Kết luận

- H3 = control-plane baseline
- Dot C = payload baseline
- H = streaming headline
- Throughput headline đến từ overlap, không phải từ context banking

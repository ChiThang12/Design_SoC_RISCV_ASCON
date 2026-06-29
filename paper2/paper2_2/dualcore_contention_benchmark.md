# Benchmark Contention Dual-Core

- Sinh bởi `run_dualcore_contention_bench.sh`
- Trọng tâm: so sánh read miss của CPU1 được forward từ peer cache với trường hợp fallback refill từ memory khi ASCON DMA đang hoạt động

| Scenario | Cycles to PASS | Core0 DC Req | Core1 DC Req | Core1 Peer Snoop Reqs | Core1 Peer Snoop Hits | Core1 C2C Forwards | Core1 C2C Fill Cycles | Core0 Mem Refills | Core1 Mem Refills |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| forward-hit + DMA | 49957 | 4597 | 4728 | 24 | 10 | 10 | 40 | 59 | 32 |
| fallback-refill + DMA | 81320 | 7788 | 8101 | 2 | 2 | 2 | 8 | 82 | 6 |

Hướng dẫn diễn giải:
- `Core1 Peer Snoop Hits` và `Core1 C2C Forwards` là chỉ báo forwarding chính cho consumer hart.
- `Core0 Mem Refills` phản ánh áp lực writeback/refill bổ sung do setup fallback-eviction tạo ra.
- `Cycles to PASS` là mốc hoàn tất end-to-end do unified SoC TB báo cáo khi CPU và ASCON DMA hoạt động đồng thời.

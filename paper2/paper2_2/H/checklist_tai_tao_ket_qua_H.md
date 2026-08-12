# Checklist Tái Tạo Kết Quả H

Tài liệu này là checklist tái tạo theo kiểu `chạy gì`, `mong đợi gì`, `đối chiếu với golden nào`.

## 1. H3 reference control-plane

Chạy:

```bash
bash run_h_firmware_benchmarks.sh
bash run_dualcore_suite.sh
```

Xác nhận:

- `test_dualcore_h3_context` PASS
- `test_dualcore_h3_benchmark` PASS
- `test_dualcore_basic`, `test_dualcore_cache_sweep`, `test_dualcore_fence_flush`, `test_dualcore_peer_snoop` đều `PASS`
- `h3_results.md` ghi lại số liệu chính
- số liệu chính khớp `golden_data_H.md`
- log chi tiết nằm trong `/tmp/h_firmware_benchmarks/`

## 2. Baseline payload datapath

Chạy:

```bash
iverilog -g2012 -I. -DIMEM_INIT_FILE='"gnu_toolchain/tests/test_ascon_dma_fence_128b.hex"' -o /tmp/run_soc_fence_128b.out run_soc_fence_128b.v
vvp /tmp/run_soc_fence_128b.out
```

Xác nhận:

- PASS
- `fair write-complete cyc = 91`
- `M2 AR/AW = 2/2`
- `dma_start/done/error = 1/1/0`
- khớp mục baseline payload trong `golden_data_H.md`

## 3. Streaming headline datapath

Chạy:

```bash
COH_CTRL=1 bash run_output_cachehit.sh 128
COH_CTRL=3 bash run_output_cachehit.sh 128
```

Xác nhận:

- `COH_CTRL=1` giữ contract output stale/non-temporal như thiết kế
- `COH_CTRL=3` refresh output đúng policy
- hành vi policy khớp mục streaming payload trong `golden_data_H.md`

## 4. Streaming sweep

Chạy:

```bash
bash run_paper2_measurements.sh
```

Xác nhận:

- với `COH_CTRL=0`: `128B`, `256B`, `512B`, `1024B` đều có CSV line
- với `COH_CTRL=3`: `128B`, `256B`, `512B`, `1024B` đều có CSV line
- với `COH_CTRL=1`: `128B`, `256B`, `512B`, `1024B` đều có CSV line
- `COH_CTRL=1` và `COH_CTRL=3` của `run_output_cachehit.sh 128` đều PASS ở cuối script
- sweep table và output-cache-hit markers khớp `golden_data_H.md`

## 5. Overlap metrics

Chạy:

```bash
iverilog -g2012 -I. -o /tmp/tb_dma_overlap_metrics.out ascon/dma/tb/tb_dma_overlap_metrics.v
vvp /tmp/tb_dma_overlap_metrics.out
```

Xác nhận:

- `peak accepted outstanding AR = 2`
- `peak pending BRESP = 2`
- khớp mục overlap trong `golden_data_H.md`

## 6. Quy tắc kết luận PASS cho package H

- Một bài chỉ được coi là PASS khi vừa `PASS functional`, vừa khớp `golden marker` tương ứng.
- Không dùng mỗi `dma_done` để kết luận headline streaming là đúng.
- Với headline `H`, phải giữ được ít nhất một bằng chứng overlap và một bằng chứng coherence policy.

## 7. Bộ ba bằng chứng tối thiểu để trình bày

Nếu cần tái tạo nhanh cho phần demo hoặc tổng hợp, tối thiểu phải có:

1. `run_h_firmware_benchmarks.sh` hoặc command H3 tương đương cho H3 reference
2. `run_soc_fence_128b.v` cho baseline payload
3. `tb_dma_overlap_metrics.v` và `run_output_cachehit.sh 128` cho headline streaming

Chuỗi này là bộ tái tạo ngắn nhất vẫn giữ được đầy đủ ba lớp:

- reference control-plane
- baseline datapath
- headline streaming datapath

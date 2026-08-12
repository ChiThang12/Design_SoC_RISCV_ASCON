# H3 DMA-First RTL Implementation Plan and Task List

Ngay cap nhat: 2026-07-13

Tai lieu nay bien narrative H3/DMA-first thanh plan trien khai RTL thuc dung trong repo hien tai. Muc tieu la de ban co the:

- biet chinh xac can sua module nao
- biet test nao dung de khoa tung moc
- biet khi nao duoc xem la "RTL chay duoc"
- biet khi nao duoc xem la "paper-ready"

## 1. Hien trang repo

Repo da co san nhung khoi quan trong sau:

- H3 top-level/reference: `ascon_H3/ascon_top.v`
- H3 register bank/slave: `ascon_H3/interface/ascon_axi_slave.v`
- DMA engine RTL: `ascon/dma/rtl/ascon_dma.v`
- DMA control FSM: `ascon/dma/rtl/dma_ctrl_fsm.v`
- DMA unit testbench: `ascon/dma/tb/tb_ascon_dma.v`
- SoC dual-core testbench: `tb_soc/tb_soc_dualcore_suite.v`
- SoC top with baseline switch: `soc_top.v`
- Dual-core H3 firmware tests: `gnu_toolchain/tests_dualcore/*.c`
- DMA sweep firmware tests: `gnu_toolchain/tests/test_ascon_dma_*.c`
- Sweep scripts: `run_coherent_sweep.sh`, `run_output_cachehit.sh`, `run_paper2_measurements.sh`

Dieu quan trong:

- H3 control-plane da co proof kha tot.
- DMA path da ton tai o muc functional prototype.
- Viec can lam tiep khong phai "viet moi tu dau", ma la chot DMA-first RTL cho dung narrative paper va khoa lai bang simulation + firmware benchmark.

## 2. Dinh nghia muc tieu RTL

Can tach ro 2 muc tieu:

### Muc tieu A: RTL chay duoc

Dat muc nay khi:

- H3 context banking van PASS
- DMA payload path PASS
- DMA context latch PASS
- coherence mode co the chay duoc tren sweep 128B-1024B
- khong co deadlock, khong co overwrite sai burst

### Muc tieu B: RTL paper-ready

Dat muc nay khi:

- co bang benchmark payload sweep ro rang
- co so sanh fair voi H3 reference va no-CRF baseline
- co at least 1 smoke/negative test cho burst/coherency
- co table area/timing neu ban muon dua sang synthesis/OpenLane2

## 3. Scope RTL nen chot

De tranh mo qua rong, pham vi nen chot cho revision nay la:

- giu H3 lam reference control-plane
- giu 2 context banks
- giu `CONTEXT_SEL` va `context_id_active`
- giu DMA bulk transfer lam headline data-plane
- giu coherence mode `0/1/3` de benchmark
- giu payload sweep 128B, 256B, 512B, 1024B

Khong nen mo qua som neu chua can:

- hardware multi-queue scheduler cho nhieu DMA context song song
- 4-context hoac N-context banking
- reorder engine phuc tap
- out-of-order overlap read/write

## 4. Kien truc implementation nen theo

### Pha 1: Chot MVP DMA-first

Muc tieu:

- data path on dinh
- burst path dung
- benchmark duoc

Task:

- Chot register interface DMA dang dung:
  - `DMA_SRC_ADDR`
  - `DMA_DST_ADDR`
  - `DMA_LEN`
  - `DMA_BURST_LEN`
  - `DMA_COH_CTRL`
  - `AD_ADDR`
  - `AD_LEN`
  - `CONTEXT_SEL`
- Chot top active giua H3 va baseline trong `soc_top.v`
- Chot context latch cho `core_start` va `dma_start`
- Chot AD phase va payload phase trong `dma_ctrl_fsm`
- Chot writeback format ciphertext/tag
- Chot fairness metric: `DMA_START -> last M2_B`

Files chinh can theo doi:

- `ascon_H3/ascon_top.v`
- `ascon_H3/interface/ascon_axi_slave.v`
- `ascon/dma/rtl/ascon_dma.v`
- `ascon/dma/rtl/dma_ctrl_fsm.v`
- `ascon/dma/rtl/dma_read_engine.v`
- `ascon/dma/rtl/dma_write_engine.v`
- `soc_top.v`

Exit criteria:

- `tb_ascon_dma` PASS
- `test_ascon_dma_noad` PASS
- `test_ascon_dma_ad` PASS
- `test_dualcore_h3_dma_context_smoke` PASS

### Pha 2: Khoa H3 reference correctness

Muc tieu:

- giu H3 sach de lam reference control-plane

Task:

- Verify `CONTEXT_SEL` bank mux khong pha data cu
- Verify `active_context` latched khi busy
- Verify doi context sau `core_start` khong lam sai output
- Verify DMA start khi `CONTEXT_SEL=1` thi `context_id_active` khong bi doi boi firmware sau do

Firmware/test dung lai:

- `test_dualcore_h3_context.c`
- `test_dualcore_h3_benchmark.c`
- `test_dualcore_h3_busy_switch.c`
- `test_dualcore_h3_stress_switchback.c`
- `test_dualcore_h3_dma_context_smoke.c`

Exit criteria:

- tat ca 5 test tren PASS
- benchmark van giu duoc:
  - context select interval = 36 cycles
  - RTL select latency = 1 cycle

### Pha 3: Chot DMA-first benchmark path

Muc tieu:

- bien DMA thanh headline thong qua so lieu

Task:

- Chay payload sweep 128B, 256B, 512B, 1024B
- Chay coherence sweep:
  - `COH_CTRL=0`
  - `COH_CTRL=1`
  - `COH_CTRL=3`
- Log cac metric:
  - fair cycles
  - throughput Mbps
  - snoop read count
  - snoop invalidate count
  - AXI AR count
  - AXI AW count
  - peak WR FIFO

Scripts/test can dung:

- `run_coherent_sweep.sh`
- `run_output_cachehit.sh`
- `run_paper2_measurements.sh`
- `gnu_toolchain/tests/test_ascon_dma_coherent_nofence_sweep.c`
- `gnu_toolchain/tests/test_ascon_dma_output_cachehit.c`

Exit criteria:

- co bang CSV/log cho 4 payload
- co du lieu so sanh giua 3 mode coherent
- co the ket luan mode nao la sweet spot

## 5. Task list theo thu tu thuc hien

## Task Group A - RTL audit and cleanup

- [ ] A1. Chot module top dang dung cho H3: `ascon_H3/ascon_top.v`
- [ ] A2. Xac nhan `soc_top.v` dang instantiate dung top H3 hay top `ascon/`
- [ ] A3. Xac nhan khong con duong include/cu phan than gay nham lan giua `ascon/` va `ascon_H3/`
- [ ] A4. Chot register map firmware-visible cho revision nay
- [ ] A5. Chot convention output buffer: ciphertext truoc, tag sau

Definition of done:

- top duoc xac dinh ro rang
- khong con nham lane giua reference tree va active tree

## Task Group B - Context banking and control-plane lock

- [ ] B1. Review `CONTEXT_SEL` write/read path
- [ ] B2. Review banked registers: mode/key/nonce/ptext/ctext/tag/AD metadata
- [ ] B3. Review `reg_context_active` latch khi `core_start`/`dma_start`
- [ ] B4. Review `context_id_active` latch trong DMA FSM
- [ ] B5. Xac nhan status global khong bi bank hoa nham

Verification:

- [ ] B6. Run `test_dualcore_h3_context`
- [ ] B7. Run `test_dualcore_h3_busy_switch`
- [ ] B8. Run `test_dualcore_h3_stress_switchback`
- [ ] B9. Run `test_dualcore_h3_dma_context_smoke`

## Task Group C - DMA payload path

- [ ] C1. Review `dma_read_engine` burst issue logic
- [ ] C2. Review `dma_ctrl_fsm` block accounting cho payload
- [ ] C3. Review `dma_write_engine` beat packing cho ciphertext/tag
- [ ] C4. Review WR FIFO overflow/error path
- [ ] C5. Review AXI write response done/error sticky behavior

Verification:

- [ ] C6. Run `tb_ascon_dma`
- [ ] C7. Run `test_ascon_dma_noad`
- [ ] C8. Run `test_ascon_dma_coherent_nofence`
- [ ] C9. Run `test_ascon_dma_fence_128b`

## Task Group D - AD DMA path

- [ ] D1. Review AD phase in `dma_ctrl_fsm`
- [ ] D2. Review AD burst sizing against `RD_FIFO_DEPTH`
- [ ] D3. Review switch from AD phase sang payload phase
- [ ] D4. Review `core_ad_valid/core_ad_last/core_ad_ready`
- [ ] D5. Confirm `AD_ADDR/AD_LEN` firmware contract ro rang

Verification:

- [ ] D6. Run `test_ascon_dma_ad`
- [ ] D7. Run unit-level `tb_ascon_dma` voi AD case neu can them testcase

## Task Group E - Coherency path

- [ ] E1. Review `DMA_COH_CTRL` decode
- [ ] E2. Review read snoop enable path
- [ ] E3. Review write invalidate policy path
- [ ] E4. Confirm selective coherent (`COH_CTRL=1`) dung output contract mong muon
- [ ] E5. Confirm full coherent (`COH_CTRL=3`) dung correctness path

Verification:

- [ ] E6. Run `run_coherent_sweep.sh` voi `COH_CTRL=0`
- [ ] E7. Run `run_coherent_sweep.sh` voi `COH_CTRL=1`
- [ ] E8. Run `run_coherent_sweep.sh` voi `COH_CTRL=3`
- [ ] E9. Run `run_output_cachehit.sh 128` voi `COH_CTRL=1`
- [ ] E10. Run `run_output_cachehit.sh 128` voi `COH_CTRL=3`

## Task Group F - Firmware-visible benchmark path

- [ ] F1. Chot file benchmark H3 reference
- [ ] F2. Chot file benchmark DMA sweep
- [ ] F3. Xuat log CSV tu sweep scripts
- [ ] F4. Ghi lai metric fair cycles va throughput
- [ ] F5. Tinh bang so sanh voi H3 va no-CRF

Outputs:

- [ ] F6. Bang payload 128B-1024B
- [ ] F7. Bang coherence mode comparison
- [ ] F8. Bang H3 vs no-CRF vs DMA-first

## 6. Command checklist de trien khai

### Build firmware dual-core H3

```bash
cd '/home/chithang/Project/Design_SoC_RISCV_ASCON H3/gnu_toolchain'
./compile_c_to_hex.sh -i tests_dualcore/test_dualcore_h3_context.c -o tests_dualcore/test_dualcore_h3_context.hex -O 0
./compile_c_to_hex.sh -i tests_dualcore/test_dualcore_h3_benchmark.c -o tests_dualcore/test_dualcore_h3_benchmark.hex -O 0
./compile_c_to_hex.sh -i tests_dualcore/test_dualcore_h3_busy_switch.c -o tests_dualcore/test_dualcore_h3_busy_switch.hex -O 0
./compile_c_to_hex.sh -i tests_dualcore/test_dualcore_h3_stress_switchback.c -o tests_dualcore/test_dualcore_h3_stress_switchback.hex -O 0
./compile_c_to_hex.sh -i tests_dualcore/test_dualcore_h3_dma_context_smoke.c -o tests_dualcore/test_dualcore_h3_dma_context_smoke.hex -O 0
```

### Build firmware DMA path

```bash
cd '/home/chithang/Project/Design_SoC_RISCV_ASCON H3/gnu_toolchain'
./compile_c_to_hex.sh -i tests/test_ascon_dma_noad.c -o tests/test_ascon_dma_noad.hex -O 0
./compile_c_to_hex.sh -i tests/test_ascon_dma_ad.c -o tests/test_ascon_dma_ad.hex -O 0
./compile_c_to_hex.sh -i tests/test_ascon_dma_coherent_nofence.c -o tests/test_ascon_dma_coherent_nofence.hex -O 0
./compile_c_to_hex.sh -i tests/test_ascon_dma_fence_128b.c -o tests/test_ascon_dma_fence_128b.hex -O 0
```

### Run SoC-level H3 testbench

```bash
cd '/home/chithang/Project/Design_SoC_RISCV_ASCON H3'
iverilog -g2005 -I. \
  -DTEST_HEX='"gnu_toolchain/tests_dualcore/test_dualcore_h3_context.hex"' \
  -DSCENARIO_NAME='"test_dualcore_h3_context"' \
  -DEXPECT_SIG0="32'h3C000001" \
  -DEXPECT_SIG1="32'h3C000002" \
  -DHEARTBEAT_MIN=4 \
  -DDC_REQ_MIN=0 \
  -DAUX0_CHECK_ENABLE=1 \
  -DEXPECT_AUX0="32'h3C0A0000" \
  -DAUX1_CHECK_ENABLE=1 \
  -DEXPECT_AUX1="32'h00000000" \
  -DTIMEOUT_CYCLES=500000 \
  -o /tmp/test_dualcore_h3_context.out \
  tb_soc/tb_soc_dualcore_suite.v
vvp /tmp/test_dualcore_h3_context.out
```

### Run DMA sweep

```bash
cd '/home/chithang/Project/Design_SoC_RISCV_ASCON H3'
COH_CTRL=1 bash run_coherent_sweep.sh 128 256 512 1024
COH_CTRL=3 bash run_coherent_sweep.sh 128 256 512 1024
COH_CTRL=0 bash run_coherent_sweep.sh 128 256 512 1024
```

## 7. Verification matrix nen dung

| Level | Muc tieu | Test |
| --- | --- | --- |
| Unit | DMA read/write correctness | `ascon/dma/tb/tb_ascon_dma.v` |
| Block | Slave register decode + burst write/read | `ascon_H3/interface/tb/tb_ascon_axi_slave.v` |
| SoC functional | H3 context isolation | `test_dualcore_h3_context` |
| SoC negative | switch khi busy | `test_dualcore_h3_busy_switch` |
| SoC stress | switch-back nhieu vong | `test_dualcore_h3_stress_switchback` |
| SoC smoke | DMA context latch | `test_dualcore_h3_dma_context_smoke` |
| SoC throughput | H3 control benchmark | `test_dualcore_h3_benchmark` |
| SoC throughput | DMA bulk path | `run_coherent_sweep.sh` |
| SoC coherence | output cache contract | `run_output_cachehit.sh` |

## 8. Thu tu thuc thi de tranh roi

Thu tu lam nhanh nhat:

1. Chot active top/module tree
2. Chot H3 context latch va slave register map
3. Chot DMA payload path
4. Chot AD path
5. Chot coherency mode
6. Run H3 reference tests
7. Run DMA smoke tests
8. Run payload/coherency sweep
9. Tong hop bang so lieu cho paper

## 9. Definition of done cho tung moc

### Moc M1 - Functional RTL stable

Dat khi:

- `test_dualcore_h3_context` PASS
- `test_dualcore_h3_busy_switch` PASS
- `test_dualcore_h3_dma_context_smoke` PASS
- `test_ascon_dma_noad` PASS
- `test_ascon_dma_ad` PASS

### Moc M2 - Benchmarkable DMA-first

Dat khi:

- sweep 128B-1024B chay het
- log duoc fair cycles
- co throughput cho `COH_CTRL=0/1/3`

### Moc M3 - Paper-ready reference

Dat khi:

- H3 benchmark on dinh
- no-CRF baseline on dinh
- DMA-first sweep on dinh
- claim trong paper map duoc truc tiep vao test/log

## 10. Risk list can canh

- Nhap nhang giua `ascon/` va `ascon_H3/` la rui ro lon nhat.
- Comment trong RTL co cho van mang dau vet "Phase 1 single 64-bit block", trong khi benchmark da di xa hon; can doi chieu ky de tranh story va implementation lech nhau.
- Neu them tinh nang moi qua nhieu cung luc, rat de mat baseline sach.
- Coherency claim phai bam theo test da co, khong nen viet claim lon hon pham vi log do duoc.

## 11. De xuat cach lam trong 3 dot

### Dot 1 - Clean and lock

- Lam sach active tree
- Khoa H3 tests
- Khoa DMA smoke/unit tests

### Dot 2 - Benchmark path

- Chay payload sweep
- Chay coherence sweep
- Ghi bang so lieu

### Dot 3 - Paper closure

- Chot results table
- Chot benchmark note
- Chot claim va limitations

## 12. Ket luan

RTL cho H3/DMA-first khong o muc "bat dau tu con so 0". Repo da co rat nhieu khoi dung duoc. Viec quan trong bay gio la trien khai theo huong:

- giu H3 lam reference control-plane
- khoa DMA bulk path thanh headline data-plane
- dung firmware + testbench hien co de chung minh tung claim

Neu bam theo task list nay, ban se co mot lo trinh ro rang tu:

- sua RTL
- chay simulation
- benchmark bang firmware
- gom so lieu de viet paper

# Dot C - Baseline Payload Datapath

## 1. Muc tieu cua Dot C

Dot C khoa phan baseline payload datapath cua nhanh `H`:

- CPU chi setup va kick
- DMA la bo di chuyen du lieu chinh
- duong du lieu chay theo memory -> DMA -> ASCON -> DMA -> memory
- payload lon hon phai cho thay throughput tot hon nho amortize overhead

Tai lieu nay van co gia tri, nhung tu nay khong con dong vai tro kien truc dich cuoi cua nhanh `H`.

O nhanh `H` hien tai:

- `H3` chi la reference control-plane
- `Dot C` chi la baseline payload datapath
- `streaming DMA pipeline` moi la implementation headline moi

## 2. Pham vi duoc khoa

Dot C chot cac khoi RTL sau lam payload datapath tham chieu:

- `ascon/dma/rtl/ascon_dma.v`
- `ascon/dma/rtl/dma_ctrl_fsm.v`
- `ascon/dma/rtl/dma_read_engine.v`
- `ascon/dma/rtl/dma_write_engine.v`

Pham vi test va benchmark cua Dot C:

- payload `128B`, `256B`, `512B`, `1024B`
- read burst tu memory/cache vao DMA
- feed payload vao ASCON
- write burst ciphertext/tag ve memory
- log `fair cycles`, `done cycles`, `throughput`, `M2_AR`, `M2_AW`

## 3. Ket luan trien khai hien tai

Tai thoi diem khoa Dot C, duong payload DMA da du manh de dung lam baseline tham chieu cho nhanh `H`.

Y nghia ky thuat:

- payload khong con di theo MMIO word-by-word
- CPU khong con la data mover chinh
- datapath burst-based da hoat dong den muc co the do throughput

Y nghia trinh bay:

- day la moc payload tham chieu can duoc giu lai
- H3 duoc giu rieng o nhom control-plane baseline

## 4. Bang chung da co

### 4.1 Unit regression

Da chay:

```bash
iverilog -g2012 -I. -o /tmp/tb_ascon_dma_dotc.out ascon/dma/tb/tb_ascon_dma.v
vvp /tmp/tb_ascon_dma_dotc.out
```

Ket qua:

- `66 PASS / 0 FAIL`

Y nghia:

- DMA read/write path, error path, ATU/snoop hooks va FIFO behavior van dung

### 4.2 SoC fair control 128B

Da chay:

```bash
iverilog -g2012 -I. -DIMEM_INIT_FILE='"gnu_toolchain/tests/test_ascon_dma_fence_128b.hex"' -o /tmp/run_soc_fence_128b_dotc.out run_soc_fence_128b.v
vvp /tmp/run_soc_fence_128b_dotc.out
```

Ket qua:

- `PASS`
- `fair write-complete cyc = 91`
- `M2 AR/AW = 2/2`
- `dma_start/done/error = 1/1/0`

Y nghia:

- payload path software-fenced baseline 128B da chay tron ven o muc SoC

### 4.3 Payload sweep cua nhanh H

Bang nay tong hop so lieu payload sweep da co san trong repo va phu hop voi pham vi Dot C.

| Payload | Path / Mode | Fair cycles | Throughput fair | M2 AR | M2 AW | Ghi chu |
| ---: | --- | ---: | ---: | ---: | ---: | --- |
| 128B | Software-fenced baseline `COH_CTRL=0` | 91 | 1125.27 Mbps | 2 | 2 | control de so sanh truc tiep voi payload path cu |
| 256B | Software-fenced baseline `COH_CTRL=0` | 159 | 1288.05 Mbps | 4 | 3 | throughput tang khi payload lon hon |
| 512B | Software-fenced baseline `COH_CTRL=0` | 295 | 1388.47 Mbps | 8 | 5 | burst path bat dau amortize overhead rat ro |
| 1024B | Software-fenced baseline `COH_CTRL=0` | 567 | 1444.80 Mbps | 16 | 9 | moc payload cao nhat hien co trong sweep |
| 128B | Selective coherent `COH_CTRL=1` | 92 | 1113.04 Mbps | 0 | 2 | read snoop no-fence, output non-temporal |
| 256B | Selective coherent `COH_CTRL=1` | 160 | 1280.00 Mbps | 0 | 3 | gan baseline, van giu read coherence |
| 512B | Selective coherent `COH_CTRL=1` | 312 | 1312.82 Mbps | 6 | 5 | payload lon van giu duoc datapath tham chieu |
| 1024B | Selective coherent `COH_CTRL=1` | 584 | 1402.74 Mbps | 6 | 9 | throughput cao nhat cua no-fence path hien tai |

Nhan xet can khoa:

- throughput tang theo payload tren ca baseline va coherent path hien tai
- DMA payload path da dat muc benchmark duoc, khong chi dung o smoke test
- overhead start, tag writeback va handshake duoc amortize ro hon khi payload tang

## 5. Dot C co can sua RTL khong

Ket luan cho Dot C la:

- khong can mo them mot dot sua RTL lon de "lam cho payload chay duoc"
- payload RTL hien tai da du bang chung de khoa baseline data-plane

Viec can lam tiep theo sau Dot C la tai cau truc len streaming datapath moi:

- tai cau truc control
- dua ping-pong buffering vao
- khoa direction-aware coherence
- sau do moi dua AD vao tren nen moi

Neu can sua RTL o giai doan sau, sua doi voi muc tieu ro rang:

- bo sung hook do dac
- sua bug neu gap o payload lon hoac mode coherence cu the
- khong coi payload phase-based hien tai la implementation headline cuoi cung

## 6. Definition of done cua Dot C

Dot C duoc xem la dat muc "khoa" khi:

- unit DMA regression pass
- SoC payload control pass
- payload sweep `128B-1024B` da co bang so lieu de dua vao benchmark
- co the mo ta ro `memory -> DMA -> ASCON -> DMA -> memory`

Trang thai hien tai:

- `Dat`

## 7. Cach trich Dot C vao paper/cuoc thi

Neu can viet ngan gon trong phan implementation:

> Dot C cung cap baseline payload datapath de so sanh, trong do CPU chi cau hinh descriptor va kick transfer, con luong du lieu chinh duoc dua theo burst tu memory vao ASCON va ghi tra ket qua ve memory.

Neu can viet ngan gon trong phan benchmark:

- tach bang `H3 control-plane baseline`
- tach bang `baseline payload sweep`
- tach bang `streaming headline benchmark`
- khong tron metric context switch vao bang throughput payload

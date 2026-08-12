# FreeRTOS Bring-Up Checklist for SoC

Ngay cap nhat: 2026-08-03

Muc tieu gan:

- giu he thong chay on dinh o 100 MHz tren FPGA
- dua CPU + SoC ve trang thai FreeRTOS-ready
- uu tien single-core bring-up truoc
- chua dat dual-core coherent + ASCON vao moc FreeRTOS dau tien

Muc tieu sau:

- co FreeRTOS tick chay on dinh
- co context switch co ban
- co 2-3 task chay tren FPGA
- sau do moi quay lai toi uu timing va tan so cao hon

---

## 0. Nguyen tac scope

- [x] Khong mo rong scope sang dual-core scheduler o moc dau
- [x] Khong bat buoc ASCON DMA vao moc FreeRTOS dau tien
- [x] Giu target FPGA hien tai la 100 MHz stable
- [x] Chi nang target len 150/200 MHz sau khi FreeRTOS basic da chay

Tieu chi xong:

- co mot moc "single-core + CLINT + UART + FreeRTOS task switch" chay that tren FPGA

---

## 1. Dong bug nen tang truoc khi port RTOS

### P0 - Bat buoc

- [x] Dong `BUG-C4-GPIO-CRASH`
- [x] Dong `BUG-C5-RAW`
- [x] Xac minh lai `mtvec -> trap -> mret` khong con fail ngau nhien
- [x] Xac minh interrupt khong lam hong stack pointer hoac register frame
- [x] Xac minh du lieu sau ISR khong bi stale o DCache

Trang thai 2026-08-03:

- `test_timer`, `test_gpio`, `test_clint`, `test_plic` PASS trong regression P0.
- CPU trap/IRQ da duoc siết ve one-cycle precise trap flush; khong con thay stack corruption trong timer ISR.
- `test_plic` da fix protocol cho ASCON level IRQ: claim trong ISR, ha ASCON IRQ_EN, delayed-complete sau khi global IRQ off.
- Script dong P0: `soc_os/run_phase1_p0.sh`, co the chay lap bang `LOOPS=5 soc_os/run_phase1_p0.sh`.
- P0 gate moi dung fast simulation UART va `FINISH_ON_PASS` de tranh timeout gia sau khi firmware da in `[PASS]`.
- Ket qua gan nhat: `LOOPS=1 bash soc_os/run_phase1_p0.sh` PASS 4/4, FAIL 0, TIMEOUT 0.

Tieu chi xong:

- test lien quan interrupt/trap/cache PASS on dinh qua nhieu lan chay

Ghi chu:

- hai bug nay la blocker truc tiep cho scheduler va tick ISR

---

## 2. Chot cau hinh SoC cho moc FreeRTOS dau tien

### P0 - Bat buoc

- [x] Chot mode `single-core`
- [x] Chot map bo nho IMEM/DMEM cho RTOS
- [x] Chot `CLINT` la nguon tick timer
- [x] Chot `PLIC` cho external interrupt neu can
- [x] Chot `UART` la kenh log chinh
- [x] Chot trap mode la machine mode

### P1 - Nen co

- [x] Ghi ro cau hinh moc 1 trong mot file note rieng
- [x] Ghi ro peripheral nao tam thoi khong dua vao bring-up

Note cau hinh:

- Firmware load contract: `soc_os/firmware_load_contract.md`.
- FreeRTOS moc 1: single-core, machine mode, CLINT tick, UART log, optional PLIC external IRQ.

Tieu chi xong:

- co mot profile cau hinh FreeRTOS-first ro rang, khong bi doi scope lien tuc

---

## 3. Tao bo test pre-RTOS tren bare-metal

### P0 - Bat buoc

- [ ] `test_trap_basic`
- [ ] `test_mret_return`
- [x] `test_clint_periodic_tick`
- [x] `test_uart_log_stability`
- [x] `test_irq_stress_basic`

### P1 - Rat nen co

- [ ] `test_context_frame_save_restore`
- [x] `test_plic_external_irq`
- [ ] `test_wfi_wakeup`

Tieu chi xong:

- cac test pre-RTOS PASS tren simulation
- cac test quan trong PASS tren FPGA o 100 MHz

Goi y output can log:

- so tick da nhan
- so lan vao ISR
- mepc/mcause trong trap
- pass marker cuoi cung

---

## 4. Kiem tra contract CPU cho FreeRTOS

### CSR / trap / interrupt

- [x] `mstatus` hoat dong dung
- [x] `mie` hoat dong dung
- [x] `mtvec` nhay dung trap entry
- [x] `mepc` duoc luu/restore dung
- [x] `mcause` phan loai dung timer/software/external IRQ
- [x] `mret` return dung ve instruction tiep theo

### Pipeline / memory behavior

- [x] Khong mat interrupt khi pipeline dang busy
- [x] Khong double-retire quanh trap/return
- [x] LSU/DCache khong gay stale read sau interrupt
- [x] Stack load/store trong ISR on dinh

### Optional nhung tot cho RTOS

- [ ] `WFI` wake dung bang timer IRQ
- [ ] co perf counter/log co ban de debug stall va retire

Tieu chi xong:

- CPU du minimum machine-mode contract de port FreeRTOS

---

## 5. Chuan bi FreeRTOS port

### P0 - Bat buoc

- [x] Tao thu muc port hoac note ro vi tri port FreeRTOS trong `soc_os`
- [x] Chot startup code cho FreeRTOS
- [x] Chot trap handler chung cho RTOS
- [x] Chot tick source = CLINT
- [x] Chot cach disable/enable interrupt bang CSR
- [x] Chot layout stack cho task

Trang thai Phase 2:

- [x] `gnu_toolchain/test_os/test_minirtos_tick.c` PASS voi periodic ping-pong.
- [x] Trap path `mtvec -> save context -> tick -> restore context -> mret` PASS.
- [x] `task0_count` va `task1_count` deu tang sau CLINT tick.
- [x] Runner: `soc_os/run_phase2_minirtos.sh`.
- [x] Stability: PASS tren simulation; regression gan nhat `bash soc_os/run_phase2_minirtos.sh` PASS.

### P1 - Nen co

- [x] Chot linker script danh cho FreeRTOS
- [x] Chot heap scheme don gian
- [x] Chot `configCPU_CLOCK_HZ`
- [x] Chot `configTICK_RATE_HZ`

Tieu chi xong:

- co skeleton software de bat dau port ma khong phai quay lai doi hardware interface

---

## 6. Port FreeRTOS toi thieu

### P0 - Bat buoc

- [x] Viet trap entry/save context
- [x] Viet restore context + `mret`
- [x] Viet tick ISR tu CLINT
- [x] Viet ham yield/context switch co ban
- [x] Khoi tao task dau tien
- [x] Chay duoc 2 task co ban

### Muc demo toi thieu

- [x] Task A counter
- [x] Task B counter
- [x] Scheduler van chay on dinh trong smoke simulation

Tieu chi xong:

- FreeRTOS-port smoke boot thanh cong
- scheduler chuyen task dung
- UART log xac nhan `[PASS] freertos_smoke`

Trang thai Phase 3:

- [x] Tao `soc_os/freertos_port/FreeRTOSConfig.h`
- [x] Tao `soc_os/freertos_port/linker_freertos.ld`
- [x] Tao `soc_os/freertos_port/portASM.S` staging note
- [x] Tao `gnu_toolchain/test_os/test_freertos_smoke.c`
- [x] Tao runner `soc_os/run_phase3_freertos_smoke.sh`
- [x] Import upstream FreeRTOS kernel va link multi-object that

Trang thai Phase 4:

- [x] Tao `gnu_toolchain/test_os/test_freertos_kernel_smoke.c`
- [x] Tao runner `soc_os/run_phase4_freertos_kernel_smoke.sh`
- [x] Link kernel objects that: `tasks.c`, `list.c`, `queue.c`
- [x] `taskYIELD()` di qua `ecall -> mtvec -> trap -> vTaskSwitchContext -> mret`
- [x] CLINT tick ISR van chay cung FreeRTOS kernel.
- [x] Hai task FreeRTOS cung priority deu tang counter.
- [x] UART log xac nhan `[PASS] freertos_kernel_smoke`
- [x] Stability: 3/3 run PASS tren simulation.
- [x] Regression gan nhat ngay 2026-08-03: Phase 2 PASS, Phase 3 PASS, Phase 4 PASS.

Ghi chu Phase 4:

- Bug cuoi da dong: CPU truoc do chua trap `ecall`, lam `taskYIELD()` return thang ve task hien tai.
- Fix RTL: them synchronous ECALL trap voi `mcause=11`, `mepc=pc_ex`, redirect `mtvec`, flush precise.
- Phase 4 dong o simulation. Moc chua dong: FPGA bring-up that.

---

## 7. Bring-up tren FPGA

### P0 - Bat buoc

- [ ] Build bitstream 100 MHz on dinh
- [ ] Nap firmware bare-metal pre-RTOS len FPGA
- [ ] PASS lai cac test trap/timer/uart tren board
- [ ] Nap firmware FreeRTOS bring-up len FPGA
- [ ] Xac minh boot, tick, task switch tren hardware that

### P1 - Nen co

- [ ] script nap firmware/bitstream gon lai
- [ ] checklist debug khi board treo
- [ ] log UART tham chieu cho tung moc

Tieu chi xong:

- FreeRTOS demo chay that tren FPGA, khong chi PASS o sim

---

## 8. Timing va toi uu sau khi RTOS da chay

### P1 - Lam sau moc FreeRTOS dau tien

- [ ] Lay timing report post-synth
- [ ] Lay timing report post-impl
- [ ] Xac dinh critical path top 10
- [ ] Tach xem bottleneck nam o CPU, cache hay crossbar
- [ ] Thu muc tieu 125 MHz
- [ ] Thu muc tieu 150 MHz
- [ ] Neu kha thi moi thu 200 MHz

Tieu chi xong:

- co du lieu timing that, khong doan cam tinh

Ghi chu:

- 200 MHz la muc stretch goal, khong nen block moc FreeRTOS

---

## 9. Bang tien do de danh dau

### Tuan 1

- [x] Dong bug P0 lien quan interrupt/cache
- [x] PASS bo test pre-RTOS tren sim
- [ ] PASS test trap/timer co ban tren FPGA

### Tuan 2

- [x] Chot single-core FreeRTOS profile
- [x] Hoan thanh skeleton port
- [x] Tick ISR chay duoc

### Tuan 3

- [x] Context switch chay duoc
- [x] 2 task co ban chay duoc
- [ ] UART log on dinh tren FPGA

### Tuan 4

- [ ] Demo FreeRTOS tren FPGA
- [ ] Don dep script/build/doc
- [ ] Neu con thoi gian thi moi bat dau timing push len cao hon

---

## 10. Definition of Done

- [ ] Single-core SoC chay FreeRTOS tren FPGA that
- [x] Tick timer on dinh trong simulation
- [x] Context switch dung trong simulation
- [x] UART log duoc PASS FreeRTOS kernel smoke trong simulation
- [x] Bug interrupt/cache/ECALL blocker da dong trong simulation
- [x] Co tai lieu va checklist cap nhat theo tien do

## 11. Khong lam trong moc dau neu khong that su can

- [ ] Khong dua dual-core SMP vao FreeRTOS moc 1
- [ ] Khong dua ASCON DMA vao task demo moc 1
- [ ] Khong theo 200 MHz truoc khi RTOS chay on dinh
- [ ] Khong mo rong sang benchmark lon khi bring-up con chua xong

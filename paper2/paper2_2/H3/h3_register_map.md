# H3 Register Map Delta for Reference Design

H3 giữ nguyên register map ASCON hiện có và thêm một thanh ghi context select. Trong narrative DMA-first, phần này là reference control plane để so sánh với kiến trúc mới.

| Offset | Name | Width | Description |
| ---: | --- | ---: | --- |
| `0x008` | `CONTEXT_SEL` | 1 bit | Chọn context bank đang active. Giá trị hợp lệ hiện tại: `0` hoặc `1`. |

## Cach dùng firmware

```c
ascon_select_context(0u);
ascon_set_key(...);
ascon_set_nonce(...);
ascon_set_ptext(...);
ascon_core_start();
ascon_wait_core_done();

ascon_select_context(1u);
ascon_set_key(...);
ascon_set_nonce(...);
ascon_set_ptext(...);
ascon_core_start();
ascon_wait_core_done();

ascon_select_context(0u);
ascon_get_ctext(&ct0, &ct1);
```

## Thanh ghi được bank theo context

- `MODE`
- `DATA_LEN`
- `KEY_0..KEY_3`
- `NONCE_0..NONCE_3`
- `PTEXT_0..PTEXT_1`
- `CTEXT_0..CTEXT_1`
- `TAG_0..TAG_3`
- `TAG_IN_0..TAG_IN_3`
- `AD_ADDR`
- `AD_LEN`
- `AD_DATA_0..AD_DATA_1`

## Thanh ghi không bank

- `STATUS`
- `CTRL`
- DMA address/length/control registers
- `IRQ_*`
- Identification/version registers

Lý do: các thanh ghi trên là trạng thái điều khiển global của accelerator/DMA. H3 hiện tại chứng minh multi-context cho core-facing ASCON state; DMA multi-tenant scheduling sau này có thể mở rộng bằng context queue riêng nếu cần.

## Hướng register map cho DMA-first revision

Nếu paper mới muốn làm đúng tinh thần `DMA-enabled pipelined ASCON engine`, register map nên mở thêm nhóm DMA-facing control như:

- `DMA_SRC_ADDR`
- `DMA_DST_ADDR`
- `DMA_LEN`
- `DMA_BURST_LEN`
- `DMA_STRIDE`
- `DMA_PREFETCH_DEPTH`
- `DMA_WATERMARK`
- `DMA_STATUS`

Nhóm này sẽ giúp DMA trở thành data mover thật sự, thay vì chỉ sideband cho context selection.

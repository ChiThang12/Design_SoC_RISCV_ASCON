# H3 Register Map Delta

H3 giữ nguyên register map ASCON hiện có và thêm một thanh ghi context select.

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


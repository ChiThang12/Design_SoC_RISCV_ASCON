# dcache_ascon

Thu muc nay la nhanh lam viec rieng cho H1 Compute-in-Cache.

Nguon ban dau duoc copy tu `cache_interface/dcache` de:

- giu baseline DCache/MESI dang dung cho H3 va regression hien tai
- cho phep sua kien truc H1 ma khong lam vo nhanh on dinh
- tao cho ro rang de them metadata/queue/datapath ASCON trong cache

## Trang thai hien tai

- Da copy day du cac file DCache chinh va testbench lien quan
- Da sua include noi bo de tham chieu sang `cache_interface/dcache_ascon`
- Chua duoc integrate vao `soc_top.v`
- Chua co logic H1 moi; day la baseline de bat dau sua

## File se la diem vao chinh cho H1

- `dcache_tag_array.v`
- `dcache_controller.v`
- `dcache_top.v`
- co the them moi:
  - `dcache_crypto_meta.v`
  - `dcache_crypto_queue.v`
  - `dcache_ascon_datapath.v`

## Nguyen tac lam viec

- Khong sua truc tiep nhanh `cache_interface/dcache` neu muc tieu la H1 prototype
- Moi thay doi H1 nen di vao `dcache_ascon` tru khi da xac nhan can merge nguoc vao baseline
- Khi H1 on dinh moi can nhac noi `dcache_ascon` vao `soc_top.v`/build flow


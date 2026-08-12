../src/IFU.v
../src/reg_file.v
../src/imm_gen.v
../src/control.v
../src/alu.v
../src/riscv_multiplier.v
../src/branch_logic.v
../src/forwarding_unit.v
../src/hazard_detection.v
../src/PIPELINE_REG_IF_ID.v
../src/PIPELINE_REG_ID_EX.v
../src/PIPELINE_REG_EX_MEM.v
../src/PIPELINE_REG_MEM_WB.v
../src/LSU.v
../src/riscv_cpu_core_v2.v

../src/icache_tag_array.v
../src/icache_data_array.v
../src/icache_axi_interface.v
../src/icache_controller.v
../src/icache_top.v

../src/dcache_tag_array.v
../src/dcache_data_array.v
../src/dcache_axi_interface.v
../src/dcache_next_state.v
../src/dcache_cpu_response.v
../src/dcache_flush_ctrl.v
../src/dcache_snoop_ctrl.v
../src/dcache_controller.v
../src/dcache_top.v
../src/dcache_snoop_bus_2way.v
../src/dcache_snoop_arb_3to1.v

../src/inst_mem.v
../src/inst_mem_axi_slave.v
../src/data_mem_burst.v
../src/data_mem_axi_slave.v

../src/axi4_addr_decoder.v
../src/axi4_master_mux_5m.v
../src/axi4_decerr_slave.v
../src/axi4_crossbar_5m12s.v
../src/axi4_master_mux_2m.v
../src/axi_width_converter_64to32.v

../src/ascon_INITIALIZATION.v
../src/ascon_STATE_REGISTER.v
../src/ascon_ROUND_COMB.v
../src/ascon_PERMUTATION.v
../src/ascon_datapath.v
../src/ascon_TAG_GENERATOR.v
../src/ascon_TAG_COMPARATOR.v
../src/ascon_CONTROLLER.v
../src/ascon_CORE.v
../src/ascon_axi_slave.v
../src/ascon_watchdog.v
../src/sync_fifo.v
../src/dma_read_engine.v
../src/dma_write_engine.v
../src/dma_ctrl_fsm.v
../src/dma_atu.v
../src/dma_snoop_arb.v
../src/dma_err_latch.v
../src/ascon_dma.v
../src/ascon_top.v

../src/soc_ctrl_slave.v
../src/clint.v
../src/reset_sync.v
../src/por_stretcher.v
../src/soft_rst_sync.v
../src/clk_buf.v
../src/clk_reset_ctrl.v

../src/uart_axi_slave.v
../src/uart_baud_gen.v
../src/uart_fifo.v
../src/uart_tx.v
../src/uart_rx.v
../src/uart_irq_gen.v
../src/uart_top.v
../src/axis_uart_bridge.v

../src/plic_regfile.v
../src/plic_gateway.v
../src/plic_priority_encoder.v
../src/plic_top.v

../src/jtag_tap.v
../src/jtag_dtm.v
../src/riscv_dm.v
../src/jtag_debug_top.v

../src/dma_reg_slave.v
../src/dma_channel.v
../src/dma_arbiter.v
../src/dma_axi_master.v
../src/dma_ctrl.v

../src/uart_boot_ctrl.v

../src/gpio_regfile.v
../src/gpio_iocell.v
../src/gpio_top.v

../src/timer_regfile.v
../src/timer_channel.v
../src/wdt_core.v
../src/timer_top.v

../src/otp_stub_slave.v
../src/spi_axi_slave.v
../src/spi_core.v
../src/spi_top.v

../src/soc_top.v
../src/soc_hs.v
../src/fpga_top.v
../src/pynqz2_notebook_uart_top.v

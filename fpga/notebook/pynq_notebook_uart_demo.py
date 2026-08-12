from pathlib import Path
import time

from pynq import Overlay, allocate


BITSTREAM = "soc_rvas_notebook_uart.bit"
FIRMWARE_BIN = "test_freertos_kernel_smoke.bin"
DMA_NAME = "axi_dma_0"


class NotebookUartBridge:
    def __init__(self, bitstream=BITSTREAM, dma_name=DMA_NAME):
        self.overlay = Overlay(bitstream)
        self.dma = getattr(self.overlay, dma_name)

    def send_bytes(self, data: bytes):
        if not data:
            return
        tx_buf = allocate(shape=(len(data),), dtype="u1")
        tx_buf[:] = list(data)
        tx_buf.flush()
        self.dma.sendchannel.transfer(tx_buf)
        self.dma.sendchannel.wait()
        tx_buf.freebuffer()

    def send_line(self, text: str):
        if not text.endswith("\n"):
            text += "\n"
        self.send_bytes(text.encode("ascii"))

    def read_packet(self, max_len=256, timeout_s=0.5) -> bytes:
        rx_buf = allocate(shape=(max_len,), dtype="u1")
        self.dma.recvchannel.transfer(rx_buf)

        deadline = time.time() + timeout_s
        while time.time() < deadline:
            if self.dma.recvchannel.idle:
                rx_buf.invalidate()
                data = bytes(rx_buf)
                rx_buf.freebuffer()
                return data.rstrip(b"\x00")
            time.sleep(0.001)

        self.dma.recvchannel.stop()
        rx_buf.freebuffer()
        return b""

    def read_some(self, packets=64, timeout_s=0.05) -> bytes:
        chunks = []
        for _ in range(packets):
            data = self.read_packet(max_len=1, timeout_s=timeout_s)
            if not data:
                break
            chunks.append(data)
        return b"".join(chunks)

    def monitor(self, seconds=5.0):
        end_time = time.time() + seconds
        while time.time() < end_time:
            data = self.read_some()
            if data:
                print(data.decode("ascii", errors="replace"), end="", flush=True)
            else:
                time.sleep(0.02)

    def boot(self, firmware_path=FIRMWARE_BIN, chunk_size=256, settle_s=0.2):
        fw = Path(firmware_path).read_bytes()
        for offset in range(0, len(fw), chunk_size):
            self.send_bytes(fw[offset:offset + chunk_size])
        time.sleep(settle_s)


def demo():
    bridge = NotebookUartBridge()

    print("[HOST] booting SoC over notebook UART bridge...")
    bridge.boot(FIRMWARE_BIN)

    print("[HOST] monitoring boot log...")
    bridge.monitor(seconds=3.0)

    print("\n[HOST] sending terminal-style commands...")
    bridge.send_line("status")
    bridge.send_line("monitor on")
    bridge.send_line("read 0x50000000")

    print("[HOST] monitoring command responses...")
    bridge.monitor(seconds=5.0)


if __name__ == "__main__":
    demo()

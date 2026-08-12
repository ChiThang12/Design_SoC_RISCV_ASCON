from collections import deque
from pathlib import Path
import time

from pynq import Overlay, allocate

try:
    from IPython.display import clear_output
except Exception:  # pragma: no cover - optional notebook UX
    clear_output = None


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

    def watch_dashboard(self, seconds=5.0, refresh_s=0.12):
        dashboard = FreeRtosDashboard()
        end_time = time.time() + seconds
        line_buffer = ""
        dirty = False
        last_render = 0.0

        while time.time() < end_time:
            data = self.read_some()
            if data:
                line_buffer += data.decode("ascii", errors="replace")

                while "\n" in line_buffer:
                    raw_line, line_buffer = line_buffer.split("\n", 1)
                    line = raw_line.rstrip("\r")
                    if not line:
                        continue

                    if line.startswith("[TEL]"):
                        dirty = dashboard.ingest_line(line) or dirty
                    else:
                        print(line, flush=True)
                        dirty = dashboard.ingest_line(line) or dirty
            else:
                time.sleep(0.02)

            now = time.time()
            if dirty and (now - last_render >= refresh_s):
                dashboard.render()
                last_render = now
                dirty = False

        if line_buffer.strip():
            tail = line_buffer.rstrip("\r")
            if tail.startswith("[TEL]"):
                dirty = dashboard.ingest_line(tail) or dirty
            else:
                print(tail, end="", flush=True)
                dirty = dashboard.ingest_line(tail) or dirty

        if dirty:
            dashboard.render()

    def boot(self, firmware_path=FIRMWARE_BIN, chunk_size=256, settle_s=0.2):
        fw = Path(firmware_path).read_bytes()
        for offset in range(0, len(fw), chunk_size):
            self.send_bytes(fw[offset:offset + chunk_size])
        time.sleep(settle_s)


class FreeRtosDashboard:
    def __init__(self):
        self.reset()

    def reset(self):
        self.boot_seen = False
        self.scheduler_started = False
        self.pass_seen = False
        self.fail_seen = False
        self.last_task = "-"
        self.last_tick = 0
        self.last_beat = 0
        self.task_a = 0
        self.task_b = 0
        self.recent = deque(maxlen=6)

    @staticmethod
    def _coerce_value(text: str):
        try:
            if text.startswith("0x") or text.startswith("0X"):
                return int(text, 16)
            return int(text)
        except ValueError:
            return text

    def _parse_fields(self, payload: str):
        fields = {}
        for token in payload.split():
            if "=" not in token:
                continue
            key, value = token.split("=", 1)
            fields[key] = self._coerce_value(value)
        return fields

    @staticmethod
    def _bar(value: int, width: int = 24, scale: int = 32) -> str:
        if scale <= 0:
            scale = 1
        filled = min(width, int(round((value * width) / scale)))
        return "[" + ("#" * filled) + ("." * (width - filled)) + "]"

    def ingest_line(self, line: str) -> bool:
        self.recent.append(line)

        if line.startswith("[PASS]"):
            self.pass_seen = True
            return True

        if line.startswith("[FAIL]"):
            self.fail_seen = True
            return True

        if not line.startswith("[TEL]"):
            if line.startswith("[RTOS]"):
                self.boot_seen = True
                return True
            return False

        fields = self._parse_fields(line[5:].strip())

        if fields.get("dashboard") == "armed":
            self.boot_seen = True
        if fields.get("scheduler") == "starting":
            self.scheduler_started = True
        if "task" in fields:
            self.last_task = str(fields["task"])
        if "tick" in fields:
            self.last_tick = int(fields["tick"])
        if "beat" in fields:
            self.last_beat = int(fields["beat"])
        if "a" in fields:
            self.task_a = int(fields["a"])
        if "b" in fields:
            self.task_b = int(fields["b"])

        return True

    def status_text(self) -> str:
        if self.pass_seen:
            return "PASS"
        if self.fail_seen:
            return "FAIL"
        if self.scheduler_started:
            return "RUNNING"
        if self.boot_seen:
            return "BOOTING"
        return "IDLE"

    def render(self):
        if clear_output is not None:
            clear_output(wait=True)

        scale = max(4, self.task_a, self.task_b, 8)
        lines = [
            "=== FreeRTOS on PYNQ-Z2 ===",
            f"status        : {self.status_text()}",
            f"last task     : {self.last_task}",
            f"tick / beat   : {self.last_tick} / {self.last_beat}",
            f"task A count  : {self.task_a:>6} {self._bar(self.task_a, scale=scale)}",
            f"task B count  : {self.task_b:>6} {self._bar(self.task_b, scale=scale)}",
            "recent lines   :",
        ]
        for line in list(self.recent)[-4:]:
            lines.append(f"  {line}")
        print("\n".join(lines), flush=True)


def demo():
    bridge = NotebookUartBridge()

    print("[HOST] booting SoC over notebook UART bridge...")
    bridge.boot(FIRMWARE_BIN)

    print("[HOST] watching FreeRTOS telemetry dashboard...")
    bridge.watch_dashboard(seconds=5.0)


if __name__ == "__main__":
    demo()

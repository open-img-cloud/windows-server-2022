"""Screenshots of a QEMU console through QMP, for CI debugging.

Usage: python3 screenshots.py QMP_SOCKET OUT_DIR INTERVAL_SECONDS

Waits for the socket, then saves OUT_DIR/NNN-HHMMSS.png every interval until
it is killed. Connection errors (VM not started yet, or stopped) are ignored.
"""
import json
import os
import socket
import sys
import time

sock_path, out_dir, interval = sys.argv[1], sys.argv[2], int(sys.argv[3])


def shot(path):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(10)
    try:
        s.connect(sock_path)
        f = s.makefile("rw")
        f.readline()  # greeting
        for cmd in ({"execute": "qmp_capabilities"},
                    {"execute": "screendump", "arguments": {"filename": path, "format": "png"}}):
            f.write(json.dumps(cmd) + "\n")
            f.flush()
            while True:
                reply = json.loads(f.readline())
                if "return" in reply or "error" in reply:
                    break
    finally:
        s.close()


n = 0
while True:
    if os.path.exists(sock_path):
        n += 1
        try:
            shot(os.path.join(out_dir, f"{n:03d}-{time.strftime('%H%M%S')}.png"))
        except (OSError, ValueError):
            pass
    time.sleep(interval)

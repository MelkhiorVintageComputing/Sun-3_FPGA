#!/usr/bin/env python3
"""Talk to the board's serial console (ttya) without pyserial.

    tools/board_console.py [-d /dev/ttyUSB0] [-b 9600] [-t SECONDS]
                           [--until STRING] [--send LINE ...] [--break] [-o LOG]

Opens the port raw at BAUD 8N1, prints (and optionally logs) everything the
machine says for SECONDS, or until STRING has been seen.  Each --send LINE is
typed after the output has been quiet for a moment (or after --until matched),
ending in a carriage return, which is what the PROM monitor's getline wants.

Only the standard library: termios/tty, so it runs on a bare Debian.
"""

import argparse
import os
import select
import sys
import termios
import time
import tty

BAUDS = {9600: termios.B9600, 19200: termios.B19200, 38400: termios.B38400,
         57600: termios.B57600, 115200: termios.B115200}


def open_port(dev, baud):
    fd = os.open(dev, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    tty.setraw(fd)
    attrs = termios.tcgetattr(fd)
    attrs[4] = attrs[5] = BAUDS[baud]               # ispeed, ospeed
    attrs[2] &= ~(termios.PARENB | termios.CSTOPB | termios.CSIZE | termios.CRTSCTS)
    attrs[2] |= termios.CS8 | termios.CLOCAL | termios.CREAD
    termios.tcsetattr(fd, termios.TCSANOW, attrs)
    termios.tcflush(fd, termios.TCIOFLUSH)
    return fd


def send_break(fd, baud):
    # tcsendbreak() is refused by some USB serial drivers (the CP210x on the
    # Wukong says EPIPE), so fake it: a 0x00 at 300 baud holds the line low
    # for 30 ms, far longer than any 9600 baud frame -- which the SCC reports
    # as a break.
    try:
        termios.tcsendbreak(fd, 0)
        return
    except termios.error:
        pass
    attrs = termios.tcgetattr(fd)
    attrs[4] = attrs[5] = termios.B300
    termios.tcsetattr(fd, termios.TCSADRAIN, attrs)
    os.write(fd, b"\0")
    termios.tcdrain(fd)
    time.sleep(0.05)
    attrs[4] = attrs[5] = BAUDS[baud]
    termios.tcsetattr(fd, termios.TCSADRAIN, attrs)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("-d", "--device", default=os.environ.get("SUN3_CONSOLE", "/dev/ttyUSB0"),
                    help="default $SUN3_CONSOLE, else /dev/ttyUSB0 (the DECA: /tmp/deca-console)")
    ap.add_argument("-b", "--baud", type=int, default=9600, choices=sorted(BAUDS))
    ap.add_argument("-t", "--time", type=float, default=30.0, help="seconds to listen")
    ap.add_argument("--until", help="stop once this string has been received")
    ap.add_argument("--send", action="append", default=[], help="a line to type (repeatable)")
    ap.add_argument("--quiet-gap", type=float, default=1.0,
                    help="seconds of silence before typing the next --send line")
    ap.add_argument("--break", dest="brk", action="store_true",
                    help="send a BREAK first (a Sun kernel drops to the PROM monitor)")
    ap.add_argument("-o", "--log", help="also append everything received to this file")
    a = ap.parse_args()

    fd = open_port(a.device, a.baud)
    if a.brk:
        send_break(fd, a.baud)
    log = open(a.log, "ab") if a.log else None
    seen = b""
    deadline = time.monotonic() + a.time
    last_rx = time.monotonic()
    pending = list(a.send)
    until = a.until.encode() if a.until else None
    matched = False
    ever_matched = False

    try:
        while time.monotonic() < deadline:
            r, _, _ = select.select([fd], [], [], 0.1)
            if r:
                # A CP210x can report readable with nothing to read (seen
                # right after the board was replugged): EAGAIN is "nothing
                # yet", not an error.
                try:
                    data = os.read(fd, 4096)
                except BlockingIOError:
                    continue
                if data:
                    last_rx = time.monotonic()
                    sys.stdout.buffer.write(data.replace(b"\0", b""))
                    sys.stdout.buffer.flush()
                    if log:
                        log.write(data)
                        log.flush()
                    seen = (seen + data)[-4096:]
                    if until and until in seen:
                        matched = True
                        ever_matched = True
                        seen = b""
                        if not pending:
                            break
            if pending and (matched or not until) and time.monotonic() - last_rx > a.quiet_gap:
                line = pending.pop(0)
                os.write(fd, line.encode() + b"\r")
                matched = False
                last_rx = time.monotonic()
                if not pending and not until:
                    deadline = min(deadline, time.monotonic() + max(a.quiet_gap * 3, 2.0))
    finally:
        os.close(fd)
        if log:
            log.close()
    print()
    return 0 if (until is None or ever_matched) else 1


if __name__ == "__main__":
    sys.exit(main())

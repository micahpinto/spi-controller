# PC-side test for the SPI master on the Arty S7-25 (spi_uart_top).
# Each byte sent over the UART goes out on SPI MOSI, comes back on MISO
# through the jumper, and is returned to the PC.
#
# Normal run (jumper JA2-JA3 in place):  pytest test_spi_loopback.py -v
# Jumper removed:                         set JUMPER_OUT=1, then run pytest again

import os
import random
import pytest
import serial

PORT = os.getenv("UART_PORT", "COM4")
BAUD = 115200
JUMPER_OUT = os.getenv("JUMPER_OUT", "0") == "1"

needs_jumper = pytest.mark.skipif(JUMPER_OUT, reason="jumper removed")
needs_no_jumper = pytest.mark.skipif(not JUMPER_OUT, reason="run with the jumper removed")


@pytest.fixture(scope="module")
def ser():
    connection = serial.Serial(PORT, BAUD, timeout=2)
    yield connection
    connection.close()


def send_and_read(ser, data):
    ser.reset_input_buffer()
    ser.write(data)
    return ser.read(len(data))


@needs_jumper
@pytest.mark.parametrize("value", range(256))
def test_every_byte(ser, value):
    sent = bytes([value])
    received = send_and_read(ser, sent)
    assert received == sent, f"sent 0x{value:02X}, got {received.hex()}"


@needs_jumper
def test_burst_all_values(ser):
    sent = bytes(range(256))
    received = send_and_read(ser, sent)
    assert len(received) == len(sent), f"sent {len(sent)} bytes, got {len(received)} back"
    assert received == sent, "burst data does not match"


@needs_jumper
@pytest.mark.parametrize("seed", range(5))
def test_random_burst(ser, seed):
    rng = random.Random(seed)
    sent = bytes(rng.randrange(256) for _ in range(1000))
    received = send_and_read(ser, sent)
    assert len(received) == len(sent), f"seed {seed}: sent {len(sent)} bytes, got {len(received)} back"
    assert received == sent, f"seed {seed}: data does not match"


@needs_no_jumper
def test_jumper_out_reads_zero(ser):
    sent = bytes([0x5A, 0xA5, 0xFF, 0x01])
    received = send_and_read(ser, sent)
    assert received == bytes(len(sent)), f"expected 00s with MISO open, got {received.hex()}"
"""ts-tunnel - local TCP listener bridged through a Tailscale userspace
instance's SOCKS5 proxy. For apps without proxy support (Minecraft etc.).

Usage: ts-tunnel <socksPort> <localPort> <host> <remotePort>
"""
import asyncio
import struct
import sys


async def pipe(reader, writer):
    try:
        while True:
            data = await reader.read(65536)
            if not data:
                break
            writer.write(data)
            await writer.drain()
    except (ConnectionError, BrokenPipeError):
        pass
    finally:
        try:
            writer.close()
            await writer.wait_closed()
        except Exception:
            pass


async def socks5_connect(s_host, s_port, t_host, t_port):
    reader, writer = await asyncio.open_connection(s_host, s_port)
    # greeting: no auth
    writer.write(b"\x05\x01\x00")
    await writer.drain()
    resp = await reader.readexactly(2)
    if resp[0:1] != b"\x05" or resp[1:2] != b"\x00":
        raise RuntimeError(f"SOCKS5 greeting failed: {resp.hex()}")
    # connect request: IPv4 or hostname
    parts = t_host.split(".")
    if len(parts) == 4 and all(p.isdigit() for p in parts):
        addr = b"\x01" + bytes(int(p) for p in parts)
    else:
        addr = b"\x03" + bytes([len(t_host)]) + t_host.encode()
    req = b"\x05\x01\x00" + addr + struct.pack("!H", t_port)
    writer.write(req)
    await writer.drain()
    resp = await reader.readexactly(10)
    if resp[1] != 0:
        raise RuntimeError(f"SOCKS5 connect failed: code {resp[1]}")
    return reader, writer


async def handle_client(
    client_reader, client_writer, s_host, s_port, t_host, t_port
):
    try:
        remote_reader, remote_writer = await socks5_connect(
            s_host, s_port, t_host, t_port
        )
    except Exception as exc:
        msg = f"ts-tunnel: connect {t_host}:{t_port} failed: {exc}"
        print(msg, file=sys.stderr)
        client_writer.close()
        return
    await asyncio.gather(
        pipe(client_reader, remote_writer),
        pipe(remote_reader, client_writer),
    )


async def start_listeners(cb, port):
    """Listen on loopback IPv4 and IPv6.

    Java resolves "localhost" to ::1 first, so an IPv4-only listener is
    invisible to the Minecraft client even when the port is right.
    """
    servers = []
    for host in ("127.0.0.1", "::1"):
        try:
            server = await asyncio.start_server(cb, host, port)
        except OSError as exc:
            print(
                f"ts-tunnel: listener {host}:{port} unavailable: {exc}",
                file=sys.stderr,
            )
            continue
        servers.append(server)
    if not servers:
        raise SystemExit(f"ts-tunnel: cannot bind port {port}")
    return servers


async def main():
    if len(sys.argv) != 5:
        print(__doc__, file=sys.stderr)
        sys.exit(1)
    socks_port = int(sys.argv[1])
    local_port = int(sys.argv[2])
    target_host = sys.argv[3]
    target_port = int(sys.argv[4])

    async def cb(r, w):
        await handle_client(
            r, w, "127.0.0.1", socks_port, target_host, target_port
        )

    servers = await start_listeners(cb, local_port)
    dest = f"socks5:{socks_port} -> {target_host}:{target_port}"
    print(
        f"ts-tunnel: localhost:{local_port} (IPv4+IPv6) -> {dest}",
        flush=True,
    )
    try:
        await asyncio.Event().wait()
    finally:
        for server in servers:
            server.close()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
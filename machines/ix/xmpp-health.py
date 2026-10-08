#!/usr/bin/env python3
"""Read-only XMPP STARTTLS/SASL advertisement and HTTPS health checks.

No credentials, messages, registration, repair, or service restarts. A failed
probe exits nonzero for systemd/journal monitoring; it never resets a database.
"""
import argparse
import json
import socket
import ssl
import time
import xml.etree.ElementTree as ET
from xml.sax.saxutils import quoteattr

STREAM = "http://etherx.jabber.org/streams"
TLS = "urn:ietf:params:xml:ns:xmpp-tls"
SASL = "urn:ietf:params:xml:ns:xmpp-sasl"
LIMIT = 32768


def element(sock, wanted):
    parser = ET.XMLPullParser(events=("start", "end"))
    total = 0
    tail = b""
    deadline = time.monotonic() + 10
    while total < LIMIT and time.monotonic() < deadline:
        data = sock.recv(min(4096, LIMIT - total))
        if not data:
            raise RuntimeError("XMPP closed before expected response")
        total += len(data)
        scanned = (tail + data).upper()
        if b"<!DOCTYPE" in scanned or b"<!ENTITY" in scanned:
            raise RuntimeError("Unexpected XML declaration")
        tail = scanned[-10:]
        parser.feed(data)
        for event, node in parser.read_events():
            if node.tag in {f"{{{STREAM}}}error", f"{{{TLS}}}failure"}:
                raise RuntimeError("XMPP returned a protocol error")
            if event == "end" and node.tag == wanted:
                return node
    raise RuntimeError("XMPP response exceeded time/size bound")


def open_stream(sock, host):
    sock.sendall(("<stream:stream xmlns='jabber:client' xmlns:stream='" + STREAM
                  + "' version='1.0' to=" + quoteattr(host) + ">").encode())
    return element(sock, f"{{{STREAM}}}features")


def certificate_days(sock, now=None):
    remaining = (ssl.cert_time_to_seconds(sock.getpeercert()["notAfter"])
                 - (time.time() if now is None else now)) / 86400
    if remaining < 7:
        raise RuntimeError("Served certificate expires in less than seven days")
    return round(remaining, 2)


def probe(host, address, cafile):
    context = ssl.create_default_context(cafile=cafile)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    # Check the certificate hostname, even when connecting to a numeric tailnet IP.
    assert context.check_hostname and context.verify_mode == ssl.CERT_REQUIRED
    with socket.create_connection((address, 5222), timeout=8) as raw:
        features = open_stream(raw, host)
        starttls = features.find(f"{{{TLS}}}starttls")
        if starttls is None or starttls.find(f"{{{TLS}}}required") is None:
            raise RuntimeError("XMPP did not require STARTTLS")
        raw.sendall(("<starttls xmlns='" + TLS + "'/>").encode())
        element(raw, f"{{{TLS}}}proceed")
        with context.wrap_socket(raw, server_hostname=host) as secure:
            days_xmpp = certificate_days(secure)
            features = open_stream(secure, host)
            mechanisms = {n.text for n in features.findall(
                f"{{{SASL}}}mechanisms/{{{SASL}}}mechanism")}
            if "SCRAM-SHA-256" not in mechanisms:
                raise RuntimeError("XMPP did not advertise expected SCRAM authentication")
            secure.sendall(b"</stream:stream>")
    with socket.create_connection((address, 5443), timeout=8) as raw:
        with context.wrap_socket(raw, server_hostname=host) as secure:
            days_https = certificate_days(secure)
            secure.sendall((f"HEAD /upload HTTP/1.1\r\nHost: {host}:5443\r\n"
                            "Connection: close\r\n\r\n").encode())
            response = bytearray()
            while b"\n" not in response and len(response) < 4096:
                part = secure.recv(512)
                if not part:
                    break
                response.extend(part)
            status = bytes(response).split(b"\r\n", 1)[0].split()
            if len(status) < 2 or status[0] not in {b"HTTP/1.0", b"HTTP/1.1"}:
                raise RuntimeError("HTTPS returned an invalid response")
            code = int(status[1])
            if not 200 <= code < 500:
                raise RuntimeError("HTTPS upload endpoint returned a server error")
    return {"xmpp_starttls": "verified", "scram_advertised": True,
            "https_tls": "verified", "https_status": code,
            "certificate_days_remaining": min(days_xmpp, days_https)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", required=True)
    parser.add_argument("--address", required=True)
    parser.add_argument("--cafile", default="/etc/ssl/certs/ca-certificates.crt")
    args = parser.parse_args()
    if any(c in args.host for c in "\r\n\x00"):
        parser.error("Invalid hostname")
    try:
        result = probe(args.host, args.address, args.cafile)
    except (OSError, ValueError, RuntimeError, ET.ParseError) as exc:
        print(json.dumps({"healthy": False, "error": str(exc)}), flush=True)
        raise SystemExit(1) from None
    print(json.dumps({"healthy": True, **result}), flush=True)


if __name__ == "__main__":
    main()

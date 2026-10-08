"""Read-only health probe and ix-only supervision policy; fake sockets only."""
import importlib.util
import json
from pathlib import Path
import ssl
import subprocess
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("xmpp_health", ROOT / "xmpp-health.py")
health = importlib.util.module_from_spec(spec)
spec.loader.exec_module(health)


class Sock:
    def __init__(self, *chunks):
        self.chunks = list(chunks)
        self.sent = []
    def recv(self, limit):
        return self.chunks.pop(0) if self.chunks else b""
    def sendall(self, data):
        self.sent.append(data)
    def getpeercert(self):
        return {"notAfter": "Oct  8 00:00:00 2099 GMT"}
    def __enter__(self):
        return self
    def __exit__(self, *args):
        pass


FEATURES = (f"<stream:stream xmlns:stream='{health.STREAM}'><stream:features>"
            f"<starttls xmlns='{health.TLS}'><required/></starttls></stream:features>").encode()
PROCEED = f"<proceed xmlns='{health.TLS}'/>".encode()
AUTH = (f"<stream:stream xmlns:stream='{health.STREAM}'><stream:features>"
        f"<mechanisms xmlns='{health.SASL}'><mechanism>SCRAM-SHA-256</mechanism>"
        "</mechanisms></stream:features>").encode()


class HealthTests(unittest.TestCase):
    def test_fragmented_xml_and_protocol_errors(self):
        node = health.element(Sock(FEATURES[:23], FEATURES[23:]), f"{{{health.STREAM}}}features")
        self.assertIsNotNone(node.find(f"{{{health.TLS}}}starttls"))
        for data in [b"", b"<broken", f"<failure xmlns='{health.TLS}'/>".encode(),
                     b"<!DOCTYPE a><a/>", b" " * health.LIMIT]:
            with self.subTest(data=data[:30]), self.assertRaises((RuntimeError, health.ET.ParseError)):
                health.element(Sock(data), f"{{{health.TLS}}}proceed")

    def test_expiring_certificate_is_a_failure(self):
        sock = Sock()
        expiry = ssl.cert_time_to_seconds(sock.getpeercert()["notAfter"])
        self.assertEqual(health.certificate_days(sock, expiry - 8 * 86400), 8)
        with self.assertRaises(RuntimeError):
            health.certificate_days(sock, expiry - 6 * 86400)

    def check_probe(self, features=FEATURES, auth=AUTH, http=b"HTTP/1.1 404 Not Found\r\n\r\n"):
        raw_x, raw_h = Sock(features, PROCEED), Sock()
        tls_x, tls_h = Sock(auth), Sock(http)
        context = Mock(check_hostname=True, verify_mode=ssl.CERT_REQUIRED)
        context.wrap_socket.side_effect = [tls_x, tls_h]
        with patch.object(health.ssl, "create_default_context", return_value=context), \
                patch.object(health.socket, "create_connection", side_effect=[raw_x, raw_h]) as connect:
            result = health.probe("example.test", "100.64.0.1", "/system/ca.pem")
        self.assertEqual([call.args[0] for call in connect.call_args_list],
                         [("100.64.0.1", 5222), ("100.64.0.1", 5443)])
        self.assertTrue(all(call.kwargs["server_hostname"] == "example.test"
                            for call in context.wrap_socket.call_args_list))
        self.assertEqual(context.minimum_version, ssl.TLSVersion.TLSv1_2)
        self.assertNotIn(b"<auth", b"".join(tls_x.sent))
        self.assertTrue(tls_h.sent[0].startswith(b"HEAD /upload "))
        return result

    def test_tls_xmpp_and_https_success_without_login_or_messages(self):
        self.assertEqual(self.check_probe()["https_status"], 404)

    def test_missing_tls_sasl_and_bad_http_fail(self):
        for kwargs in [dict(features=FEATURES.replace(b"<required/>", b"")),
                       dict(auth=AUTH.replace(b"SCRAM-SHA-256", b"PLAIN")),
                       dict(http=b"HTTP/1.1 503 Unavailable\r\n"), dict(http=b"garbage\r\n")]:
            with self.subTest(kwargs=kwargs), self.assertRaises(RuntimeError):
                self.check_probe(**kwargs)

    def test_ix_bounded_restart_and_read_only_timer(self):
        config = json.loads(subprocess.check_output(['nix', 'eval', '--impure', '--json', '--expr',
            f'(import {ROOT / "ejabberd.nix"} {{pkgs.python3="/test-python";}})'], text=True))
        systemd = config['systemd']
        ejabberd = systemd['services']['ejabberd']
        self.assertEqual(ejabberd['serviceConfig'], {'Restart': 'on-failure', 'RestartSec': '30s'})
        self.assertEqual(ejabberd['startLimitIntervalSec'], 600)
        self.assertEqual(ejabberd['startLimitBurst'], 3)
        checker = systemd['services']['ix-xmpp-health']
        self.assertTrue(checker['serviceConfig']['DynamicUser'])
        self.assertEqual(checker['serviceConfig']['Type'], 'oneshot')
        self.assertNotIn('Restart', checker['serviceConfig'])
        self.assertEqual(systemd['timers']['ix-xmpp-health']['timerConfig']['OnUnitActiveSec'], '5min')
        self.assertNotIn('subprocess', (ROOT / 'xmpp-health.py').read_text())
        self.assertEqual(config['networking']['firewall']['interfaces']['tailscale0']['allowedTCPPorts'], [5222, 5443])


if __name__ == '__main__':
    unittest.main()

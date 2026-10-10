"""Run in the patched Matter package's Nix check phase, without network access."""
from datetime import datetime, timedelta, timezone
from pathlib import Path
import tempfile
import unittest

try:
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec
    from matter_server.server.helpers import paa_certificates as paa
except ImportError:
    paa = None


@unittest.skipIf(paa is None, "requires the Matter package's Nix test environment")
class PaaCertificateTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        paa.CERT_SUBJECT_KEY_IDS.clear()
        key = ec.generate_private_key(ec.SECP256R1())
        name = x509.Name([x509.NameAttribute(x509.NameOID.COMMON_NAME, "ix-test-PAA")])
        now = datetime.now(timezone.utc)
        cert = (
            x509.CertificateBuilder()
            .subject_name(name).issuer_name(name).public_key(key.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(now - timedelta(days=1))
            .not_valid_after(now + timedelta(days=1))
            .add_extension(x509.SubjectKeyIdentifier.from_public_key(key.public_key()), critical=False)
            .sign(key, hashes.SHA256())
        )
        self.pem = cert.public_bytes(serialization.Encoding.PEM).decode()

    async def test_malformed_is_skipped_and_valid_certificate_still_loads(self):
        with self.assertLogs(paa.LOGGER, level="WARNING"):
            result = await paa.write_paa_root_cert(self.directory, "test_", "invalid PEM", "test")
        self.assertFalse(result)
        self.assertEqual(list(self.directory.iterdir()), [])
        self.assertEqual(paa.CERT_SUBJECT_KEY_IDS, set())
        self.assertTrue(await paa.write_paa_root_cert(self.directory, "test_", self.pem, "test"))
        self.assertEqual(len(list(self.directory.glob("*.pem"))), 1)
        self.assertEqual(len(list(self.directory.glob("*.der"))), 1)
        self.assertFalse(await paa.write_paa_root_cert(self.directory, "test_", self.pem, "test"))

    async def test_storage_errors_are_not_silenced(self):
        with self.assertRaises(FileNotFoundError):
            await paa.write_paa_root_cert(self.directory / "missing", "test_", self.pem, "test")


if __name__ == "__main__":
    unittest.main()

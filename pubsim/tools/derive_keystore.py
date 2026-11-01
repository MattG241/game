#!/usr/bin/env python3
"""Derive a stable Android signing keystore from a single secret passphrase.

The same passphrase always yields the same RSA key and certificate, so every CI
build is signed identically and updates install over the previous version
without losing save data. Only the passphrase needs to be stored (as a GitHub
Actions secret); no keystore file is ever committed.

usage: derive_keystore.py OUT.p12 ALIAS   (passphrase read from $PUBSIM_SIGNING_PASSPHRASE)
"""
import datetime
import hashlib
import hmac
import os
import sys

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID


class DRBG:
    """HMAC-SHA256 counter-mode byte stream (deterministic)."""

    def __init__(self, seed: bytes):
        self.key = hashlib.sha256(b"pubsim-keystore-v1" + seed).digest()
        self.counter = 0

    def bytes(self, n: int) -> bytes:
        out = b""
        while len(out) < n:
            out += hmac.new(self.key, self.counter.to_bytes(8, "big"), hashlib.sha256).digest()
            self.counter += 1
        return out[:n]

    def randint_bits(self, bits: int) -> int:
        return int.from_bytes(self.bytes((bits + 7) // 8), "big") >> ((8 - bits % 8) % 8)


SMALL_PRIMES = [p for p in range(3, 2000) if all(p % d for d in range(2, int(p ** 0.5) + 1))]


def is_probable_prime(n: int, rng: DRBG, rounds: int = 40) -> bool:
    if n < 2:
        return False
    for p in SMALL_PRIMES:
        if n % p == 0:
            return n == p
    d, s = n - 1, 0
    while d % 2 == 0:
        d //= 2
        s += 1
    for _ in range(rounds):
        a = 2 + rng.randint_bits(n.bit_length() - 1) % (n - 3)
        x = pow(a, d, n)
        if x in (1, n - 1):
            continue
        for _ in range(s - 1):
            x = pow(x, 2, n)
            if x == n - 1:
                break
        else:
            return False
    return True


def gen_prime(bits: int, rng: DRBG, e: int) -> int:
    while True:
        c = rng.randint_bits(bits) | (1 << (bits - 1)) | (1 << (bits - 2)) | 1
        if (c - 1) % e != 0 and is_probable_prime(c, rng):
            return c


def derive_key(passphrase: str, bits: int = 2048) -> rsa.RSAPrivateKey:
    rng = DRBG(passphrase.encode("utf-8"))
    e = 65537
    while True:
        p = gen_prime(bits // 2, rng, e)
        q = gen_prime(bits // 2, rng, e)
        if p != q and (p * q).bit_length() == bits:
            break
    if p < q:
        p, q = q, p
    n = p * q
    phi = (p - 1) * (q - 1)
    d = pow(e, -1, phi)
    numbers = rsa.RSAPrivateNumbers(
        p=p, q=q, d=d, dmp1=d % (p - 1), dmq1=d % (q - 1), iqmp=pow(q, -1, p),
        public_numbers=rsa.RSAPublicNumbers(e, n))
    return numbers.private_key()


def main() -> None:
    out, alias = sys.argv[1], sys.argv[2]
    passphrase = os.environ.get("PUBSIM_SIGNING_PASSPHRASE", "")
    if len(passphrase) < 12:
        sys.exit("PUBSIM_SIGNING_PASSPHRASE must be at least 12 characters")
    key = derive_key(passphrase)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "The Irish Pub Simulator")])
    start = datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc)
    cert = (x509.CertificateBuilder()
            .subject_name(name).issuer_name(name).public_key(key.public_key())
            .serial_number(int.from_bytes(hashlib.sha256(passphrase.encode()).digest()[:8], "big"))
            .not_valid_before(start).not_valid_after(start + datetime.timedelta(days=365 * 40))
            .sign(key, hashes.SHA256()))
    store_pw = hashlib.sha256(("store:" + passphrase).encode()).hexdigest()[:32]
    data = pkcs12.serialize_key_and_certificates(
        alias.encode(), key, cert, None, serialization.BestAvailableEncryption(store_pw.encode()))
    with open(out, "wb") as f:
        f.write(data)
    fp = hashlib.sha256(cert.public_bytes(serialization.Encoding.DER)).hexdigest()
    # The store password is derived too; print it for the workflow (masked by Actions).
    print(f"KEYSTORE_PASSWORD={store_pw}")
    print(f"CERT_SHA256={fp}", file=sys.stderr)


if __name__ == "__main__":
    main()

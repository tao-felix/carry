"""The single paid plan. A StoreKit 2 signed transaction (JWS) written by the iOS app to license.json,
verified offline against Apple Root CA G3. Nothing here talks to a server."""

from __future__ import annotations

import base64
import json
import os
import time
from dataclasses import dataclass
from importlib import resources
from pathlib import Path

from carry.config import CONTAINER_DIR, PRO_PRODUCT_ID, PRO_PRODUCT_IDS

GRACE_SECONDS = 3 * 24 * 3600


@dataclass
class ProStatus:
    active: bool
    reason: str
    expires_at: str | None = None
    environment: str | None = None
    source: str = "none"


def _b64url(s: str) -> bytes:
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))


def _apple_root():
    from cryptography import x509

    pem = resources.files("carry.assets").joinpath("AppleRootCA-G3.pem").read_bytes()
    return x509.load_pem_x509_certificate(pem)


def verify_jws(jws: str) -> ProStatus:
    from cryptography import x509
    from cryptography.exceptions import InvalidSignature
    from cryptography.hazmat.primitives import hashes
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.hazmat.primitives.asymmetric.utils import encode_dss_signature

    try:
        h64, p64, s64 = jws.split(".")
        header = json.loads(_b64url(h64))
        payload = json.loads(_b64url(p64))
        sig = _b64url(s64)
    except Exception:  # noqa: BLE001
        return ProStatus(False, "license.json is not a valid JWS")
    if header.get("alg") != "ES256" or not header.get("x5c"):
        return ProStatus(False, "unexpected JWS header")
    try:
        chain = [x509.load_der_x509_certificate(base64.b64decode(c)) for c in header["x5c"]]
    except Exception:  # noqa: BLE001
        return ProStatus(False, "bad certificate chain")
    root = _apple_root()
    try:
        if chain[-1].public_bytes(__import__("cryptography.hazmat.primitives.serialization", fromlist=["Encoding"]).Encoding.DER) != root.public_bytes(
            __import__("cryptography.hazmat.primitives.serialization", fromlist=["Encoding"]).Encoding.DER
        ):
            chain.append(root)
        for cert, issuer in zip(chain, chain[1:]):
            cert.verify_directly_issued_by(issuer)
    except Exception:  # noqa: BLE001
        return ProStatus(False, "certificate chain does not lead to Apple Root CA G3")
    try:
        r, s = int.from_bytes(sig[:32], "big"), int.from_bytes(sig[32:], "big")
        chain[0].public_key().verify(encode_dss_signature(r, s), f"{h64}.{p64}".encode(), ec.ECDSA(hashes.SHA256()))
    except (InvalidSignature, Exception):  # noqa: BLE001
        return ProStatus(False, "signature does not verify")
    if payload.get("productId") not in PRO_PRODUCT_IDS:
        return ProStatus(False, f"license is for {payload.get('productId')}, not Carry Pro")
    if payload.get("revocationDate"):
        return ProStatus(False, "license was revoked")
    exp_ms = payload.get("expiresDate")
    if exp_ms and exp_ms / 1000 + GRACE_SECONDS < time.time():
        return ProStatus(False, "license expired", expires_at=_ms_iso(exp_ms), environment=payload.get("environment"), source="phone")
    return ProStatus(True, "verified StoreKit transaction", expires_at=_ms_iso(exp_ms) if exp_ms else None,
                     environment=payload.get("environment"), source="phone")


def _ms_iso(ms: float) -> str:
    from datetime import datetime

    return datetime.fromtimestamp(ms / 1000).astimezone().isoformat(timespec="seconds")


def status() -> ProStatus:
    if os.environ.get("CARRY_PRO") == "1":
        return ProStatus(True, "CARRY_PRO=1 (developer override)", source="env")
    p = CONTAINER_DIR / "license.json"
    if not p.exists():
        return ProStatus(False, "no license.json in the Carry folder yet")
    try:
        data = json.loads(p.read_text())
    except Exception:  # noqa: BLE001
        return ProStatus(False, "license.json unreadable")
    if not data.get("jws"):
        return ProStatus(False, "license.json has no jws")
    return verify_jws(data["jws"])


def is_pro() -> bool:
    return status().active

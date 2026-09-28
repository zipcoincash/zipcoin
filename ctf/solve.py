#!/usr/bin/env python3
"""The Reader — decrypt the zip phrase of the prize note.

    python3 solve.py <a1> <a2> <a3> <a4> <a5> <a6>

Key = SHA-256 of the six answers, lowercase, joined with "|" and nothing else.
Cipher = AES-256-GCM (12-byte nonce, tag appended). Needs `pip install cryptography`.
"""
import hashlib, json, sys
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

p = json.load(open(__file__.rsplit("/", 1)[0] + "/prize.json" if "/" in __file__ else "prize.json"))
answers = [a.strip().lower() for a in sys.argv[1:]]
if len(answers) != 6:
    sys.exit("need exactly 6 answers")
key = hashlib.sha256("|".join(answers).encode()).digest()
try:
    phrase = AESGCM(key).decrypt(bytes.fromhex(p["nonce"]), bytes.fromhex(p["ciphertext"]), None).decode()
except Exception:
    sys.exit("wrong answers")
assert hashlib.sha256(phrase.encode()).hexdigest() == p["check"]
print(phrase)
print("\nGo to zipcoin.cash/unzip, choose 'use a 12 word zip phrase', paste it, unzip to any address. First valid unzip wins.")

#!/usr/bin/env python3
"""Fetches the pinned Windows Server ISO from the open-img-cloud ISO vault.

Usage: fetch-iso.py <iso.sha256> <output.iso>

iso.sha256 holds one line, "<sha256>  <key in the vault>". The vault is a
private bucket of another Infomaniak project, read with a read-only key
(OIC_ISO_VAULT_KEY_ID / OIC_ISO_VAULT_SECRET) and addressed as
"<project>:<bucket>" (Ceph tenants). The download fails unless the file
matches the pinned sha256.
"""
import hashlib
import os
import sys

import boto3
from boto3.s3.transfer import TransferConfig
from botocore.handlers import validate_bucket_name

ENDPOINT = "https://s3.gva2.infomaniak.cloud"
BUCKET = "c0862b7f7b6849508bbcd74fb00e7fe2:oic-iso-vault"

lock, out = sys.argv[1], sys.argv[2]
expected, key = open(lock).read().split()
s3 = boto3.client(
    "s3",
    endpoint_url=ENDPOINT,
    region_name="us-east-1",
    aws_access_key_id=os.environ["OIC_ISO_VAULT_KEY_ID"],
    aws_secret_access_key=os.environ["OIC_ISO_VAULT_SECRET"],
)
# boto3 rejects the colon of a tenant-qualified bucket name.
s3.meta.events.unregister("before-parameter-build.s3", validate_bucket_name)

print(f"fetching {key} from the ISO vault")
s3.download_file(BUCKET, key, out, Config=TransferConfig(multipart_chunksize=64 << 20, max_concurrency=8))

h = hashlib.sha256()
with open(out, "rb") as f:
    for chunk in iter(lambda: f.read(8 << 20), b""):
        h.update(chunk)
if h.hexdigest() != expected:
    os.remove(out)
    sys.exit(f"sha256 mismatch for {key}: got {h.hexdigest()}, pinned {expected}")
print(f"{key}: {os.path.getsize(out)} bytes, sha256 {expected} (matches iso.sha256)")

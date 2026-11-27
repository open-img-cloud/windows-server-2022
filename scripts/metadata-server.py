"""Minimal OpenStack metadata server for the boot test (Python standard library).

Serves what Cloudbase-Init (HttpService) reads from Nova, and keeps the
password it posts, as Nova does:
  GET  /openstack/{latest,2013-04-04}/meta_data.json  uuid, hostname, key
  GET  /openstack/2013-04-04/password                  stored password or ""
  POST /openstack/2013-04-04/password                  stores it once (409 after)
Anything else is a 404, like a path Nova does not serve. The posted password
(base64 of the RSA encrypted password) goes to PASSWORD_FILE.

Usage: python3 metadata-server.py PORT HOSTNAME PUBLIC_KEY_FILE PASSWORD_FILE
"""
import json
import os
import sys
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

port, hostname, key_file, password_file = sys.argv[1:5]
with open(key_file) as f:
    public_key = f.read().strip()
meta_data = json.dumps({
    "uuid": str(uuid.uuid4()),
    "hostname": hostname,
    "name": hostname,
    "public_keys": {"oic-smoke": public_key},
    "keys": [{"name": "oic-smoke", "type": "ssh", "data": public_key}],
}).encode()
META_PATHS = ("/openstack/latest/meta_data.json", "/openstack/2013-04-04/meta_data.json")
PASSWORD_PATH = "/openstack/2013-04-04/password"
password = b""


class Handler(BaseHTTPRequestHandler):
    def reply(self, code, body=b""):
        self.send_response(code)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?")[0]
        if path in META_PATHS:
            self.reply(200, meta_data)
        elif path == PASSWORD_PATH:
            self.reply(200, password)
        else:
            self.reply(404)

    def do_POST(self):
        global password
        body = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        if self.path.split("?")[0] != PASSWORD_PATH:
            self.reply(404)
        elif password:
            self.reply(409)
        else:
            password = body
            # Written then renamed: the boot test reads it as soon as it exists.
            with open(password_file + ".tmp", "wb") as f:
                f.write(body)
            os.replace(password_file + ".tmp", password_file)
            self.reply(200)

    def log_message(self, fmt, *args):
        sys.stderr.write("metadata: %s\n" % (fmt % args))


ThreadingHTTPServer(("127.0.0.1", int(port)), Handler).serve_forever()

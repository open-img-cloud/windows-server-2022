#!/usr/bin/env bash
# Boots a built image once with QEMU/KVM and an OpenStack config drive, and
# checks it through the QEMU guest agent:
#   1. the guest agent answers (VirtIO serial driver and QEMU-GA service);
#   2. Cloudbase-Init used the metadata server, not the config drive (each
#      gives another hostname);
#   3. the random Administrator password reached the metadata server,
#      encrypted with the instance key (nova get-password), and opens a
#      session in the guest;
#   4. C: was extended to the larger disk (ExtendVolumesPlugin).
# The image itself is never modified: the VM runs on a temporary overlay.
#
# The metadata server (scripts/metadata-server.py) listens on the host; an
# iptables rule, limited to the user of this script, redirects the
# connections of QEMU (user networking) to 169.254.169.254:80 to it. sudo
# is needed for that rule.
#
# Usage: scripts/smoke.sh IMAGE.qcow2 [bios|uefi] [timeout-minutes]
set -euo pipefail

image="${1:?usage: scripts/smoke.sh IMAGE.qcow2 [bios|uefi] [timeout-minutes]}"
firmware="${2:-bios}"
timeout_min="${3:-30}"
hostname_expected="oic-smoke"
hostname_config_drive="oic-config-drive"
metadata_port=8775

qemu_binary="$(command -v qemu-system-x86_64 || true)"
if [ -z "$qemu_binary" ] && [ -x /usr/libexec/qemu-kvm ]; then
  qemu_binary=/usr/libexec/qemu-kvm
fi
[ -n "$qemu_binary" ] || { echo "qemu-system-x86_64 not found" >&2; exit 1; }
[ -w /dev/kvm ] || { echo "/dev/kvm is not writable" >&2; exit 1; }
sudo -n iptables -t nat -S OUTPUT >/dev/null ||
  { echo "sudo iptables is needed for the metadata server" >&2; exit 1; }

work="$(mktemp -d)"
qemu_pid=""
metadata_pid=""
redirect=(-p tcp -d 169.254.169.254 --dport 80 -m owner --uid-owner "$(id -u)"
  -j REDIRECT --to-ports "$metadata_port")
cleanup() {
  status=$?
  if [ -n "$qemu_pid" ]; then kill "$qemu_pid" 2>/dev/null || true; fi
  if [ -n "$metadata_pid" ]; then
    kill "$metadata_pid" 2>/dev/null || true
    sudo -n iptables -t nat -D OUTPUT "${redirect[@]}" 2>/dev/null || true
    if [ "$status" -ne 0 ] && [ -s "$work/metadata.log" ]; then
      echo "--- metadata server requests ---"
      tail -n 30 "$work/metadata.log"
    fi
  fi
  rm -rf "$work"
}
trap cleanup EXIT

# Overlay on the image, with a disk larger than the image so that the
# volume extension can be checked.
qemu-img create -q -f qcow2 -F qcow2 -b "$(realpath "$image")" "$work/disk.qcow2" 60G

# Instance key pair (RSA, the type Cloudbase-Init encrypts with) and the
# metadata server.
ssh-keygen -q -t rsa -b 2048 -m PEM -N '' -C oic-smoke -f "$work/key"
python3 "$(dirname "$0")/metadata-server.py" "$metadata_port" "$hostname_expected" \
  "$work/key.pub" "$work/password.b64" 2>"$work/metadata.log" &
metadata_pid=$!
sudo -n iptables -t nat -A OUTPUT "${redirect[@]}"

# OpenStack config drive (label config-2), with another hostname: the
# metadata server must win, since only it can receive the password.
mkdir -p "$work/cd/openstack/latest"
cat > "$work/cd/openstack/latest/meta_data.json" <<EOF
{"uuid": "$(cat /proc/sys/kernel/random/uuid)", "hostname": "$hostname_config_drive", "name": "$hostname_config_drive"}
EOF
xorriso -as mkisofs -quiet -V config-2 -J -r -o "$work/config-2.iso" "$work/cd"

machine=(-machine pc)
if [ "$firmware" = "uefi" ]; then
  code="" vars=""
  for pair in \
    "/usr/share/OVMF/OVMF_CODE_4M.fd:/usr/share/OVMF/OVMF_VARS_4M.fd" \
    "/usr/share/OVMF/OVMF_CODE.fd:/usr/share/OVMF/OVMF_VARS.fd" \
    "/usr/share/edk2/ovmf/OVMF_CODE.fd:/usr/share/edk2/ovmf/OVMF_VARS.fd" \
    "/usr/share/edk2/x64/OVMF_CODE.4m.fd:/usr/share/edk2/x64/OVMF_VARS.4m.fd"; do
    if [ -f "${pair%%:*}" ] && [ -f "${pair##*:}" ]; then
      code="${pair%%:*}" vars="${pair##*:}"
      break
    fi
  done
  [ -n "$code" ] || { echo "OVMF firmware not found" >&2; exit 1; }
  cp "$vars" "$work/vars.fd"
  machine=(-machine q35
    -drive "if=pflash,format=raw,readonly=on,file=$code"
    -drive "if=pflash,format=raw,file=$work/vars.fd")
fi

"$qemu_binary" "${machine[@]}" -accel kvm -cpu host -smp 2 -m 4096 \
  -drive "file=$work/disk.qcow2,if=virtio,discard=unmap" \
  -drive "file=$work/config-2.iso,media=cdrom,readonly=on" \
  -nic user,model=virtio-net-pci \
  -device virtio-serial-pci \
  -chardev "socket,path=$work/qga.sock,server=on,wait=off,id=qga0" \
  -device virtserialport,chardev=qga0,name=org.qemu.guest_agent.0 \
  -display none -serial "file:$work/serial.log" &
qemu_pid=$!

# The guest agent is driven from Python (standard library only).
python3 - "$work/qga.sock" "$hostname_expected" "$timeout_min" "$work" <<'PY'
import base64, json, os, socket, subprocess, sys, time

sock_path, expected, timeout_min = sys.argv[1], sys.argv[2], int(sys.argv[3])
work = sys.argv[-1]
deadline = time.time() + timeout_min * 60


def call(cmd, args=None, wait=10):
    """One guest agent command on a fresh connection; None if no answer."""
    s = None
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(wait)
        s.connect(sock_path)
        # guest-sync flushes any stale answer left on the channel.
        token = int(time.time()) % 100000
        s.sendall(json.dumps({"execute": "guest-sync", "arguments": {"id": token}}).encode())
        buf = b""
        while True:
            buf += s.recv(65536)
            if f'"return": {token}'.encode() in buf or f'"return":{token}'.encode() in buf:
                break
        req = {"execute": cmd}
        if args:
            req["arguments"] = args
        s.sendall(json.dumps(req).encode())
        buf = b""
        while True:
            chunk = s.recv(65536)
            if not chunk:
                return None
            buf += chunk
            try:
                return json.loads(buf.decode()).get("return")
            except json.JSONDecodeError:
                continue
    except OSError:
        return None
    finally:
        if s:
            s.close()


def run(path, *args):
    """Runs a program in the guest, returns its stdout or None. Arguments go
    one by one: the guest agent quotes them, so a command line passed through
    cmd.exe /c would reach PowerShell as a quoted string, not as code."""
    r = call("guest-exec", {"path": path, "arg": list(args), "capture-output": True})
    if not r:
        return None
    for _ in range(60):
        st = call("guest-exec-status", {"pid": r["pid"]})
        if st and st.get("exited"):
            return base64.b64decode(st.get("out-data", "")).decode(errors="replace").strip()
        time.sleep(2)
    return None


start = time.time()
name = out = None
step = "guest agent"
while time.time() < deadline:
    if call("guest-ping", wait=5) is not None:
        break
    time.sleep(10)
else:
    sys.exit(f"FAIL: {step} did not answer within {timeout_min} min")
print(f"ok: guest agent answers after {int(time.time() - start)} s")

info = call("guest-get-osinfo") or {}
print(f"ok: {info.get('pretty-name', '?')} ({info.get('kernel-version', '?')})")

# Cloudbase-Init sets the hostname, then reboots the instance: wait for it.
step = "hostname from the metadata server"
while time.time() < deadline:
    name = run("hostname.exe")
    if name and name.lower() == expected:
        break
    time.sleep(15)
else:
    sys.exit(f"FAIL: {step} (last seen: {name!r})")
print(f"ok: hostname {name} from the metadata server after {int(time.time() - start)} s")

# The password posted by SetUserPasswordPlugin, decrypted with the private
# key as nova get-password does, must open an Administrator session.
step = "password posted to the metadata server"
password_file = os.path.join(work, "password.b64")
while time.time() < deadline and not os.path.exists(password_file):
    time.sleep(10)
if not os.path.exists(password_file):
    sys.exit(f"FAIL: {step}")
with open(password_file, "rb") as f:
    encrypted = base64.b64decode(f.read())
password = subprocess.run(
    ["openssl", "pkeyutl", "-decrypt", "-inkey", os.path.join(work, "key"),
     "-pkeyopt", "rsa_padding_mode:pkcs1"],
    input=encrypted, capture_output=True, check=True).stdout.decode()
print(f"ok: password of {len(password)} characters posted and decrypted")


def logon(candidate):
    """LogonUser (interactive) for Administrator in the guest, from
    PowerShell (-EncodedCommand: no quoting through the agent)."""
    secret = base64.b64encode(candidate.encode()).decode()
    script = (
        "$p=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('%s'));"
        "Add-Type -Namespace OIC -Name L -MemberDefinition '"
        "[DllImport(\"advapi32.dll\", SetLastError=true)] public static extern bool "
        "LogonUser(string u, string d, string p, int t, int v, out IntPtr h);';"
        "$h=[IntPtr]::Zero;"
        "if ([OIC.L]::LogonUser('Administrator', '.', $p, 2, 0, [ref]$h)) {'logon-ok'} "
        "else {'logon-failed ' + [Runtime.InteropServices.Marshal]::GetLastWin32Error()}"
    ) % secret
    encoded = base64.b64encode(script.encode("utf-16-le")).decode()
    return run(r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe",
               "-NoProfile", "-NonInteractive", "-EncodedCommand", encoded)


out = logon(password)
if out != "logon-ok":
    sys.exit(f"FAIL: the posted password does not open a session ({out!r})")
out = logon(password + "x")
if not (out or "").startswith("logon-failed"):
    sys.exit(f"FAIL: a wrong password was not refused ({out!r})")
print("ok: the posted password opens an Administrator session, a wrong one is refused")

step = "C: extended to the disk"
while time.time() < deadline:
    out = run("powershell.exe", "-NoProfile", "-NonInteractive", "-Command",
              "[math]::Round((Get-Partition -DriveLetter C).Size/1GB)")
    if out and out.isdigit() and int(out) >= 55:
        break
    time.sleep(15)
else:
    sys.exit(f"FAIL: {step} (C: is {out!r} GB on a 60 GB disk)")
print(f"ok: C: is {out} GB on a 60 GB disk")
PY
echo "smoke test passed"

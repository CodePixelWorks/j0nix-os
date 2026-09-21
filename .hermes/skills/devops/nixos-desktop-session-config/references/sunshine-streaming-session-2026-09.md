# Streaming Stack Session — 2026-09-08 (j0nix-os, Jonas-PC + OPNsense)

Full session detail: Sunshine discovery + latency tuning, OPNsense firewall
API automation, security wrapper capabilities. Class-level patterns extracted
into SKILL.md; this file preserves the session specifics and error transcripts.

## Sunshine discovery fix (commit 43da5a4)

Symptom: Moonlight client on laptop (Wi-Fi VLAN11) could not discover the
Sunshine host on the LAN PC.

Root cause chain:
- PC is dual-homed in the SAME L2 (bridge0 = igc1 + VLAN11 on OPNsense):
  wired enp5s0 = 172.16.2.11, wireless wlp6s0 = 172.16.2.10
- Avahi (via j0nix `lanDiscoveryInterfaces`) was announcing `_nvstream._tcp`
  on BOTH interfaces of one L2 — multi-homing breaks mDNS client discovery
  (duplicate conflicting records)
- A previous commit (083838f) had added wlp6s0 "to restore discovery", which
  actually made it worse

Fix: `lanDiscoveryInterfaces = [ "enp5s0" ]` — exactly one interface per
shared L2 announces. After Avahi restart, Sunshine must be restarted too
(user unit) or it loses its registration:
```
systemctl --user restart sunshine
```
Verification:
```
avahi-browse -rt _nvstream._tcp   # only enp5s0 entries
getent hosts Jonas-PC.local       # resolves to 172.16.2.11 (LAN IP)
```

## OPNsense firewall rule automation (commits via REST API)

The MCP server (`@richard-stovall/opnsense-mcp-server`) reads rules fine but
its mutating methods hit camelCase endpoints (`addRule`) that OPNsense 26.7
rejects — the correct endpoints use snake_case (`add_rule`).

Working recipe via REST + Basic auth (credentials from SOPS):
```
POST /api/firewall/filter/add_rule/     body: {"rule": { ...flat enums... }}
POST /api/firewall/filter/apply/        body: {}
```
Payload field format (FLAT enums, not nested objects):
```json
{"rule": {
  "enabled":"1","sequence":"592","action":"pass","quick":"1",
  "interface":"opt4","direction":"in","ipprotocol":"inet",
  "protocol":"udp","statetype":"sloppy",
  "source_net":"opt4","destination_net":"any",
  "destination_port":"47998-48002",
  "log":"1","description":"STREAM: ..."
}}
```
Gotchas:
- `ipprotocol` must be `inet`|`inet6`|`inet46` — `inet4` fails validation
- `destination_port` accepts single range `47984-48010` but NOT mixed lists
  like `47984-47990,48010`
- Rules land under `OPNsense/Firewall/Filter` in config.xml, NOT the legacy
  `<filter>` section (backup parsing must check the new location)
- `filterBaseSavepoint` endpoint does not exist on 26.7 (404) — rollback by
  deleting added rules via `del_rule/<uuid>`

Streaming rule set (seq 592-595 on opt4, 882-883 on opt7):
- UDP media: `sloppy` state on client ingress (max PPS, less state tracking)
- TCP control: `keep` state
- opt7 (PC→WLAN media return): `no state` — survives state-table flushes
- IPv6 link-local (`fe80::/10`) variants for both directions as fallback path

## security.wrappers capability string (commit 3642a62 + 8c0a2b5)

Symptom: `EGL: context priority set to HIGH but CAP_SYS_NICE capability is
missing` from Sunshine; then after first fix attempt, the ENTIRE
`suid-sgid-wrappers.service` failed with `fatal error: Invalid argument` and
/run/wrappers/bin/sunshine was missing.

Root cause: `cap_from_text` accepts only ONE flag group per string.
`"cap_sys_admin+p,cap_sys_nice+p"` → Invalid Argument (setcap rejects it).
Verified in an unprivileged user namespace:
```
unshare -r -U bash -c 'setcap "cap_sys_admin+p,cap_sys_nice+p" /tmp/f'   # FAILS
unshare -r -U bash -c 'setcap "cap_sys_admin,cap_sys_nice+p" /tmp/f'     # OK
```
Correct form: `"cap_sys_admin,cap_sys_nice+p"` (shared single flag group).

Verification of the running process (Sunshine drops privileges but keeps
caps in the Ambient set):
```
SPID=$(pgrep -f "bin/sunshine" | head -1)
grep CapPrm /proc/$SPID/status    # bit 23 = CAP_SYS_NICE
journalctl --user -u sunshine | grep "EGL: context priority"
# expect: "EGL: context priority set to HIGH" without the warning
```

## NVENC API version gate (commit a7b1c48)

Sunshine 2026.906's ffmpeg requires NVENC API 13.1 = driver 610+. NVIDIA
production branch 595.84 exposes only 13.0:
```
Error: [h264_nvenc] Driver does not support the required nvenc API version.
       Required: 13.1 Found: 13.0
Error: The minimum required Nvidia driver for nvenc is 610.00 or newer
→ fallback "Found H.264 encoder: libx264 [software]"
```
Fix: `settings.drivers.nvidia.package = "latest"` (610.43.03 in the flake's
nixpkgs snapshot).

⚠️ KMD/UMD mismatch after switch: kernel module still 595.84 until reboot
(`/proc/driver/nvidia/version` shows NVRM 595.84, `nvidia-smi` shows NVRM
595.84 + UMD 610.43.03). NVENC stays broken until reboot. Verify after reboot
that the journal reports `h264_nvenc` instead of `libx264 [software]`.

## Config-sequence learning

The repo has layered config: `settings.nix` (host-generic toggles) →
`profiles/desktop/modules/*.nix` (host-specific data, defaults from settings
via `or`-fallbacks). When changing a driver branch or streaming behavior,
check BOTH layers: `settings.nix` sets `drivers.nvidia.package`, while
`profiles/desktop/modules/drivers.nix` mirrors it with `or`-fallbacks —
a change in one without the other can silently keep the old value.

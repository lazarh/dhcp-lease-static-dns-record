# dhcp-lease-static-dns-record

MikroTik RouterOS v7 DHCP lease script that automatically creates and removes
static DNS A-records whenever a client receives or releases a lease.

---

## Problem it solves

MikroTik's DHCP server can run a script on every lease event, but two common
problems prevent a naïve implementation from working:

1. **Empty `leaseHostName`** – Many clients never send DHCP option 12, so the
   hostname variable is always empty.
2. **Empty `leaseClientMac`** – On some RouterOS v7 builds the MAC-address
   environment variable is not populated (confirmed in logs showing `MAC=`).

Both issues are addressed in [`dhcp-lease-dns.rsc`](dhcp-lease-dns.rsc).

---

## Features

| Feature | Detail |
|---|---|
| Hostname from client | Uses DHCP option 12 when the client provides it |
| MAC-address fallback | Falls back to `dev-AABBCC` (first 3 MAC octets) when no hostname |
| Lease-table MAC lookup | When `leaseClientMac` env var is empty, reads the MAC from `/ip dhcp-server lease` |
| Last-resort name | Uses `dev-<last-IP-octet>` if MAC is also unavailable |
| Hostname sanitisation | Strips characters that are invalid in DNS labels; converts to lower-case |
| Stale-record cleanup | Removes any previous record for the same IP **or** FQDN before adding the new one |
| Lease release | Removes the record when the lease is released (`leaseBound=0`) |

---

## Quick start

1. Open **Winbox / WebFig** → **IP → DHCP Server**.
2. Double-click your DHCP server entry.
3. Open the **"Lease Script"** tab (or field).
4. Paste the entire contents of [`dhcp-lease-dns.rsc`](dhcp-lease-dns.rsc).
5. Change the `topdomain` variable at the top to match your local domain, e.g.
   ```
   :local topdomain "home.local"
   ```
6. Click **Apply / OK**.

### CLI alternative

```rsc
/ip dhcp-server set <server-name> \
    lease-script=[/file get [find name=dhcp-lease-dns.rsc] contents]
```

Or paste the script inline:

```rsc
/ip dhcp-server set defconf lease-script="..."
```

---

## How it works

```
DHCP event
    │
    ├─ leaseBound=0 ──► remove A-record for that IP ──► done
    │
    └─ leaseBound=1
            │
            ├─ resolve MAC (env var → lease table → warning)
            │
            ├─ pick hostname
            │       ├─ leaseHostName (if non-empty)
            │       └─ dev-AABBCC   (first 3 octets of MAC)
            │
            ├─ sanitise: keep [a-zA-Z0-9-], lowercase, strip leading/trailing hyphens
            │
            └─ register: remove stale records, add new A-record
                         name=<hostname>.<topdomain> address=<leasedIP>
                         comment="DHCP-Auto" ttl=10m
```

---

## Log output

Successful bind:
```
DHCP-DNS: Bound=1 IP=192.168.88.50 MAC=AA:BB:CC:DD:EE:FF Host=mylaptop Server=defconf
DHCP-DNS: Added mylaptop.house.local -> 192.168.88.50
```

No hostname (MAC fallback):
```
DHCP-DNS: Bound=1 IP=192.168.88.51 MAC=AA:BB:CC:DD:EE:FF Host= Server=defconf
DHCP-DNS: No hostname from 192.168.88.51, using fallback: dev-aabbcc
DHCP-DNS: Added dev-aabbcc.house.local -> 192.168.88.51
```

Release:
```
DHCP-DNS: Bound=0 IP=192.168.88.50 MAC= Host= Server=defconf
DHCP-DNS: Removed DNS record for 192.168.88.50
```

---

## Requirements

* RouterOS **v7.x** (tested against v7.20)
* `:tolower` built-in — available in RouterOS v7
* Script permissions: the DHCP server runs the lease script under the
  `full` policy by default; no extra configuration needed.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Host=` and `MAC=` both empty on bind | RouterOS is not populating env vars | Script already falls back to lease table for MAC |
| DNS record created as `dev-.house.local` | Empty MAC AND lease table lookup failed | Check `/ip dhcp-server lease print` while lease is active |
| Record not removed on release | Client released before script ran, or script error | Check `/log print` for `DHCP-DNS:` entries |
| Hostname contains spaces/special chars | Some clients send option 12 with odd characters | Sanitisation step replaces them with `-` |

# dhcp-lease-static-dns-record

MikroTik RouterOS DHCP lease script that automatically creates and removes
static DNS A-records whenever a client receives or releases a lease.

---

## Problem it solves

MikroTik's DHCP server can run a script on every lease event, but two common
problems prevent a naïve implementation from working:

1. **Empty `leaseHostName`** – Many clients never send DHCP option 12, so the
   hostname variable is always empty.
2. **Empty `leaseClientMac`** – On some RouterOS builds the MAC-address
   environment variable is not populated (confirmed in logs showing `MAC=`).

Both issues are addressed in [`dhcp-lease-dns.rsc`](dhcp-lease-dns.rsc).

---

## Features

| Feature | Detail |
|---|---|
| Hostname from client | Uses DHCP option 12 when the client provides it |
| MAC-address fallback | Falls back to `dev-AABBCC` (first 3 MAC octets) when no hostname, lowercased to `dev-aabbcc` in the final DNS record |
| Lease-table MAC lookup | When `leaseClientMac` env var is empty, reads the MAC from `/ip dhcp-server lease` |
| Last-resort name | Uses `dev-<last-IP-octet>` if MAC is also unavailable |
| Hostname sanitisation | Strips characters that are invalid in DNS labels; converts to lower-case |
| Stale-record cleanup | Removes any previous record for the same IP **or** FQDN before adding the new one |
| Lease release | Removes the record when the lease is released (`leaseBound=0`) |

---

## Setup (recommended — named script approach)

The cleanest way to deploy is to store the script in RouterOS's script
repository (`/system script`) and reference it by name from the DHCP
server.  This avoids all inline-escaping problems and script-length limits
that appear when the script is pasted directly into the `lease-script` field.

### Step 1 — customise the domain

Edit the first line of `dhcp-lease-dns.rsc` to match your local domain:

```rsc
:local topdomain "home.local"
```

### Step 2 — upload the script to the router

**Via Winbox / WebFig file manager**

1. Upload `dhcp-lease-dns.rsc` to the router's file system (drag-and-drop in
   the **Files** window, or use FTP/SCP/SFTP).
2. In a terminal, import it as a named script:

```rsc
/system script add name=dhcp-lease-dns \
    source=[/file get [find name="dhcp-lease-dns.rsc"] contents]
```

**Via SSH / CLI directly**

Paste the file contents as the `source` parameter:

```rsc
/system script add name=dhcp-lease-dns policy=read,write,test source="<paste full contents here>"
```

### Step 3 — point the DHCP server at the script

```rsc
/ip dhcp-server set defconf lease-script="/system script run dhcp-lease-dns"
```

Replace `defconf` with the name of your DHCP server entry.

---

## Setup (alternative — inline paste)

If you prefer not to use a named script, paste the entire contents of
`dhcp-lease-dns.rsc` directly into the **Lease Script** field in Winbox /
WebFig → **IP → DHCP Server** → double-click your server → **Lease Script**
tab.

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
            │       └─ dev-AABBCC   (first 3 octets of MAC, lowercased to dev-aabbcc)
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
DHCP-DNS: No hostname from 192.168.88.51, using fallback: dev-AABBCC
DHCP-DNS: Added dev-aabbcc.house.local -> 192.168.88.51
```

Release:
```
DHCP-DNS: Bound=0 IP=192.168.88.50 MAC= Host= Server=defconf
DHCP-DNS: Removed DNS record for 192.168.88.50
```

---

## Requirements

* RouterOS **v6.x or v7.x**
* Script permissions: the DHCP server runs the lease script under the
  `full` policy by default; no extra configuration needed.
* No external commands are used — in particular, `:tolower` is **not** required
  (case conversion is done with a built-in character loop).

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Host=` and `MAC=` both empty on bind | RouterOS is not populating env vars | Script already falls back to lease table for MAC |
| DNS record created as `dev-.house.local` | Empty MAC AND lease table lookup failed | Check `/ip dhcp-server lease print` while lease is active |
| Record not removed on release | Client released before script ran, or script error | Check `/log print` for `DHCP-DNS:` entries |
| Hostname contains spaces/special chars | Some clients send option 12 with odd characters | Sanitisation step replaces them with `-` |


# dhcp-lease-static-dns-record

MikroTik RouterOS DHCP lease script that automatically creates and removes
static DNS A-records whenever a client receives or releases a lease.

---

## Problem it solves

MikroTik's DHCP server can run a script on every lease event, but the built-in
lease variables (`$leaseActIP`, `$leaseBound`, etc.) are only available when
the script content is executed **directly** inside the `lease-script` field.
If `lease-script` is set to `/system script run <name>`, RouterOS runs the
named script in its own isolated context and those variables are **not**
passed through — they are all empty, so any script that relies on them silently
fails.

[`dhcp-lease-dns.rsc`](dhcp-lease-dns.rsc) avoids this entirely by reading
from the DHCP lease table directly (inspired by
[MichaelPaddon/routeros-scripts](https://github.com/MichaelPaddon/routeros-scripts)).
It never touches the event environment variables, so it works correctly when
called via `/system script run`, inline, or from a scheduler.

---

## Features

| Feature | Detail |
|---|---|
| No env-var dependency | Reads `/ip dhcp-server lease` directly — works via `/system script run` or inline |
| Hostname from client | Uses the `host-name` field from the lease (DHCP option 12) when present |
| MAC-address fallback | Falls back to `dev-aabbcc` (first 3 MAC octets, lowercased) when no hostname |
| Last-resort name | Uses `dev-<last-IP-octet>` if MAC is also unavailable |
| Hostname sanitisation | Strips characters that are invalid in DNS labels; converts to lower-case |
| Stale-record cleanup | Removes any previous auto-record for the same IP or FQDN before adding |
| Expired-lease cleanup | Removes DNS records for leases no longer in the DHCP lease table |
| Manual-record safety | Never overwrites a DNS record that was not created by this script |

---

## Setup

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

### Step 4 (optional) — add a periodic sync job

Lease releases remove the DNS record on the next event. To guarantee cleanup
even when no further events occur, add a scheduler entry:

```rsc
/system scheduler add name=dhcp-dns-sync interval=5m \
    on-event="/system script run dhcp-lease-dns"
```

---

## Setup (alternative — inline paste)

If you prefer not to use a named script, paste the entire contents of
`dhcp-lease-dns.rsc` directly into the **Lease Script** field in Winbox /
WebFig → **IP → DHCP Server** → double-click your server → **Lease Script**
tab.

---

## How it works

```
DHCP event (or scheduler tick)
    │
    └─ read all entries from /ip dhcp-server lease
            │
            ├─ for each lease: derive FQDN
            │       ├─ host-name field (if non-empty)
            │       └─ dev-aabbcc (first 3 octets of MAC, lowercased)
            │
            ├─ sanitise: keep [a-zA-Z0-9-], lowercase, strip leading/trailing hyphens
            │
            ├─ add/update A-record for each lease
            │       comment="DHCP-Auto"  ttl=10m
            │       (skips names that already have a manually-created record)
            │
            └─ remove any "DHCP-Auto" records with no matching lease
```

---

## Log output

New lease assigned:
```
DHCP-DNS: Starting sync
DHCP-DNS: Add mylaptop.house.local -> 192.168.88.50
DHCP-DNS: Sync complete
```

No hostname (MAC fallback):
```
DHCP-DNS: Starting sync
DHCP-DNS: Add dev-aabbcc.house.local -> 192.168.88.51
DHCP-DNS: Sync complete
```

Lease released / expired:
```
DHCP-DNS: Starting sync
DHCP-DNS: Remove mylaptop.house.local
DHCP-DNS: Sync complete
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
| All vars empty (`Bound= IP= MAC=`) in old logs | Old version depended on DHCP env vars; `/system script run` does not pass them | Update to current version which reads the lease table directly |
| DNS record not added after a bind event | Lease is in the table but sanitised hostname is empty | Check `/ip dhcp-server lease print` — does the lease have an address and MAC? |
| Record not removed immediately on release | Lease still present in table when script runs | Run the script via scheduler every 5 minutes (Step 4) for guaranteed cleanup |
| Hostname contains spaces/special chars | Some clients send option 12 with odd characters | Sanitisation step replaces them with `-` |
| A manually-created DNS record is not overwritten | By design — script only manages records tagged `comment=DHCP-Auto` | Remove the manual record if you want the script to manage it |


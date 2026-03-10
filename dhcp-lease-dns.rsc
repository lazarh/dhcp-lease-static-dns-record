# MikroTik RouterOS v7 DHCP Lease Script — Auto DNS static record management
#
# How it works:
#   - On lease bound  (leaseBound=1): removes any stale record for the IP or FQDN,
#     then adds a new A-record with comment "DHCP-Auto".
#   - On lease release (leaseBound=0): removes the A-record for that IP.
#
# Hostname priority:
#   1. leaseHostName   (DHCP option 12 sent by the client)
#   2. MAC-based name  "dev-AABBCC" (first 3 octets of the MAC address)
#      The MAC is read from the leaseClientMac environment variable; if it is
#      empty (which can happen on some RouterOS builds) the active-mac-address
#      is looked up directly from the DHCP lease table.
#
# Sanitisation:
#   - The hostname is converted to lower-case.
#   - Characters that are not letters, digits or hyphens are replaced with "-".
#   - Leading/trailing hyphens are stripped.
#
# Usage:
#   Paste this script into the "Lease Script" field of your DHCP server
#   (IP → DHCP Server → <server> → Lease Script) and set topdomain below.

# ── Configuration ────────────────────────────────────────────────────────────
:local topdomain "house.local"
# ─────────────────────────────────────────────────────────────────────────────

# Collect the environment variables injected by the DHCP server
:local lIP      $leaseActIP
:local lHost    $leaseHostName
:local lBound   $leaseBound
# leaseClientMac format: "AA:BB:CC:DD:EE:FF" (upper-case, colon-separated)
:local lMac     $leaseClientMac
:local lServer  $leaseServerName

:log info "DHCP-DNS: Bound=$lBound IP=$lIP MAC=$lMac Host=$lHost Server=$lServer"

# Pre-compute a last-resort name from the last IP octet (e.g. "dev-50").
# Used in two places below, so defined once here.
:local ipOctets    [:toarray [:tostr $lIP] delimiter="."]
:local lastResort  ("dev-" . ($ipOctets->3))

# ── Lease release ─────────────────────────────────────────────────────────────
:if ($lBound = 0) do={
    /ip dns static remove [/ip dns static find where address=$lIP comment="DHCP-Auto"]
    :log info "DHCP-DNS: Removed DNS record for $lIP"
    :return
}

# ── Lease bound ───────────────────────────────────────────────────────────────

# --- Step 1: resolve the MAC address ----------------------------------------
# leaseClientMac can be empty on some RouterOS v7 builds; fall back to the
# lease table so we always have a MAC to generate a fallback hostname.
:if ([:len $lMac] = 0) do={
    :do {
        :set lMac [/ip dhcp-server lease get \
            [/ip dhcp-server lease find where active-address=$lIP] \
            active-mac-address]
    } on-error={
        :log warning "DHCP-DNS: Cannot resolve MAC for $lIP from lease table"
    }
}

# --- Step 2: build the hostname ----------------------------------------------
:local finalHost ""

:if ([:len $lHost] > 0) do={
    # Use the hostname supplied by the client (sanitised below)
    :set finalHost $lHost
} else={
    # Build a stable name from the first three MAC octets: dev-AABBCC
    # Requires MAC in "AA:BB:CC:DD:EE:FF" format (indices 0-2, 3-5, 6-8).
    :if ([:len $lMac] >= 8) do={
        :set finalHost ("dev-" . [:pick $lMac 0 2] . [:pick $lMac 3 5] . [:pick $lMac 6 8])
    } else={
        # Last-resort: use the last octet of the IP address
        :set finalHost $lastResort
        :log warning "DHCP-DNS: No MAC for $lIP, using last-resort name: $finalHost"
    }
    :log info "DHCP-DNS: No hostname from $lIP, using fallback: $finalHost"
}

# --- Step 3: sanitise the hostname ------------------------------------------
# RouterOS does not have a native regex replace, so we iterate character-by-
# character and keep only [a-zA-Z0-9-].
:local safe     ""
:local allowed  "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-"
:local hostLen  [:len $finalHost]
:for i from=0 to=($hostLen - 1) do={
    :local ch [:pick $finalHost $i ($i + 1)]
    :if ([:find $allowed $ch] >= 0) do={
        :set safe ($safe . $ch)
    } else={
        :set safe ($safe . "-")
    }
}

# Strip leading hyphens
:while ([:len $safe] > 0 && [:pick $safe 0 1] = "-") do={
    :set safe [:pick $safe 1 [:len $safe]]
}
# Strip trailing hyphens
:while ([:len $safe] > 0 && [:pick $safe ([:len $safe] - 1) [:len $safe]] = "-") do={
    :set safe [:pick $safe 0 ([:len $safe] - 1)]
}

# Guard against an empty result after sanitisation
:if ([:len $safe] = 0) do={
    :set safe $lastResort
    :log warning "DHCP-DNS: Sanitised hostname is empty for $lIP, using $safe"
}

# Convert to lower-case (RouterOS v7 supports :tolower)
:set safe [:tolower $safe]

# --- Step 4: register the DNS record ----------------------------------------
:local fqdn ($safe . "." . $topdomain)

/ip dns static remove [/ip dns static find where name=$fqdn]
/ip dns static remove [/ip dns static find where address=$lIP comment="DHCP-Auto"]
/ip dns static add name=$fqdn address=$lIP comment="DHCP-Auto" ttl=00:10:00

:log info "DHCP-DNS: Added $fqdn -> $lIP"

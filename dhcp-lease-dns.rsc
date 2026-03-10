:local topdomain "house.local"

:local lIP      $leaseActIP
:local lHost    $leaseHostName
:local lBound   $leaseBound
:local lMac     $leaseClientMac
:local lServer  $leaseServerName

:log info "DHCP-DNS: Bound=$lBound IP=$lIP MAC=$lMac Host=$lHost Server=$lServer"

:local ipStr    [:tostr $lIP]
:local d1       [:find $ipStr "."]
:local d2       [:find $ipStr "." ($d1 + 1)]
:local d3       [:find $ipStr "." ($d2 + 1)]
:local lastResort ("dev-" . [:pick $ipStr ($d3 + 1)])

:if ($lBound = 0) do={
    :local recRelease [/ip dns static find where address=$lIP comment="DHCP-Auto"]
    :if ([:len $recRelease] > 0) do={
        /ip dns static remove $recRelease
    }
    :log info "DHCP-DNS: Removed DNS record for $lIP"
} else={
    :if ([:len $lMac] = 0) do={
        :do {
            :set lMac [/ip dhcp-server lease get \
                [/ip dhcp-server lease find where active-address=$lIP] \
                active-mac-address]
        } on-error={
            :log warning "DHCP-DNS: Cannot resolve MAC for $lIP from lease table"
        }
    }

    :local finalHost ""

    :if ([:len $lHost] > 0) do={
        :set finalHost $lHost
    } else={
        :if ([:len $lMac] >= 8) do={
            :set finalHost ("dev-" . [:pick $lMac 0 2] . [:pick $lMac 3 5] . [:pick $lMac 6 8])
        } else={
            :set finalHost $lastResort
            :log warning "DHCP-DNS: No MAC for $lIP, using last-resort name: $finalHost"
        }
        :log info "DHCP-DNS: No hostname from $lIP, using fallback: $finalHost"
    }

    :local safe     ""
    :local allowed  "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-"
    :local hostLen  [:len $finalHost]
    :if ($hostLen >= 1) do={
        :for i from=0 to=($hostLen - 1) do={
            :local ch [:pick $finalHost $i ($i + 1)]
            :if ([:find $allowed $ch] >= 0) do={
                :set safe ($safe . $ch)
            } else={
                :set safe ($safe . "-")
            }
        }
    }

    :while ([:len $safe] > 0 && [:pick $safe 0 1] = "-") do={
        :set safe [:pick $safe 1 [:len $safe]]
    }
    :while ([:len $safe] > 0 && [:pick $safe ([:len $safe] - 1) [:len $safe]] = "-") do={
        :set safe [:pick $safe 0 ([:len $safe] - 1)]
    }

    :if ([:len $safe] = 0) do={
        :set safe $lastResort
        :log warning "DHCP-DNS: Sanitised hostname is empty for $lIP, using $safe"
    }

    :local upper "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    :local lower "abcdefghijklmnopqrstuvwxyz"
    :local safeLen [:len $safe]
    :local safeLower ""
    :for i from=0 to=($safeLen - 1) do={
        :local ch [:pick $safe $i ($i + 1)]
        :local pos [:find $upper $ch]
        :if ($pos >= 0) do={
            :set safeLower ($safeLower . [:pick $lower $pos ($pos + 1)])
        } else={
            :set safeLower ($safeLower . $ch)
        }
    }
    :set safe $safeLower

    :local fqdn ($safe . "." . $topdomain)

    :local recFqdn [/ip dns static find where name=$fqdn]
    :if ([:len $recFqdn] > 0) do={
        /ip dns static remove $recFqdn
    }
    :local recIP [/ip dns static find where address=$lIP comment="DHCP-Auto"]
    :if ([:len $recIP] > 0) do={
        /ip dns static remove $recIP
    }
    /ip dns static add name=$fqdn address=$lIP comment="DHCP-Auto" ttl=00:10:00

    :log info "DHCP-DNS: Added $fqdn -> $lIP"
}

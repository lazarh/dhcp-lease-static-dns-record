:local topdomain "house.local"
:local magic    "DHCP-Auto"
:local ttl      00:10:00

:log info "DHCP-DNS: Starting sync"

:local desired [:toarray ""]

/ip dhcp-server lease
:foreach lease in=[find] do={
    :local lIP   [get value-name=address $lease]
    :local lHost [get value-name=host-name $lease]
    :local lMac  [get value-name=mac-address $lease]

    :local ipStr    [:tostr $lIP]
    :local d1       [:find $ipStr "."]
    :local d2       [:find $ipStr "." ($d1 + 1)]
    :local d3       [:find $ipStr "." ($d2 + 1)]
    :local lastResort ("dev-" . [:pick $ipStr ($d3 + 1)])

    :local finalHost ""
    :if ([:len $lHost] > 0) do={
        :set finalHost $lHost
    } else={
        :if ([:len $lMac] >= 8) do={
            :set finalHost ("dev-" . [:pick $lMac 0 2] . [:pick $lMac 3 5] . [:pick $lMac 6 8])
            :log info "DHCP-DNS: $lIP no hostname, using MAC fallback: $finalHost"
        } else={
            :set finalHost $lastResort
            :log warning "DHCP-DNS: $lIP no hostname or MAC, using last-resort: $finalHost"
        }
    }

    :local safe    ""
    :local allowed "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-"
    :local hostLen [:len $finalHost]
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
        :log warning "DHCP-DNS: $lIP sanitised hostname empty, using last-resort: $safe"
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

    :if ([:len $safe] > 0) do={
        :local fqdn ($safe . "." . $topdomain)
        :set ($desired->$fqdn) $lIP
    }
}

:foreach fqdn,lIP in=$desired do={
    :if ([:len [/ip dns static find where name=$fqdn address=$lIP comment=$magic]] = 0) do={
        :foreach entry in=[/ip dns static find where name=$fqdn comment=$magic] do={
            /ip dns static remove $entry
        }
        :foreach entry in=[/ip dns static find where address=$lIP comment=$magic] do={
            /ip dns static remove $entry
        }
        :if ([:len [/ip dns static find where name=$fqdn]] = 0) do={
            :log info "DHCP-DNS: Add $fqdn -> $lIP"
            /ip dns static add name=$fqdn address=$lIP comment=$magic ttl=$ttl
        }
    }
}

/ip dns static
:foreach entry in=[find where comment=$magic] do={
    :local fqdn [get value-name=name $entry]
    :if ([:len ($desired->$fqdn)] = 0) do={
        :log info "DHCP-DNS: Remove $fqdn"
        remove $entry
    }
}

:log info "DHCP-DNS: Sync complete"

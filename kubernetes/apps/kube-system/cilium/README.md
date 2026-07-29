# Cilium

## L2 Announcements

UDR7 does not support BGP. Cilium uses L2 announcements (ARP) instead.

LoadBalancer IPs from pool `10.10.4.224/27` are announced via ARP on interface `ens18` (VLAN 4 / infra).

No router configuration is required — the router learns the MAC address of the announcing node via ARP automatically.

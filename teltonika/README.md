
# Packages

## AdguardHome

Follow instructions at https://openwrt.org/docs/guide-user/services/dns/adguard-home

## Tailscale (as exit node)

Install the appropriate packages

```bash
opkg update
opkg install tailscale
uci commit tailscale
```

Start the service and authenticate

```bash
tailscale up --advertise-exit-node
```

Configure firewall rules as follows

```
Enable_TAILSCALE_ADMIN
ANY TCP
From IPs 100.118.xxx.xxx, 100.118.yyy.yyy, 100.116.zzz.zz in any zone
To any router IP at port 22, 80 this device
```

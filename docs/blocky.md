# Blocky on ix: home LAN and Tailscale

The configuration is `machines/ix/dns.nix` in ix's checkout at
`/home/amunoz/.local/share/src/nixos-config` (branch `feat/ix-arm-emulation`).

## Server endpoints

- Home Ethernet LAN: `192.168.1.162:53`, UDP and TCP.
- Existing Tailscale endpoint: `100.114.49.10:53`, UDP and TCP.
- Management API: `127.0.0.1:4000` only.

The LAN firewall rules accept only IPv4 traffic arriving on `end0` from
`192.168.1.0/24`, addressed to `192.168.1.162`. DNS is not opened globally or
on public IPv6. The existing Tailscale permissions are unchanged. Adding a
listener does not change client DNS or Tailscale's administrative DNS settings.

## Blocklists and private policy

The public `ads` group combines
[StevenBlack](https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts)
and [HaGeZi Multi NORMAL](https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/multi.txt).
HaGeZi uses the wildcard format recommended for Blocky 0.23+. Sources refresh
on Blocky's default schedule. These policies also apply to clients connecting
directly over Tailscale; no tailnet-wide DNS setting is changed.

Additional private policy is encrypted in `secrets/blocky-private.yaml.age`.
Recipients are the personal recovery key and ix's SSH host key, registered in
`secrets/secrets.nix`. Agenix decrypts it as root with mode `0400` at activation;
systemd supplies it to Blocky's dynamic user through `LoadCredential`.
Blocky merges `00-public.yaml` and `10-private.yaml` in its service-private
credential directory. The public config is validated during the build, and
the merged config is validated before the service starts. Secret updates
trigger a service restart. A missing or invalid private overlay prevents
startup rather than silently bypassing its policy.

Edit the encrypted overlay with agenix from the `secrets` directory using an
authorized identity. Include the full intended `clientGroupsBlock.default`
list: arrays replace, rather than append to, the public values. Plaintext
scratch copies at the documented private filenames are gitignored; do not
commit plaintext elsewhere or put it into Nix expressions. Do not edit the
generated read-only configuration in `/nix/store`.

Encryption keeps the private source URL and policy out of the readable
repository and newly generated public configuration. It does not hide them
from root, the Blocky service, or administrators reading service logs. Earlier
test generations, Nix-store source snapshots, and logs may still contain the
previous plaintext settings; they are not automatically erased.

No filter is exhaustive. Report false positives so individual domains can be
reviewed rather than disabling all filtering. Router and client DNS caches
can retain pre-change answers until they expire.

The Home Assistant integration remains deferred. No custom integration,
statistics collection, or Prometheus endpoint was enabled.

## Verizon router setup — DNS forwarding verified

The router at <https://192.168.1.1/> serves a CR1000A-family management UI.
Keep the admin password private; make authenticated changes in the browser.
See the [Verizon router guide](https://www.verizon.com/supportresources/content/dam/verizon/support/consumer/documents/internet/verizon-router-guide.pdf).

1. Record the current DNS settings so they can be restored if needed.
2. Reserve ix's Ethernet DHCP lease before making it a DNS dependency:
   **Advanced → Network Settings → IPv4 Address Distribution → Connection
   List**. Edit the existing ix lease or add a static connection:
   - Host: `ix`
   - Address: `192.168.1.162`
   - Ethernet MAC: `dc:a6:32:c2:0b:8b`
   Leave the router's own address, subnet, and DHCP service unchanged.
3. On the observed firmware, use **Advanced → Network Settings → Network
   Connections → Broadband Connection (Ethernet) → Edit/Settings**. Leave
   **Obtain IPv4 Address Automatically** and the Internet Connection Firewall
   enabled. Set **IPv4 DNS** to **Use the Following IPv4 DNS Addresses**:
   address 1 is `192.168.1.162`; unused address 2 displays `0.0.0.0`.
   The owner applied these settings. The sidebar's **DNS Server** page manages
   local host records, not this forwarding setting. Do not add a public
   secondary resolver: it could bypass filtering.
4. **Keep IPv6 enabled with the verified router-proxy setup.** Clients still
   use the router's IPv4 and IPv6 addresses for DNS. Fresh, uniquely named
   test queries sent to each address were both logged by Blocky with source
   `192.168.1.1`: the router forwards both transports to ix over IPv4.
   Blocked A/AAAA answers and normal resolution were verified through the
   router, including its IPv6 listener. No separate LAN IPv6 listener on ix
   or IPv6 shutdown was needed. Recheck after firmware/DNS changes; do not
   assume that all future router configurations preserve this behavior.
5. Apply the chosen router settings, renew a test client's DHCP lease/reconnect
   its Wi-Fi, and test the default resolver path as well as direct queries.
   Clients may still show the router as DNS if it proxies queries to ix.

Router-wide DNS affects clients using that router's advertised DNS, including
other people's devices on that LAN. Guest networks may have separate settings.
Hardcoded DNS, browser DoH, VPNs, and Private Relay can bypass it. This does not
change tailnet-wide DNS policy. If ix is offline, clients depending on it may
lose DNS; revert the router DNS settings to automatic to recover.

## Verification

From a LAN client:

```sh
dig @192.168.1.162 example.com A
dig @192.168.1.162 doubleclick.net A       # Expect 0.0.0.0
dig @192.168.1.162 doubleclick.net AAAA    # Expect ::
dig @192.168.1.162 example.com A +tcp
```

The same tests should still work against `100.114.49.10` from an authorized
Tailscale client. On ix, inspect `systemctl status blocky` and
`ss -lnut '( sport = :53 or sport = :4000 )'`.

After the router change, also verify the normal client resolver. On macOS:

```sh
scutil --dns
dscacheutil -q host -a name doubleclick.net
```

The native lookup should show blocked addresses, not public addresses. Check
IPv4 and IPv6 paths; `dig @192.168.1.162` alone only tests the server directly.

## Deployment evidence

The baseline checkout evaluated to the running system before editing. The
updated system built successfully with Blocky's native config validation.
Activation preview changed only `blocky.service` and `firewall.service`.
Runtime tests from a LAN Mac passed normal DNS and A/AAAA ad blocking over both
UDP and TCP, on both the LAN and Tailscale endpoints. The API remained
loopback-only; Home Assistant and Tailscale stayed active.

After the owner applied the router DNS settings, direct tests through both
router addresses and the native macOS resolver confirmed ad blocking. The
router returns empty answers for these blocked queries, while direct Blocky
queries return `0.0.0.0` / `::`. Normal DNS continued working. Unique test
names in Blocky's logs confirmed forwarding from both router DNS transports.

The private-policy update passed public build validation, root-only decryption,
merged runtime validation, and DNS tests on both direct listeners and both
router DNS transports. Normal DNS, public filtering, and private filtering
continued working. The ordinary login user cannot read either runtime secret
path, and the private source/category does not appear in the current readable
config/docs. Home Assistant was not restarted.

**The DHCP reservation still needs owner confirmation.** No router credentials
were collected, and no Tailscale administrative settings were changed.

## Tailscale interruption — 2026-09-29 UTC

Read-only journal inspection found an Ethernet carrier loss on ix, not a
Tailscale daemon crash:

- `01:31:22`: the kernel reported `end0: Link is Down`; dhcpcd removed its
  addresses and routes. Tailscale then paused because all underlying links
  were down, with a transient DNS configuration error.
- `01:31:24`: the Ethernet link returned at 1 Gbit/s.
- `01:31:26–28`: IPv6 routing returned, the DNS error cleared, and Tailscale
  reconnected to its relay.
- `01:31:34`: dhcpcd restored `192.168.1.162` and the IPv4 default route.

The physical cause (cable, router/switch port, or Ethernet hardware/driver)
was not established. At inspection, tailscaled had been running continuously
since September 28 at 15:42:17 UTC, with backend state `Running` and no health
warnings. Restarting Tailscale or weakening DNS filtering is not supported by
this evidence; investigate the Ethernet path if carrier losses recur.

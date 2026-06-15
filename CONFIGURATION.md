# Configuration guide

A step-by-step walkthrough for configuring `coredns-fanout` from a user's point
of view: from a single-machine cache to a full resolver for your home network,
with parallel encrypted upstreams, domain filtering, and automatic filter-list
updates.

This guide focuses on *how to configure your own setup*. For the exhaustive
syntax of each component, follow the upstream links:

| Component | What it does | Reference |
|-----------|--------------|-----------|
| **CoreDNS** | The DNS server itself; everything is configured in a `Corefile`. | <https://coredns.io/manual/toc/> |
| **fanout** (TomTonic fork) | Sends each query to several upstream resolvers in parallel. | <https://github.com/TomTonic/fanout> |
| **filterlist** | Blocks domains using denylists/allowlists (AdGuard/EasyList/hosts formats). | <https://github.com/TomTonic/filterlist> |
| **websyncd** | Small daemon that keeps each filter-list file in sync with its remote URL. | <https://github.com/TomTonic/websyncd> |

> All addresses, domain names, and provider IDs in this guide are **examples**.
> Replace them with your own values.

---

## Overview: which files you edit

A working deployment is just three things in one directory:

```
my-dns/
├── docker-compose.yml     # which containers run (CoreDNS + optional updaters)
├── Corefile               # how CoreDNS behaves (filtering, fanout, cache, ...)
└── denylists/             # filter-list files, mounted into the container
    ├── adguard-filter.txt
    └── ...
```

- The **Corefile** is where you spend most of your time.
- The **docker-compose.yml** decides how the container is networked and which
  filter-list updater services run.
- The **denylists/** directory is mounted read-only into CoreDNS at
  `/etc/coredns/denylist.d` and is filled (and refreshed) by the updater
  services.

---

## Step 1 — Get the example files

```bash
mkdir my-dns && cd my-dns
curl -O https://raw.githubusercontent.com/TomTonic/coredns-fanout/refs/heads/main/docker-compose.yml
curl -O https://raw.githubusercontent.com/TomTonic/coredns-fanout/refs/heads/main/Corefile
mkdir -p denylists
```

You now have a complete, editable starting point. Nothing is started yet.

---

## Step 2 — Decide how CoreDNS listens

There are two common deployment shapes. Pick one.

### A) Single machine (just this host)

Bind to loopback only. Other devices cannot reach it, which is exactly what you
want for a personal cache.

```corefile
. {
    bind 127.0.0.1
    bind ::1
    # ...
}
```

The example `docker-compose.yml` uses `network_mode: host`, which is the
simplest option on a Linux host and lets CoreDNS bind directly to the host
interfaces.

### B) Resolver for the whole network (LAN)

Bind to the host's LAN addresses so other devices can use it as their resolver.

```corefile
. {
    bind 192.168.1.2          # this host's LAN IPv4 address
    bind fd00::2              # this host's LAN IPv6 address (optional)
    # ...
}
```

Then point your clients at this address — usually by setting it as the DNS
server in your router's DHCP settings.

> If you run several CoreDNS server blocks for different zones (see
> [Step 6](#step-6--local-zones-and-split-dns-optional)), repeat the same
> `bind` lines in each block.

---

## Step 3 — Configure your upstream resolvers (fanout)

This is the heart of the setup. The `fanout` plugin queries multiple upstreams
in parallel and returns the first usable answer.

Full option reference: <https://github.com/TomTonic/fanout>

### Upstream address syntax

| Transport | Prefix | Example |
|-----------|--------|---------|
| Plain DNS (UDP) | *(none)* | `9.9.9.9` |
| Plain DNS (TCP) | *(none)* + `network tcp` | `9.9.9.9` |
| DoT (DNS over TLS) | `tls://` | `tls://9.9.9.9` |
| DoH (HTTP/2) | `https://` | `https://cloudflare-dns.com/dns-query` |
| DoH3 (HTTP/3) | `h3://` | `h3://cloudflare-dns.com/dns-query` |
| DoQ (DNS over QUIC) | `quic://` | `quic://dns.adguard-dns.com` |

You can **mix all of these in a single `fanout` block**.

### Key options

| Option | Meaning | Default |
|--------|---------|---------|
| `race` | Return the first valid response, whatever the RCODE. | off |
| `race-continue-on-error` | With `race`: don't let an early error (e.g. `SERVFAIL`) win; `NOERROR`/`NXDOMAIN` still end the race. | off |
| `policy weighted-random` | Query a random subset instead of every upstream. | `sequential` |
| `weighted-random-server-count N` | How many upstreams to query per request. | all |
| `weighted-random-load-factor a b c …` | Per-upstream weight (1–100), in listed order. | 100 each |
| `worker-count N` | Max parallel queries per request. | number of upstreams |
| `timeout DURATION` | Per-request timeout. | `30s` |
| `attempt-count N` | Failures before an upstream is marked down (`0` disables). | `3` |
| `tls_servername NAME` | TLS server name; **required** for IP-based DoT endpoints. | — |
| `bootstrap IP …` | Plain-DNS servers used to resolve hostname-based upstreams (avoids a chicken-and-egg loop). | — |
| `ecs [CIDR]` | Add EDNS Client Subnet; no argument auto-detects your subnet. | off |
| `except DOMAIN …` / `except-file FILE` | Keep selected domains out of the fanout path. | — |
| `debug` | Log per-upstream intermediate failures. | off |

### Recommended starting point

For a low-latency local cache, combining `race` with `race-continue-on-error`
is usually the safest default:

```corefile
fanout . https://cloudflare-dns.com/dns-query h3://cloudflare-dns.com/dns-query quic://dns.adguard-dns.com {
    race
    race-continue-on-error
    timeout 1500ms
}
```

### Pattern: encrypted upstreams via IP (DoT with local stubs)

DoT to bare IP addresses needs a `tls_servername`. When you want several such
upstreams with *different* server names, the cleanest approach is to point
`fanout` at small local `forward` stubs, one per upstream:

```corefile
. {
    bind 127.0.0.1
    bind ::1

    fanout . 127.0.0.1:5301 127.0.0.1:5302 [::1]:5303 [::1]:5304 {
        race
        race-continue-on-error
        timeout 1500ms
    }
    cache 300
    errors
    health
}

.:5301 {
    bind 127.0.0.1 ::1
    forward . tls://9.9.9.11 { tls_servername dns11.quad9.net; health_check 10s }
}
.:5302 {
    bind 127.0.0.1 ::1
    forward . tls://1.1.1.1 { tls_servername one.one.one.one; health_check 10s }
}
.:5303 {
    bind 127.0.0.1 ::1
    forward . tls://2620:fe::11 { tls_servername dns11.quad9.net; health_check 10s }
}
.:5304 {
    bind 127.0.0.1 ::1
    forward . tls://2606:4700:4700::1111 { tls_servername one.one.one.one; health_check 10s }
}
```

### Pattern: a hosted profile (e.g. NextDNS) plus mixed transports

If you use a hosted resolver with a personal profile, keep your profile ID out
of any file you share publicly. Use a placeholder and fill in your own value:

```corefile
fanout . tls://dns.example-resolver.net quic://doq.example-resolver.net h3://doh.example-resolver.net/<your-profile-id> {
    tls_servername dot.example-resolver.net
    race
    race-continue-on-error
    bootstrap 9.9.9.9 1.1.1.1     # plain-DNS servers used only to resolve the hostnames above
    ecs
}
```

> Many hosted resolvers publish a fixed set of public **bootstrap** IPs. Use
> those (or any reliable plain-DNS server) so the encrypted hostnames can be
> resolved without depending on the very resolver you are configuring.

---

## Step 4 — Domain filtering (filterlist)

The `filterlist` plugin runs **before** `fanout`, so blocked names never reach
your upstreams. It is already enabled in the shipped Corefile.

Full option reference: <https://github.com/TomTonic/filterlist>

### Options

| Option | Meaning | Default |
|--------|---------|---------|
| `denylist_dir PATH` | Directory of denylist files. | — |
| `allowlist_dir PATH` | Directory of allowlist files (overrides denylist matches). | — |
| `action nxdomain\|nullip\|refuse` | How to answer a blocked query. | `nxdomain` |
| `nullip ADDR` / `nullip6 ADDR` | Sinkhole addresses for `action nullip`. | `0.0.0.0` / `::` |
| `ttl SECONDS` | TTL for `nullip` answers. | `3600` |
| `deny_non_allowlisted` | Block everything *not* on the allowlist (strict mode). | `false` |
| `invert_allowlist` | Treat non-`@@` rules in allowlist files as allow rules. | `false` |
| `log_queries` | Log each query's block/allow outcome. | `false` |
| `debounce DURATION` | Wait this long after a file change before recompiling. | `300ms` |
| `max_states N` | Cap wildcard-matcher memory (`0` = unlimited). | `200000` |

`action` values:

- **`nxdomain`** — answer `NXDOMAIN` (recommended for ad/tracker blocking).
- **`refuse`** — answer `REFUSED`.
- **`nullip`** — answer with the sinkhole IPs from `nullip`/`nullip6`.

### Supported list formats

The plugin parses the DNS-relevant subset of common formats — you can drop in
most public lists as-is:

- AdGuard / EasyList / ABP rules: `||example.com^`, `@@||allowed.com^`, `||*.ads.example.com^`
- Hosts files: `0.0.0.0 example.com`, `127.0.0.1 example.com`

### Hot reload

When files in the watched directories change, the plugin recompiles and swaps
the active matchers atomically. A bad file is logged and the previous ruleset
stays active — so a broken download never takes filtering down.

### Example

```corefile
filterlist {
    denylist_dir /etc/coredns/denylist.d
    allowlist_dir /etc/coredns/allowlist.d   # optional
    action nxdomain
}
```

Place this block before `fanout` in your `. { ... }` server block.

---

## Step 5 — Keep filter lists up to date (websyncd)

Filter lists go stale quickly, so the example stack ships **one websyncd
service per list**. Each service polls a single remote URL and writes it into
the shared `denylists/` directory; `filterlist` hot-reloads the change.

Full option reference: <https://github.com/TomTonic/websyncd>

### How it is wired in `docker-compose.yml`

```yaml
denylist-updater-adguard-filter:
  profiles: ["updaters"]                       # disabled unless the profile is active
  image: ghcr.io/tomtonic/websyncd:latest
  environment:
    RESOURCE_URL: https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt
    OUTPUT_PATH: /etc/coredns/denylist.d/adguard-filter.txt
    POLL_INTERVAL: 6h
    HEARTBEAT_ADDR: :8081
  volumes:
    - ./denylists:/etc/coredns/denylist.d
  restart: unless-stopped
```

### websyncd settings you'll use most

| Variable | Required | Default | Meaning |
|----------|----------|---------|---------|
| `RESOURCE_URL` | yes | — | Remote list URL (`http://` or `https://`). |
| `OUTPUT_PATH` | yes | — | Where to write it inside the container. |
| `POLL_INTERVAL` | no | `1h` | How often to check (Go duration: `30s`, `6h`; min 5s). |
| `HEARTBEAT_ADDR` | no | — | Enables `/healthz` + `/readyz` probes at this address. |
| `MAX_DOWNLOAD_BYTES` | no | `0` (unlimited) | Safety cap on response size. |
| `OUTPUT_FILE_ATTRIBUTES` | no | — | `uid:gid:mode`, e.g. `1000:1000:0644`. |

websyncd is bandwidth-friendly: it does a conditional HEAD/GET and only
downloads when the list actually changed.

### Adding your own list

Copy a service block, give it a unique service name, and change only
`RESOURCE_URL` and `OUTPUT_PATH`:

```yaml
denylist-updater-oisd-small:
  profiles: ["updaters"]
  image: ghcr.io/tomtonic/websyncd:latest
  environment:
    RESOURCE_URL: https://small.oisd.nl
    OUTPUT_PATH: /etc/coredns/denylist.d/oisd-small.txt
    POLL_INTERVAL: 6h
    HEARTBEAT_ADDR: :8081
  volumes:
    - ./denylists:/etc/coredns/denylist.d
  restart: unless-stopped
```

### Enabling the updaters

The updater services sit behind a Compose profile named `updaters` and are
**off by default**. Turn them on with either:

```bash
docker compose --profile updaters up -d
# or
COMPOSE_PROFILES=updaters docker compose up -d
```

To run them permanently, delete the `profiles: ["updaters"]` line from each
service.

> Prefer no extra containers? You can also drop list files into `denylists/`
> by hand (or via your own cron job) and skip websyncd entirely. `filterlist`
> will pick them up on the next change.

---

## Step 6 — Local zones and split DNS (optional)

If you have internal hostnames, you usually want CoreDNS to answer those
locally and *not* forward them upstream. Use a dedicated server block per
internal zone.

### Static records for an internal zone

```corefile
home.example.net {
    bind 192.168.1.2
    bind fd00::2
    hosts {
        192.168.1.10 nas.home.example.net
        fd00::10     nas.home.example.net
        192.168.1.11 server.home.example.net
        fd00::11     server.home.example.net
        fallthrough
    }
    local
    errors
}
```

### Block a domain locally

To make a domain always return `NXDOMAIN` locally (e.g. a router admin domain
you don't want resolved through upstreams):

```corefile
router.example.net {
    bind 192.168.1.2
    bind fd00::2
    local
    template ANY ANY {
        match ".*"
        rcode NXDOMAIN
    }
    errors
}
```

### Suppress noisy reverse/mDNS lookups

```corefile
in-addr.arpa {
    bind 192.168.1.2
    bind fd00::2
    local
    template ANY ANY {
        match "^.*\._dns-sd\._udp\..*$"
        answer ""
        rcode NXDOMAIN
    }
    errors
}
```

> Alternatively, keep a single `. { ... }` block and use `except` /
> `except-file` inside `fanout` to keep specific domains off the fanout path.

---

## Step 7 — Cache tuning

The shipped cache profile is a good default for a home cache:

```corefile
cache {
    success 100000          # how many positive answers to keep
    denial 20000            # how many negative answers to keep
    prefetch 5 3600s        # refresh popular entries before they expire
    serve_stale 3600s immediate   # answer instantly from stale data, refresh in background
}
```

`serve_stale … immediate` is especially valuable at home: clients still get an
instant answer even when an upstream is briefly slow or unreachable.

---

## Step 8 — Monitoring (optional but recommended)

The example always enables Prometheus metrics:

```corefile
prometheus 127.0.0.1:9153
```

- Open <http://127.0.0.1:9153/metrics> to see raw metrics.
- Search the page for `coredns_fanout_` to focus on per-upstream stats:
  request counts, durations, RCODE counts, and error counts per upstream.

This makes it easy to see which upstream is slow or flaky and whether your
`race` / `weighted-random` setup behaves as expected.

---

## Step 9 — Start and verify

```bash
docker compose up -d                       # without updaters
# or
docker compose --profile updaters up -d    # with filter-list updaters

# verify it resolves
dig github.com @127.0.0.1
# verify a blocked domain returns NXDOMAIN (once a denylist is loaded)
dig doubleclick.net @127.0.0.1
```

Check logs with `docker compose logs -f coredns`.

---

## Putting it together

A minimal but complete `. { ... }` block combining all of the above:

```corefile
. {
    bind 127.0.0.1
    bind ::1
    bufsize 1232
    local

    filterlist {
        denylist_dir /etc/coredns/denylist.d
        action nxdomain
    }

    fanout . https://cloudflare-dns.com/dns-query h3://cloudflare-dns.com/dns-query quic://dns.adguard-dns.com {
        race
        race-continue-on-error
        timeout 1500ms
    }

    cache {
        success 100000
        denial 20000
        prefetch 5 3600s
        serve_stale 3600s immediate
    }

    prometheus 127.0.0.1:9153
    errors
    health
    loop
}
```

---

## Reference links

- CoreDNS manual & plugin syntax — <https://coredns.io/manual/toc/>
- fanout (parallel upstreams) — <https://github.com/TomTonic/fanout>
- filterlist (domain blocking) — <https://github.com/TomTonic/filterlist>
- websyncd (filter-list updates) — <https://github.com/TomTonic/websyncd>
- coredns-fanout image on Docker Hub — <https://hub.docker.com/r/tomtonic/coredns-fanout/>

# coredns-fanout

![coredns-fanout Docker image](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2FTomTonic%2Fcoredns-fanout%2Frefs%2Fheads%2Fmain%2Fversion.json&query=%24.version&prefix=v&label=coredns-fanout%20Docker%20image&color=blue)
[![Docker Pulls](https://img.shields.io/docker/pulls/tomtonic/coredns-fanout.svg)](https://hub.docker.com/r/tomtonic/coredns-fanout)
![Built with CoreDNS](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2FTomTonic%2Fcoredns-fanout%2Frefs%2Fheads%2Fmain%2Fversion.json&query=%24.coredns&label=Built%20with%20CoreDNS&color=blue)
![Built with Fanout](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2FTomTonic%2Fcoredns-fanout%2Frefs%2Fheads%2Fmain%2Fversion.json&query=%24.fanout&label=Built%20with%20Fanout&color=blue)
![Built with Filterlist](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2FTomTonic%2Fcoredns-fanout%2Frefs%2Fheads%2Fmain%2Fversion.json&query=%24.filterlist&label=Built%20with%20Filterlist&color=blue)
![Built with Go toolchain](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2FTomTonic%2Fcoredns-fanout%2Frefs%2Fheads%2Fmain%2Fversion.json&query=%24.go_version&prefix=v&label=Built%20with%20Go%20toolchain&color=blue)
[![Vulnerabilities of Docker Image](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/TomTonic/f925f1cacde626864f41dd3fc86d43b2/raw/coredns_fanout-docker_image.json)](https://gist.github.com/TomTonic/f925f1cacde626864f41dd3fc86d43b2#file-coredns_fanout-docker_image-md)

`coredns-fanout` is a small, fully text-configurable DNS cache and ad/tracker
blocker for a laptop, homelab host, or whole home network. It is a Docker image
built on [CoreDNS](https://github.com/coredns/coredns) with two plugins:
[TomTonic/filterlist](https://github.com/TomTonic/filterlist) for domain
blocking and the maintained [TomTonic/fanout](https://github.com/TomTonic/fanout)
plugin for querying several upstream resolvers in parallel. It is available on
[Docker Hub](https://hub.docker.com/r/tomtonic/coredns-fanout/).

Unlike a single-upstream forwarder, `fanout` sends each query to several
resolvers at once and returns the first usable answer — so one slow or flaky
upstream no longer decides your latency. You can mix plain DNS, DoT, DoH (HTTP/2),
DoH3 (HTTP/3), and DoQ in a single configuration.

## Is it the right tool for you?

It is a good alternative to **Pi-hole**, **AdGuard Home**, or **dnsproxy** if
you want:

- **Blocking *and* fast resolution in one place** — denylists/allowlists in
  AdGuard, EasyList/ABP, and hosts formats, combined with parallel encrypted
  upstreams and a tuned cache.
- **Plain-text configuration** — a single `Corefile`, no database and no admin
  UI. Keep it in git and deploy it reproducibly.
- **Mixed encrypted transports** — DoT, DoH, DoH3, and DoQ, freely combined in
  one `fanout` block, with first-usable-answer racing.
- **A tiny footprint** — a distroless, multi-arch image (`amd64`, `arm64`,
  `armhf`) from pinned, reproducible builds.
- **First-class metrics** — a Prometheus endpoint with per-upstream latency,
  RCODE, and error counters built in.

Look elsewhere if you want an all-in-one appliance with a **web dashboard,
per-client rules, a query-log browser, or built-in DHCP** — AdGuard Home or
Pi-hole fit that better. `coredns-fanout` is a resolver, cache, and filter you
configure as code and observe with Prometheus/Grafana, not a bundled UI.

## Built for performance

Every component is chosen and tuned so the request hot path stays fast and the
parts work together without wasted effort:

- **Filtering in ~200 ns per query.** `filterlist` uses a hybrid matcher: exact
  domains live in a suffix hash map (O(1) lookup), while wildcard rules compile
  into a minimized DFA. A typical AdGuard list compiles in well under a second,
  and lookups add roughly 0.0002 ms to a query.
- **Reloads never stall lookups.** When a list changes, `filterlist` recompiles
  in the background and swaps the active matcher **atomically and lock-free** —
  queries keep being answered at full speed during the swap, and a broken list
  is rejected while the previous one stays live.
- **Fastest usable answer wins.** `fanout`'s `race` returns the first valid
  response and cancels the remaining in-flight queries immediately. With
  `race-continue-on-error` a fast `SERVFAIL` or transport failure cannot win
  early, while `NOERROR`/`NXDOMAIN` still end the race at once — you get the
  speed of racing without losing answers to a flaky upstream.
- **Connections are reused, not rebuilt.** The maintained `fanout` fork keeps
  pooled TCP/TLS/QUIC connections with liveness checks and retry-on-stream-
  failure, so sustained load does not pay repeated handshake costs.
  `worker-count` and `weighted-random` let you cap concurrency and spread load
  instead of hitting every upstream on every query.
- **The cache answers instantly.** CoreDNS `prefetch` refreshes popular entries
  before they expire, and `serve_stale … immediate` returns a stale answer
  right away while refreshing it in the background — clients never wait on a
  slow upstream.
- **Updates only when something actually changed.** `websyncd` polls each list
  with a conditional `HEAD`/`GET` (ETag / Last-Modified) and rewrites the file
  **only when the content really changed**, using an atomic write. No needless
  downloads, no partial files, and — crucially — no unnecessary `filterlist`
  recompiles, so the updater and the matcher stay out of each other's way.

The runtime is a small distroless, multi-arch image from pinned, reproducible
builds, so the performance profile is the same everywhere it runs.

## Quick start

```bash
mkdir my-dns && cd my-dns
curl -O https://raw.githubusercontent.com/TomTonic/coredns-fanout/refs/heads/main/docker-compose.yml
curl -O https://raw.githubusercontent.com/TomTonic/coredns-fanout/refs/heads/main/Corefile
mkdir -p denylists

# Start the cache with parallel encrypted upstreams
docker compose up -d
dig github.com @127.0.0.1

# Add ad/tracker blocking by also starting the bundled filter-list updaters
docker compose --profile updaters up -d
```

Defaults of the shipped example:

- `docker-compose.yml` uses `network_mode: host` — the simplest option on a
  Linux host.
- The `Corefile` binds to `127.0.0.1` and `::1` (a single-machine cache). For a
  LAN resolver, change `bind` to the host's LAN addresses and point clients at
  it via DHCP. See **[CONFIGURATION.md](CONFIGURATION.md)**.
- `fanout` mixes local DoT forward stubs with direct DoH, DoH3, and DoQ
  upstreams, using `race` + `race-continue-on-error`.
- The cache is tuned for day-to-day use (`prefetch`, `serve_stale`).
- Prometheus metrics are always exposed on `127.0.0.1:9153`.
- Docker pulls the right image for your CPU architecture automatically.

## Configuration

For a complete, step-by-step walkthrough — listening addresses, choosing and
mixing upstreams, domain filtering, automatic list updates, local zones/split
DNS, cache tuning, and monitoring — see:

➡️ **[CONFIGURATION.md](CONFIGURATION.md)**

It also links to the full option reference of each component
([fanout](https://github.com/TomTonic/fanout),
[filterlist](https://github.com/TomTonic/filterlist),
[websyncd](https://github.com/TomTonic/websyncd)).

## Domain filtering

The image bundles the `filterlist` plugin, placed **before** `fanout` so blocked
names never reach your upstreams. The shipped `Corefile` uses
`action nxdomain` and hot-reloads whenever a list file changes. Lists in
AdGuard/EasyList/ABP and hosts formats work as-is, and an optional `allowlist_dir`
lets you override individual matches.

To keep lists fresh, the example `docker-compose.yml` includes optional
[websyncd](https://github.com/TomTonic/websyncd) updater services — one per
list, each syncing a single URL into the shared denylist directory. They sit
behind a Compose profile named `updaters` and are **off by default**; enable
them with `docker compose --profile updaters up -d` (or
`COMPOSE_PROFILES=updaters`). Add your own list by copying a service block and
changing `RESOURCE_URL` / `OUTPUT_PATH`. Details and per-option reference are in
[CONFIGURATION.md](CONFIGURATION.md) (steps 4–5).

## Built on the maintained fanout fork

This image deliberately uses [TomTonic/fanout](https://github.com/TomTonic/fanout)
instead of the original
[networkservicemesh/fanout](https://github.com/networkservicemesh/fanout). The
practical differences:

- **More upstream protocols.** In addition to UDP, TCP, and DoT, the fork adds
  DoH over HTTP/2, DoH3 over HTTP/3, and DoQ — mixable in one `fanout` block.
- **Better race behavior.** With `race-continue-on-error`, a transport failure
  or an error response such as `SERVFAIL` does not beat a slightly slower
  successful answer; `NXDOMAIN` still counts as a valid terminal answer and ends
  the race.
- **More resilient transport handling.** Stronger connection reuse and pooling
  for HTTPS and QUIC, plus more robust handling of failed streams and unhealthy
  connections.
- **Better observability.** Additional per-upstream error metrics on the
  Prometheus endpoint.
- **Better supply-chain hygiene.** Tracks current CoreDNS and Go releases and
  trims unnecessary dependency surface.

## Image channels and releases

This repository publishes two clearly separated image channels:

- **Test images** are built automatically when `build-versions.json` changes on
  `main`, as immutable pre-release tags such as
  `tomtonic/coredns-fanout:v2.5.0-test.104.1.a1b2c3d` plus the floating
  `tomtonic/coredns-fanout:test`.
- **Production images** are published only when a GitHub Release is created,
  publishing `tomtonic/coredns-fanout:vX.Y.Z` and the floating `vX.Y`, `vX`, and
  `latest` tags. The stable tags never move unless a Release is created on
  purpose.

```bash
docker pull tomtonic/coredns-fanout:test       # latest automatic test build
docker pull tomtonic/coredns-fanout:latest     # latest production release
docker pull tomtonic/coredns-fanout:v2.4.0     # a specific production release
```

Releasing for production: update `build-versions.json`, merge to `main`, let the
`-test` build finish, then create a GitHub Release tagged `vX.Y.Z`. The release
workflow publishes the production images and syncs `version.json` on `main`.

## Compatibility note

This project switched from `networkservicemesh/fanout` to `TomTonic/fanout` in
March 2026. If you explicitly need the older plugin line, use an earlier image
tag:

```bash
docker pull tomtonic/coredns-fanout:v2.0.0
```

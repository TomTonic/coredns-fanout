# coredns-fanout

![coredns-fanout Docker image](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2FTomTonic%2Fcoredns-fanout%2Frefs%2Fheads%2Fmain%2Fversion.json&query=%24.version&prefix=v&label=coredns-fanout%20Docker%20image&color=blue)
[![Docker Pulls](https://img.shields.io/docker/pulls/tomtonic/coredns-fanout.svg)](https://hub.docker.com/r/tomtonic/coredns-fanout)
![Built with CoreDNS](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2FTomTonic%2Fcoredns-fanout%2Frefs%2Fheads%2Fmain%2Fversion.json&query=%24.coredns&label=Built%20with%20CoreDNS&color=blue)
![Built with Fanout](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2FTomTonic%2Fcoredns-fanout%2Frefs%2Fheads%2Fmain%2Fversion.json&query=%24.fanout&label=Built%20with%20Fanout&color=blue)
![Built with Go toolchain](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2FTomTonic%2Fcoredns-fanout%2Frefs%2Fheads%2Fmain%2Fversion.json&query=%24.go_version&prefix=v&label=Built%20with%20Go%20toolchain&color=blue)
[![Vulnerabilities of Docker Image](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/TomTonic/f925f1cacde626864f41dd3fc86d43b2/raw/coredns_fanout-docker_image.json)](https://gist.github.com/TomTonic/f925f1cacde626864f41dd3fc86d43b2#file-coredns_fanout-docker_image-md)

`coredns-fanout` is a Docker image for a fast local DNS cache built with [CoreDNS](https://github.com/coredns/coredns) and the maintained [TomTonic/fanout](https://github.com/TomTonic/fanout) plugin. The image is available on [Docker Hub](https://hub.docker.com/r/tomtonic/coredns-fanout/).

It is aimed at users who want a simple, low-latency DNS cache for a laptop, homelab host, or home network and want to query multiple upstream resolvers in parallel instead of depending on a single upstream.

The badges above reflect the versions that are actually shipped. Builds are produced from pinned dependencies in `build-versions.json` and published as multi-arch images for `amd64`, `arm64`, and `armhf`.

## Image channels and releases

This repository now publishes two clearly separated image channels:

- Test images are built automatically when `build-versions.json` changes on `main`. They are published as immutable pre-release style tags such as `tomtonic/coredns-fanout:v2.5.0-test.104.1.a1b2c3d` plus the floating tag `tomtonic/coredns-fanout:test`.
- Production images are published only when a GitHub Release is explicitly created. That workflow publishes `tomtonic/coredns-fanout:vX.Y.Z` and the floating production tags `vX.Y`, `vX`, and `latest`.
- `version.json` now tracks the production release line only. Its `.version` value must match the GitHub Release tag exactly, for example `"version": "2.4.0"` in `version.json` and `v2.4.0` as the GitHub Release tag.

That means you can still pull and test CI-built images normally, but they are always unmistakably marked as non-production by the `-test...` suffix. The stable tags never move unless you create a GitHub Release on purpose.

Examples:

```bash
# latest automatic test build
docker pull tomtonic/coredns-fanout:test

# specific immutable test build
docker pull tomtonic/coredns-fanout:v2.5.0-test.104.1.a1b2c3d

# explicit production release
docker pull tomtonic/coredns-fanout:v2.4.0
docker pull tomtonic/coredns-fanout:latest
```

### Releasing for production

The production workflow is intentionally explicit:

1. Update `build-versions.json` to the dependency set you want to ship.
2. Update `version.json` so it already describes that exact production release, including `"version": "X.Y.Z"` and the matching dependency metadata.
3. Merge that state to `main` and let the automatic `-test` image build finish.
4. Create a GitHub Release with the tag `vX.Y.Z`.

The release workflow validates that the release tag, `version.json`, and `build-versions.json` all match before it publishes the production tags.

## Why use it

- CoreDNS runs as a local cache in front of your upstream resolvers.
- The `fanout` plugin sends each DNS query to multiple upstreams in parallel.
- The first usable response wins instead of waiting on a single resolver.
- You can combine classic and encrypted upstream transports.
- The runtime image is small and distroless, and the build chain is pinned for reproducibility.

In practice that means faster lookups, better tolerance for weak upstreams, and a setup that scales from a single-machine cache to a resolver for an entire home network.

## Why the TomTonic fork matters

This image deliberately uses [TomTonic/fanout](https://github.com/TomTonic/fanout) instead of the original [networkservicemesh/fanout](https://github.com/networkservicemesh/fanout).

For someone who just wants a dependable local DNS cache, the relevant differences are:

- More upstream protocols. In addition to UDP, TCP, and DoT, the fork supports DoH over HTTP/2, DoH3 over HTTP/3, and DoQ. You can even mix these transports in one `fanout` block.
- Better behavior when a fast upstream returns a bad answer. With `race-continue-on-error`, transport failures and error responses such as `SERVFAIL` do not automatically beat a slightly slower successful response. In the intended race behavior for this image, `NXDOMAIN` is treated as a valid terminal DNS answer and should still be allowed to end the race early.
- Harder, more resilient transport handling. The fork adds stronger connection reuse and pooling for HTTPS and QUIC, plus more robust handling around failed streams and unhealthy connections.
- Better observability. The fork exposes additional error metrics per upstream via the prometheus endpoint.
- Better supply-chain hygiene. The maintained fork follows current CoreDNS and Go releases and trims away unnecessary dependency surface.

For a home network, that mainly translates into lower latency, more transport options, and fewer situations where one flaky resolver spoils the overall result.

## Quick start

The shipped example is designed as a practical starting point for a local DNS cache:

```bash
mkdir coredns-fanout
cd coredns-fanout
curl -O https://raw.githubusercontent.com/TomTonic/coredns-fanout/refs/heads/main/docker-compose.yml
curl -O https://raw.githubusercontent.com/TomTonic/coredns-fanout/refs/heads/main/Corefile
docker compose up -d
dig github.com @127.0.0.1
```

Important details:

- The shipped Compose file uses `network_mode: host`. That is the most straightforward option on a Linux host.
- The example `Corefile` binds to `127.0.0.1` and `::1` by default. That is suitable for a cache on one machine. For a LAN resolver, change the bind addresses to the host's LAN IP addresses.
- The shipped `Corefile` always enables Prometheus metrics on `127.0.0.1:9153`.
- Docker automatically pulls the correct image for your CPU architecture.

## What the shipped example actually does

The repository includes a practical mixed-protocol example in `docker-compose.yml` and `Corefile`:

- CoreDNS listens on port `53` on the host network.
- Prometheus metrics are always exposed on `127.0.0.1:9153`.
- The cache is tuned for a local DNS cache, including `prefetch` and `serve_stale`.
- `fanout` mixes four DoT-backed local forward stubs with direct DoH over HTTP/2, DoH over HTTP/3, and DoQ upstreams.
- The shipped example includes two IPv4 DoT resolvers, two IPv6 DoT resolvers, one DoH endpoint, one DoH3 endpoint, and one DoQ endpoint.

That layout is intentional. The four IP-address-based upstreams stay on DoT, where separate TLS server names are easier to handle through local `forward` stubs, while the same fanout block still demonstrates mixed transport support with DoH, DoH3, and DoQ.

## Best-of configuration guide

These are the settings most users end up changing:

- `bind`: where the cache listens on IPv4 and IPv6
- upstream selection: which resolvers you want to query in parallel
- `cache`: size, `prefetch`, and `serve_stale`
- `race`: return quickly when you care most about latency
- `race-continue-on-error`: keep race mode without letting a fast transport failure or `SERVFAIL` win too early
- `policy weighted-random`: query only a subset of upstreams per request
- `worker-count`: limit concurrency per request
- `timeout` and `attempt-count`: tune how aggressively fanout should give up on weak upstreams
- `except` and `except-file`: keep selected domains out of the fanout path

## Common patterns

### 1. Minimal direct setup with encrypted upstreams

If you want the smallest possible configuration, point `fanout` directly at encrypted resolvers:

```corefile
. {
    bind 192.168.178.2
    bind fd00::53

    fanout . https://cloudflare-dns.com/dns-query h3://cloudflare-dns.com/dns-query quic://dns.adguard-dns.com {
        race
        race-continue-on-error
        timeout 1500ms
    }

    cache 300
    errors
    health
}
```

This is a good fit if you want a compact config and want to mix DoH, DoH3, and DoQ directly.

### 2. Query only some upstreams, not all of them

If you want several upstreams configured but do not want to hit all of them on every query, `weighted-random` is usually a better compromise:

```corefile
. {
    fanout . 9.9.9.9 1.1.1.1 8.8.8.8 {
        policy weighted-random
        weighted-random-server-count 2
        weighted-random-load-factor 100 80 40
        worker-count 2
        timeout 1200ms
    }

    cache 300
    errors
}
```

Use this when you want less upstream traffic, want to prefer some resolvers over others, or want to spread load without querying every upstream every time.

### 3. Mixed transports in one fanout block

The shipped example demonstrates a single `fanout` block that mixes DoT-backed local stubs with direct DoH over HTTP/2, DoH over HTTP/3, and DoQ:

```corefile
. {
    fanout . 127.0.0.1:5301 127.0.0.1:5302 [::1]:5303 [::1]:5304 https://cloudflare-dns.com/dns-query h3://cloudflare-dns.com/dns-query quic://dns.adguard-dns.com {
        policy weighted-random
        weighted-random-server-count 4
        worker-count 4
        race
        race-continue-on-error
        timeout 1500ms
    }

    cache 300
    prometheus 127.0.0.1:9153
    errors
    health
}

.:5301 {
    forward . tls://9.9.9.11 {
        tls_servername dns11.quad9.net
    }
}

.:5302 {
    forward . tls://1.1.1.1 {
        tls_servername one.one.one.one
    }
}

.:5303 {
    forward . tls://2620:fe::11 {
        tls_servername dns11.quad9.net
    }
}

.:5304 {
    forward . tls://2606:4700:4700::1111 {
        tls_servername one.one.one.one
    }
}
```

This is a good fit when you want the example itself to show the full range of upstream transport choices supported by the maintained fork without dropping the IP-address-based upstreams back to plain DNS.

### 4. Keep the latency benefits of race mode without accepting fast failures

`race` alone is fast, but an early error response can win too soon. For a local DNS cache, this combination is often the safer default:

```corefile
. {
    fanout . https://dns.google/dns-query https://cloudflare-dns.com/dns-query h3://cloudflare-dns.com/dns-query {
        race
        race-continue-on-error
        timeout 1500ms
    }
}
```

This is useful when you want low latency but do not want one weak upstream returning `SERVFAIL` to decide the entire request immediately. In the intended behavior for this image, `NXDOMAIN` is considered a valid DNS answer and should still terminate the race.

### 5. Exclude specific domains

For split DNS, local zones, or special cases, exclude domains from the fanout path:

```corefile
. {
    fanout . 9.9.9.9 1.1.1.1 {
        except home.arpa
        except corp.example
        except-file /etc/coredns/fanout-exclude.txt
    }
}
```

That is useful when some names should be answered by local zones, static records, or other CoreDNS plugins instead.

## Cache tuning for day-to-day use

The shipped example already uses a sensible cache profile for a local DNS cache:

```corefile
cache {
    success 100000
    denial 20000
    prefetch 5 3600s
    serve_stale 3600s immediate
}
```

In short:

- `success` and `denial` control how many positive and negative responses are retained
- `prefetch` refreshes frequently used entries before they expire
- `serve_stale ... immediate` returns a stale response immediately and refreshes it in the background

For a home network, `serve_stale` is often especially useful because clients still get an immediate answer even when an upstream is briefly slow or unavailable.

## Monitoring

The shipped example always enables the `prometheus` plugin in CoreDNS, so `fanout` metrics are available immediately on `127.0.0.1:9153`. In the maintained fork that includes:

- request counters per upstream
- request duration per upstream
- RCODE counters per upstream
- error counters per upstream and error class

That makes it much easier to spot which upstream is slow, which one fails often, and whether your `race` or `weighted-random` setup behaves as expected.

Small browser-based examples:

- Open `http://127.0.0.1:9153/metrics` in a browser to see the raw CoreDNS and `fanout` metrics output.
- Search that page for `coredns_fanout_` to focus on the plugin-specific metrics.
- If you scrape this endpoint with a Prometheus server, you can open its expression browser with a query such as:

```text
http://127.0.0.1:9090/graph?g0.expr=sum(rate(coredns_fanout_request_count_total%5B5m%5D))&g0.tab=1
```

That example shows the recent total fanout request rate across all configured upstreams.

## When to use which setup

- Single-machine local cache: keep the loopback bindings
- Resolver for the whole home network: change `bind` to the host's LAN addresses and point clients at that resolver via DHCP or static settings
- Maximum simplicity: use direct `fanout` upstreams with DoH, DoH3, or DoQ
- Maximum per-provider control: put `fanout` in front of local `forward` stubs
- Low latency with occasional weak upstreams: enable both `race` and `race-continue-on-error`

## Further reading

This README is intentionally a compact, best-of guide for the practical use case of a local DNS cache. For complete plugin syntax, more examples, and all fanout options, see [TomTonic/fanout](https://github.com/TomTonic/fanout).

## Compatibility note

This project switched from `networkservicemesh/fanout` to `TomTonic/fanout` in March 2026. If you explicitly need the older plugin line, you can still use an earlier image tag:

```bash
docker pull tomtonic/coredns-fanout:v2.0.0
```

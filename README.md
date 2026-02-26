# coredns-fanout

A Docker container for a local high performance DNS cache for your notebook or your LAN.

The Docker image encapsulates a standard build of [CoreDNS](https://github.com/coredns/coredns) with an activated [fanout](https://github.com/networkservicemesh/fanout) plugin.
Plattform specific Docker images are built nightly and can be obtained from the Docker Hub repository [tomtonic/coredns-fanout](https://hub.docker.com/r/tomtonic/coredns-fanout).
Pinned dependency versions for deterministic builds are managed in `build-versions.json`.

coredns-fanout version: v2.0.0

Latest release lookup: 24.02.2026 00:33 UTC

Latest CoreDNS release: v1.14.1

Latest Fanout release: v1.11.3

Go toolchain: (pending first v2 build)

Runtime base image: (pending first v2 build)

## How to install

To install this Docker image as DNS cache, you can execute the following steps:

- Make sure you have Docker installed.
- Donwload the [docker-compose.yml](https://raw.githubusercontent.com/TomTonic/coredns-fanout/refs/heads/main/docker-compose.yml) and the [Corefile](https://raw.githubusercontent.com/TomTonic/coredns-fanout/refs/heads/main/Corefile) from above and put them next to each other in a directory on the local server machine.
- Docker will automatically pull the correct image for your CPU architecture (amd64, arm64, armhf).
- Start with `docker compose up` and test via `dig github.com @127.0.0.1` from a second console.
- Configure both files to your (network's) needs. Especially, set the bind addresses in the Corefile to the public interface of your local server.
- Don't forget to configure your clients to use the new server, advertize it via DHCP, for example.

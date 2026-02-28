# coredns-fanout

![coredns-fanout Docker image](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2FTomTonic%2Fcoredns-fanout%2Frefs%2Fheads%2Fmain%2Fversion.json&query=%24.version&prefix=v&label=coredns-fanout%20Docker%20image&color=blue)
![Built with CoreDNS](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2FTomTonic%2Fcoredns-fanout%2Frefs%2Fheads%2Fmain%2Fversion.json&query=%24.coredns&label=Built%20with%20CoreDNS&color=blue)
![Built with Fanout](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2FTomTonic%2Fcoredns-fanout%2Frefs%2Fheads%2Fmain%2Fversion.json&query=%24.fanout&label=Built%20with%20Fanout&color=blue)
![Built with Go toolchain](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2FTomTonic%2Fcoredns-fanout%2Frefs%2Fheads%2Fmain%2Fversion.json&query=%24.go_version&prefix=v&label=Built%20with%20Go%20toolchain&color=blue)
[![Vulnerabilities of Docker Image](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/TomTonic/f925f1cacde626864f41dd3fc86d43b2/raw/coredns_fanout-docker_image.json)](https://gist.github.com/TomTonic/f925f1cacde626864f41dd3fc86d43b2#file-coredns_fanout-docker_image-md)

A Docker container for a local high performance DNS cache for your notebook or your LAN.

The Docker image encapsulates a standard build of [CoreDNS](https://github.com/coredns/coredns) with an activated [fanout](https://github.com/networkservicemesh/fanout) plugin.
Plattform specific Docker images can be obtained from the Docker Hub repository [tomtonic/coredns-fanout](https://hub.docker.com/r/tomtonic/coredns-fanout).
Pinned dependency versions for deterministic builds are managed in `build-versions.json`.

## How to install

To install this Docker image as DNS cache, you can execute the following steps:

- Make sure you have Docker installed.
- Donwload the [docker-compose.yml](https://raw.githubusercontent.com/TomTonic/coredns-fanout/refs/heads/main/docker-compose.yml) and the [Corefile](https://raw.githubusercontent.com/TomTonic/coredns-fanout/refs/heads/main/Corefile) from above and put them next to each other in a directory on the local server machine.
- Docker will automatically pull the correct image for your CPU architecture (amd64, arm64, armhf).
- Start with `docker compose up` and test via `dig github.com @127.0.0.1` from a second console.
- Configure both files to your (network's) needs. Especially, set the bind addresses in the Corefile to the public interface of your local server.
- Don't forget to configure your clients to use the new server. Advertize it via DHCP, for example.

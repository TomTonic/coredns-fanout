# AI Agent Guidelines

## Project Overview

`coredns-fanout` is a Docker image build wrapper, **not a Go module**. It
builds a small, distroless, multi-arch DNS cache/ad-blocker image from
[CoreDNS](https://github.com/coredns/coredns) plus two plugins —
[`fanout`](https://github.com/TomTonic/fanout) (parallel upstream querying
over DoT/DoH/DoH3/DoQ) and [`filterlist`](https://github.com/TomTonic/filterlist)
(allow/deny-list blocking) — together with
[`websyncd`](https://github.com/TomTonic/websyncd) for keeping filter lists
updated at runtime. There is no `go.mod` here: CoreDNS and the plugins are
compiled from their pinned source tags during the Docker build, not
imported as Go modules of this repo.

## Repository Layout

- `build-versions.json` — the single source of truth for pinned versions:
  `coredns_tag`, `fanout_tag`, `filterlist_tag`, `go_image` (build-time Go
  toolchain image), `runtime_base` (distroless runtime image digest). Bump
  one of these to update that dependency.
- `version.json` — a snapshot of the versions used in the *last published*
  release. Updated by CI on release, not by hand.
- `Corefile` — the CoreDNS configuration shipped in the image.
- `docker-compose.yml` — example deployment.
- `CONFIGURATION.md` — user-facing configuration reference.

## Build & Release Process

- `.github/workflows/main.yml` builds test images whenever
  `build-versions.json` changes (push to `main` or PR) — this is how a
  dependency bump gets validated before release.
- `.github/workflows/publish-images.yml` is a reusable workflow that builds
  and pushes the multi-arch image for a given git ref/version/tag set.
- `.github/workflows/release.yml` runs on a published GitHub Release and
  publishes the production image.
- `.github/workflows/testLogin.yml` is a manual, isolated check of Docker
  Hub credentials — use it to debug login/publish failures without
  triggering a real build or release.

## Dependencies

- Version bumps in `build-versions.json` (all five keys) and GitHub Actions
  are automated via Renovate.
- `dependency-review.yml` blocks PRs that introduce known-vulnerable
  dependencies.
- `security-badge.yml` refreshes a grype_me vulnerability badge daily
  against the latest published image.

## Security

- Never commit secrets, credentials, or API keys.
- The runtime image is **distroless**: anything present only in the
  `golang:*-bookworm` build stage (e.g. `curl`, `python3.11` OS packages)
  never ships in the final image. Don't treat a scanner hit against the
  build stage as a hit against the shipped artifact — see
  `known_not_applicable` guidance in `.claude/release-notes.yml`.

## Commit Messages

- Use imperative mood ("Update fanout to v1.16.2", not "Updated fanout").
- Limit subject line to 72 characters.
- Separate subject from body with a blank line.

## Release Notes

Handled by the `release-notes` agent (symlinked from `go-project-defaults`'s
`.claude/agents/release-notes.md` into `~/.claude/agents/` — see
[go-project-defaults's README](https://github.com/TomTonic/go-project-defaults#claude-code-agents-symlink-into-claudeagents)
for setup). This repo's `.claude/release-notes.yml` already declares its
three `core_dependencies` (CoreDNS, fanout, filterlist), each with a
`pinned_in: build-versions.json#.<key>` pointer instead of a go.mod-derived
version, since none of them are imported as Go modules of this repo.

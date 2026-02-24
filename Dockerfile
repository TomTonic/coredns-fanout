ARG ALPINE_VERSION=latest
FROM alpine:${ALPINE_VERSION}

RUN apk --no-cache add ca-certificates

COPY coredns /coredns
RUN chmod +x /coredns

EXPOSE 53 53/udp

ENTRYPOINT ["/coredns"]

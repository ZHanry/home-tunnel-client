# Build locally from the matching official Linux release extracted as ./package.
# The package contains the verified CLI and its matching, hash-pinned Agent.
FROM alpine:3.23
RUN apk add --no-cache ca-certificates && addgroup -g 10001 tunnel && adduser -D -u 10001 -G tunnel tunnel
COPY package/bin/home-tunnel-client /usr/local/bin/home-tunnel-client
COPY package/lib/home-tunnel-agent /usr/local/lib/home-tunnel-agent
USER 10001:10001
ENTRYPOINT ["/usr/local/bin/home-tunnel-client"]
CMD ["run", "--state", "/data/state.json", "--agent", "/usr/local/lib/home-tunnel-agent"]

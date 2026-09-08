FROM rust:1.96.0-alpine3.23 AS build
RUN apk add --no-cache musl-dev gcc
WORKDIR /src
COPY Cargo.toml Cargo.lock ./
COPY src ./src
COPY templates ./templates
COPY static ./static
RUN cargo build --locked --release

FROM scratch
COPY --from=build /src/target/release/homedesk-console /homedesk-console
ENTRYPOINT ["/homedesk-console"]

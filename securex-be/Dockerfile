# syntax=docker/dockerfile:1.7

FROM --platform=$BUILDPLATFORM golang:1.25-alpine AS builder

ARG TARGETOS
ARG TARGETARCH
ARG VERSION=dev
ARG REVISION=unknown

WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build \
    -trimpath \
    -ldflags="-s -w -X main.version=${VERSION} -X main.revision=${REVISION}" \
    -o /out/secure-x \
    ./cmd/server

FROM alpine:3.22

ARG VERSION=dev
ARG REVISION=unknown

LABEL org.opencontainers.image.title="Secure X Backend" \
      org.opencontainers.image.description="Secure X private backend service" \
      org.opencontainers.image.source="https://github.com/ligson/secure-x" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${REVISION}"

RUN apk add --no-cache ca-certificates tzdata \
    && addgroup -g 10001 -S securex \
    && adduser -u 10001 -S -G securex -h /app securex \
    && mkdir -p /app/data/files /app/logs \
    && chown -R securex:securex /app

WORKDIR /app

COPY --from=builder /out/secure-x /app/secure-x
COPY config.example.yaml /app/config.example.yaml

USER securex

EXPOSE 8080

VOLUME ["/app/data", "/app/logs"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/healthz >/dev/null || exit 1

ENTRYPOINT ["/app/secure-x"]
CMD ["--config", "/app/config.yaml"]

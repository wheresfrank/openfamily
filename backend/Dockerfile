# Build stage
FROM golang:1.25-alpine AS build
WORKDIR /src

# Git ref embedded as the fallback deployed version (the updater sidecar
# stamps the authoritative ref at runtime; this covers manual rebuilds).
ARG GIT_COMMIT=dev

# Cache dependencies.
COPY go.mod go.sum ./
RUN go mod download

# Build a static binary (migrations are embedded via go:embed).
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath \
    -ldflags="-s -w -X github.com/whereabouts/whereabouts/backend/internal/config.buildVersion=${GIT_COMMIT}" \
    -o /out/server ./cmd/server

# Runtime stage
FROM alpine:3.20
RUN apk add --no-cache ca-certificates tzdata
COPY --from=build /out/server /usr/local/bin/server
EXPOSE 8080
ENTRYPOINT ["server"]

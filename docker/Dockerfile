# --- Fase 1: Build ---
FROM golang:1.19-alpine AS builder
WORKDIR /app

# Configura Go per evitare problemi di rete
ENV GOPROXY=https://proxy.golang.org,direct
ENV GOSUMDB=sum.golang.org
ENV CGO_ENABLED=0
ENV GOOS=linux

# Copia solo i file necessari per il build (ottimizzazione cache Docker)
COPY go.mod go.sum ./
RUN go mod download

# Copia il codice sorgente
COPY src/ ./src/
COPY web/ ./web/
COPY scripts/ ./scripts/
COPY data/ ./data/

# Compila con ottimizzazioni
RUN go build -ldflags="-s -w" -o mapreduce ./src

# --- Fase 2: Release ---
FROM alpine:latest
WORKDIR /root/

# Installa ca-certificates per HTTPS
RUN apk --no-cache add ca-certificates docker-cli bash

COPY --from=builder /app/mapreduce .
COPY --from=builder /app/data ./data
COPY --from=builder /app/web ./web
COPY --from=builder /app/scripts ./scripts

CMD ["./mapreduce"]
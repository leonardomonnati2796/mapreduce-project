# --- Fase 1: Build ---
FROM golang:1.19-alpine AS builder
WORKDIR /app

# Configura Go per evitare problemi di rete
ENV GOPROXY=https://proxy.golang.org,direct
ENV GOSUMDB=sum.golang.org
ENV CGO_ENABLED=0
ENV GOOS=linux

# Copia tutto il progetto (approccio semplificato)
COPY . .

# Compila direttamente senza separare il download
RUN go build -o mapreduce ./src

# --- Fase 2: Release ---
FROM alpine:latest
WORKDIR /root/

# Installa ca-certificates per HTTPS
RUN apk --no-cache add ca-certificates docker-cli bash

COPY --from=builder /app/mapreduce .
COPY --from=builder /app/data ./data
COPY --from=builder /app/web ./web

CMD ["./mapreduce"]
# --- Fase 1: Build ---
FROM golang:1.19-alpine AS builder
WORKDIR /app

# Configura Go per evitare problemi di rete
ENV GOPROXY=https://proxy.golang.org,direct
ENV GOSUMDB=sum.golang.org
ENV CGO_ENABLED=0
ENV GOOS=linux

# Copia solo i file di dipendenze per ottimizzare la cache
COPY go.mod go.sum ./

# Download delle dipendenze con verbose output per debug
RUN go mod download -x

# Copia il codice sorgente
COPY src/ ./src/

# Compila l'applicazione
WORKDIR /app/src
RUN go build -o ../mapreduce

# --- Fase 2: Release ---
FROM alpine:latest
WORKDIR /root/
COPY --from=builder /app/mapreduce .
# Crea directory data e copia i file di input
RUN mkdir -p data
COPY data/*.txt ./data/
# Verifica che i file siano stati copiati correttamente
RUN ls -la data/
CMD ["./mapreduce"]
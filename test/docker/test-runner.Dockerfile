# Dockerfile per Test Runner MapReduce
FROM mcr.microsoft.com/powershell:7.2-ubuntu-20.04

# Installa dipendenze
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Installa Go
RUN wget https://go.dev/dl/go1.21.0.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go1.21.0.linux-amd64.tar.gz && \
    rm go1.21.0.linux-amd64.tar.gz

# Imposta PATH
ENV PATH="/usr/local/go/bin:${PATH}"

# Crea directory di lavoro
WORKDIR /app

# Copia codice sorgente
COPY . .

# Installa dipendenze Go
RUN cd src && go mod download

# Crea directory per report
RUN mkdir -p test/reports test/logs

# Imposta permessi
RUN chmod +x test/run-tests-optimized.ps1
RUN chmod +x test/test-suites/*.ps1

# Comando di default
CMD ["pwsh", "-File", "test/run-tests-optimized.ps1"]

FROM rust:1.70-slim as builder

WORKDIR /usr/src/app

# Copy only the dependencies first to leverage Docker caching
COPY Cargo.toml Cargo.lock ./

# Create a dummy main.rs to build dependencies
RUN mkdir -p src && \
    echo "fn main() {println!(\"Dummy build\")}" > src/main.rs && \
    cargo build --release && \
    rm -rf src

# Copy the actual source code
COPY . .

# Build the application
RUN cargo build --release

# Runtime stage
FROM debian:bullseye-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        git \
        libssl1.1 \
        libsqlite3-0 && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the built executable from the builder stage
COPY --from=builder /usr/src/app/target/release/art /app/art

# Copy static files and templates
COPY --from=builder /usr/src/app/static /app/static
COPY --from=builder /usr/src/app/templates /app/templates
COPY --from=builder /usr/src/app/config.toml /app/config.toml

# Create repositories directory
RUN mkdir -p /app/repositories

# Expose the port the server listens on
EXPOSE 3000

# Run the application
CMD ["/app/art", "--config", "/app/config.toml"]

# syntax=docker/dockerfile:1
FROM julia:1.8.5@sha256:c9c13e38ea7ef6a893b97834e75f00fec4fc07b24072088e1360171cb192ebb0
WORKDIR /app
ENV JULIA_NUM_THREADS=4 JULIA_NUM_PRECOMPILE_TASKS=4 JULIA_PKG_PRECOMPILE_AUTO=0
COPY Project.toml Manifest.toml ./
COPY src ./src
# Optional combined CA bundle for managed HTTPS proxies; never retained in an image layer.
RUN --mount=type=secret,id=proxy_ca \
    if [ -f /run/secrets/proxy_ca ]; then export JULIA_SSL_CA_ROOTS_PATH=/run/secrets/proxy_ca; fi; \
    julia --startup-file=no --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'
COPY data ./data
COPY scripts ./scripts
COPY test ./test
COPY third_party ./third_party
COPY LICENSE README.md ./
CMD ["julia", "--startup-file=no", "--project=.", "scripts/baseline.jl", "--smoke"]

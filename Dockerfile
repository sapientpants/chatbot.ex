# Build stage
ARG BUILDER_IMAGE="hexpm/elixir:1.19.4-erlang-28.2-debian-bookworm-20251117"
ARG RUNNER_IMAGE="debian:bookworm-20251117-slim"

FROM ${BUILDER_IMAGE} AS builder

# Install build dependencies
RUN apt-get update -y && apt-get install -y build-essential git \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Prepare build dir
WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set build ENV
ENV MIX_ENV="prod"

# Install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Copy compile-time config files
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# Copy application code and compile (generates colocated hooks)
COPY lib lib
RUN mix compile

# Copy assets and deploy (requires colocated hooks from compilation)
COPY priv priv
COPY assets assets
RUN mix assets.deploy

# Copy runtime config
COPY config/runtime.exs config/

# Build the release
COPY rel rel
RUN mix release

# Runtime stage
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR /app
RUN chown nobody /app

# Set runner ENV
ENV MIX_ENV="prod"

# Copy the release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/chatbot ./

USER nobody

# Run migrations on startup, then start the server
CMD ["/app/bin/server"]

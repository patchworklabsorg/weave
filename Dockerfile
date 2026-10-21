# syntax=docker/dockerfile:1

# Weave production image, on Ruby Alpine. Two stages: the build stage
# installs the gems and compiles the assets, and the runtime stage gets only
# the result. Keep RUBY_VERSION equal to .ruby-version and BUN_VERSION equal to
# mise.toml.
ARG RUBY_VERSION=4.0.7
ARG ALPINE_VERSION=3.24
ARG BUN_VERSION=1.4.3

FROM oven/bun:${BUN_VERSION}-alpine AS bun

FROM ruby:${RUBY_VERSION}-alpine${ALPINE_VERSION} AS base

LABEL org.opencontainers.image.description="Weave, the identity provider for Patchwork Labs"
LABEL org.opencontainers.image.source="https://github.com/patchworklabsorg/weave"

WORKDIR /rails

# Runtime packages only. jemalloc replaces the musl allocator, which is slow
# for Ruby. tzdata gives TZInfo its zone files.
RUN apk add --no-cache jemalloc tzdata

ENV RAILS_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=development:test \
    LD_PRELOAD=/usr/lib/libjemalloc.so.2 \
    RAILS_SERVE_STATIC_FILES=true \
    RAILS_LOG_TO_STDOUT=true

FROM base AS build

# Build packages: a compiler and headers for the gems with C extensions
# (openssl, psych, fiddle). Bun needs libstdc++ and libgcc.
RUN apk add --no-cache build-base libffi-dev openssl-dev yaml-dev libstdc++ libgcc

COPY --from=bun /usr/local/bin/bun /usr/local/bin/bun

COPY Gemfile Gemfile.lock .ruby-version ./
RUN bundle install --jobs 4 && \
    rm -rf "${BUNDLE_PATH}"/cache "${BUNDLE_PATH}"/ruby/*/cache && \
    find "${BUNDLE_PATH}"/ruby/*/gems \( -name "*.o" -o -name "*.c" -o -name "*.h" -o -name "Makefile" \) -type f -delete && \
    find "${BUNDLE_PATH}"/ruby/*/gems -mindepth 2 -maxdepth 2 -type d \( -name spec -o -name test -o -name tests \) -exec rm -rf {} +

COPY package.json bun.lock ./
RUN bun install --frozen-lockfile

COPY . .

# The Tailwind binary (about 100 MB) is only needed for assets:precompile.
# The precompile boot also writes a dummy local secret and a bootsnap cache
# of every loaded gem, so remove tmp/ and cache only app/ and lib/.
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile && \
    rm -rf node_modules app/assets/builds/*.map "${BUNDLE_PATH}"/ruby/*/gems/tailwindcss-ruby-*/exe \
      tmp/cache tmp/local_secret.txt && \
    bundle exec bootsnap precompile app/ lib/

FROM base

COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

ENTRYPOINT ["/rails/bin/docker-entrypoint"]
EXPOSE 3000
CMD ["./bin/thrust", "./bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]

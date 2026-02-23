# syntax=docker/dockerfile:1

# ---- Builder stage ----
FROM ruby:3.2-slim AS builder

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential libpq-dev libyaml-dev && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle config set --local without "development test" && \
    bundle install --jobs 4 --retry 3 && \
    rm -rf ~/.bundle/cache /usr/local/bundle/cache

COPY . .

RUN SECRET_KEY_BASE=placeholder bin/rails assets:precompile

# ---- Runtime stage ----
FROM ruby:3.2-slim

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y libpq5 libyaml-0-2 && \
    rm -rf /var/lib/apt/lists/* && \
    groupadd --system rails && \
    useradd --system --gid rails --create-home rails

WORKDIR /app

ENV RAILS_ENV=production

COPY --from=builder /usr/local/bundle /usr/local/bundle
COPY --from=builder /app /app

RUN mkdir -p /app/tmp /app/log && \
    chown -R rails:rails /app/tmp /app/log /app/db

USER rails

EXPOSE 3030

ENTRYPOINT ["bin/docker-entrypoint"]
CMD ["bin/rails", "server", "-b", "0.0.0.0", "-p", "3030"]

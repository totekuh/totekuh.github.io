# syntax=docker/dockerfile:1

FROM ruby:3.3-slim AS builder

WORKDIR /site

# Native extensions such as eventmachine need a compiler. Keep this in the
# build stage so the web image stays small and contains no build toolchain.
RUN apt-get update \
    && apt-get install --no-install-recommends -y build-essential libcurl4 \
    && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock ./
RUN bundle config set --local path /usr/local/bundle \
    && bundle config set --local without test \
    && bundle install --jobs 4 --retry 3

COPY . .

ENV JEKYLL_ENV=production
RUN bundle exec jekyll build --destination /site/_site

FROM builder AS test

# External URLs are intentionally skipped: a build should not fail because a
# third-party site is down or rate-limiting requests.
RUN bundle config unset without \
    && bundle install --jobs 4 --retry 3 \
    && bundle exec htmlproofer _site \
      --disable-external=true \
      --ignore-urls '/^http:\/\/127.0.0.1/,/^http:\/\/0.0.0.0/,/^http:\/\/localhost/'

FROM nginx:1.27-alpine AS runtime

COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /site/_site /usr/share/nginx/html

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:8080/ || exit 1

CMD ["nginx", "-g", "daemon off;"]

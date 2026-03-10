# Minimal image for isolated dev/test runs (see usr/README.md).
# Repo is mounted at /app; entrypoint runs bundle install then the given command.
FROM ruby:3.3-alpine

RUN apk add --no-cache build-base sqlite-dev git

WORKDIR /app

RUN gem install bundler

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/sh"]

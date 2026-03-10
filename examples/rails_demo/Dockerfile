# Build from repo root: docker build -f examples/rails_demo/Dockerfile .
# So that the gem is available at build time (COPY . /active_version).
FROM ruby:4.0

WORKDIR /app

RUN apt-get update && apt-get install -y \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Copy the ActiveVersion gem into the image so bundle install can find path: /active_version
COPY . /active_version

# Copy demo app Gemfile (gem at /active_version when DOCKER_BUILD=true)
COPY examples/rails_demo/Gemfile ./
RUN DOCKER_BUILD=true bundle install

COPY examples/rails_demo .

EXPOSE 3000

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]
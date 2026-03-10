# Demo App Setup

This document matches the current `examples/rails_demo` implementation.

## Prerequisites

- Ruby `>= 3.4`
- Bundler
- SQLite (local default)
- Optional: Docker + Docker Compose
- Optional for `bin/dev`: Foreman (`gem install foreman`)

## Local Setup (SQLite, default)

```bash
cd examples/rails_demo
bundle install
bin/rails db:prepare
bin/rails db:seed
```

Start server:

```bash
bin/rails server
```

Or:

```bash
bin/dev
```

`bin/dev` behavior:
- Uses `foreman start -f Procfile` if Foreman is installed.
- Falls back to `bin/rails server` if Foreman is missing.

App URL: [http://localhost:3000](http://localhost:3000)

### Demo Mode and Credentials

Auto-provisioning behavior:

- `development` and `test`: enabled by default
- other environments: set `DEMO_MODE=1` to enable

Supported environment variables:

- `DEMO_USER_EMAIL` (default: `demo@example.com`)
- `DEMO_USER_NAME` (default: `Demo User`)
- `DEMO_USER_PASSWORD` (default: generated at runtime)
- `DEMO_REVIEWER_EMAIL` (default: `reviewer@example.com`)
- `DEMO_SEED_PASSWORD` (used by `db:seed`; generated if not set)
- `DEMO_ADMIN_EMAIL` (default: `admin@example.com`)
- `DEMO_ADMIN_ENCRYPTED_PASSWORD` (default: generated at runtime)

## Docker Setup (PostgreSQL via DATABASE_URL)

From `examples/rails_demo`:

```bash
docker-compose up --build
docker-compose exec rails bundle exec rails db:create db:migrate db:seed
```

App URL: [http://localhost:3000](http://localhost:3000)

Notes:
- Container uses `DOCKER_BUILD=true` to resolve gem path as `/active_version`.
- Compose provides PostgreSQL and sets `DATABASE_URL`.
- Compose uses trust authentication for local demo convenience.

## Verification Checklist

After setup, verify:

1. Public app pages:
   - `/`
   - `/posts`
   - `/issues`
   - `/pull_requests`
2. Admin:
   - `/admin` (demo mode, direct access)
3. Theme picker in top bar:
   - `light`, `dark`, `leary`, `neon`, `forest`
4. Bottom command line is visible and accepts `help`.

## Test Setup

Run full test suite:

```bash
bin/rails test
```

System tests only:

```bash
bin/rails test test/system
```

System test stack:
- `capybara`
- `capybara-playwright-driver`
- `ActionDispatch::SystemTestCase` with `driven_by :playwright`

## Troubleshooting

1. DB issues:
```bash
bin/rails db:drop db:create db:migrate db:seed
```

2. Gems/path issues:
```bash
bundle install
```

3. Port conflict:
```bash
bin/rails server -p 3001
```

4. No Foreman:
- Use `bin/rails server` directly (or install Foreman).

# ActiveVersion Demo App

Rails 8 demo application for ActiveVersion with:
- Translations
- Revisions
- Audits
- Shrine attachments
- Phlex + StyleCapsule UI
- Built-in command line (`/command_line`)

Security note: this is a demo application. Do not deploy as-is to production.

## Current UI State

- Public app UI is rendered with Phlex components.
- Styling uses StyleCapsule inline scoped styles.
- Theme picker is available in the top bar:
  - `light`, `dark`, `leary`, `neon`, `forest`
- Liquid background styling is enabled.
- Bottom command line is always visible.

## Core Demo Areas

- Public social-style pages:
  - `/` (feed)
  - `/posts`
  - `/issues`
  - `/pull_requests`
  - `/categories`
  - `/users/:id`
- ActiveAdmin:
  - `/admin`
  - Demo mode: no login prompt (authorization relaxed for demo use).
- Specialized data model demos:
  - `/column_posts` (column-based audit storage)
  - `/composite_audits` (composite PK audit table)
  - `/source_partition_demo` (identity propagation / partition-shape demo)

## Data + Storage Notes

- Default DB in this app is SQLite (`config/database.yml`).
- Docker setup uses PostgreSQL via `DATABASE_URL`.
- Shrine is configured with:
  - `Shrine.plugin :keep_files`
  - local filesystem storage (`tmp/uploads/cache`, `public/uploads/store`)
- Attachment lifecycle tracking is implemented via `attachment_references` table.

## Quick Start (Local)

```bash
cd examples/rails_demo
bundle install
bin/rails db:prepare
bin/rails db:seed
bin/rails server
```

Open: [http://localhost:3000](http://localhost:3000)

### Demo Credentials / Identity

- Demo auto-provisioning is controlled by `DEMO_MODE`.
- In `development` and `test`, demo mode is enabled automatically.
- In other environments, set `DEMO_MODE=1` explicitly if you want auto-provisioning.

Optional environment variables:

- `DEMO_USER_EMAIL` (default: `demo@example.com`)
- `DEMO_USER_NAME` (default: `Demo User`)
- `DEMO_USER_PASSWORD` (default: random generated value)
- `DEMO_REVIEWER_EMAIL` (default: `reviewer@example.com`)
- `DEMO_SEED_PASSWORD` (used by seeds for demo/reviewer users; random if unset)
- `DEMO_ADMIN_EMAIL` (default: `admin@example.com`)
- `DEMO_ADMIN_ENCRYPTED_PASSWORD` (default: random generated value)

## Quick Start (Docker Compose)

From `examples/rails_demo`:

```bash
docker-compose up --build
docker-compose exec rails bundle exec rails db:create db:migrate db:seed
```

Open: [http://localhost:3000](http://localhost:3000)

## Command Line Examples

Type commands in the bottom command bar:

- `help`
- `models`
- `search welcome`
- `posts search mobile page 1 per 10`
- `create post title='Hello' body='From CLI'`
- `post.create(title:'Dotted syntax')`
- `post translations`
- `post revisions`
- `post audits`

CLI responses include clickable links in UI output.

## Testing

Run all tests:

```bash
bin/rails test
```

Run system tests only:

```bash
bin/rails test test/system
```

Notes:
- System tests use Capybara + Playwright (`driven_by :playwright`).
- Test coverage uses [polyrun](https://rubygems.org/gems/polyrun) **`~> 1.3.0`** (stdlib `Coverage` via `Polyrun::Coverage::Rails` in `test/test_helper.rb`; not SimpleCov). Disable with `POLYRUN_COVERAGE_DISABLE=1`.
- Current minimum line coverage gate in demo app is `30%` (`test/test_helper.rb`).

## Boot Profiling

Optional boot timing output:

```bash
BOOT_PROFILE=1 bin/rails runner 'puts "boot ok"'
```

# Sinatra Demo (Clickable App + E2E)

This folder contains a fully working Sinatra app with a social-style UI:

- Posts
- Issues
- Pull Requests
- Profile timeline
- Per-item Translations, Revisions, and Audits sections on the show page

It also demonstrates ActiveVersion runtime-adapter wiring for non-Rails environments and includes an E2E test suite.
The `WorkItem` model uses `plugin ActiveVersion::Adapters::Sequel::Versioning` and `active_version(...)` DSL for audits/revisions/translations.

## Stack

- App: Sinatra + Sequel + SQLite
- Tests: RSpec + Capybara
- Browser E2E: Capybara Playwright driver

Main test framework is RSpec (chosen for consistency with this repository).

## Quick start

```bash
cd examples/sinatra_demo
bundle install
bundle exec rackup -p 4567
```

Then open [http://localhost:4567](http://localhost:4567).

## Run tests

```bash
cd examples/sinatra_demo
bundle exec rspec
```

## Enable Playwright browser tests

Install Playwright browsers once:

```bash
cd examples/sinatra_demo
bundle exec ruby -e 'require "playwright"; Playwright.create(playwright_cli_executable_path: "npx playwright") {}'
npx playwright install chromium
```

Then run JS tests:

```bash
bundle exec rspec spec/e2e/playwright_spec.rb
```

If Playwright driver is unavailable, the Playwright spec is skipped while non-JS feature tests still run.

## Files

- `app.rb` - Sinatra application and Sequel runtime adapter setup
- `app/views/*` - ERB templates
- `app/public/styles.css` - UI styling
- `spec/e2e/*` - E2E suite
- `runtime_adapter_example.rb` / `sequel_like_runtime_adapter_example.rb` - runtime adapter contract examples

## Runtime-adapter examples

```bash
ruby examples/sinatra_demo/runtime_adapter_example.rb
ruby examples/sinatra_demo/sequel_like_runtime_adapter_example.rb
```

These scripts show:

- assigning `ActiveVersion.runtime_adapter`
- using `ActiveVersion.with_context`
- resolving connections through `ActiveVersion.with_connection`
- creating and reading translations, revisions, and audits with Sequel plugin APIs

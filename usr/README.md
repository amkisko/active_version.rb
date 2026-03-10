# Dev environment (usr)

Use it for isolated, script-driven, or bot-driven development (e.g. CI-like runs, bots, automation).

## Purpose

- Scripts and tooling that maintainers and automation run from the repo (e.g. release, analyze, sample test runner).
- Optional local dev stack under `usr/etc/local/` to run tests and commands in a container with a fixed Ruby/DB stack.
- Clarity that nothing under `usr/` is part of the gem; the gemspec explicitly excludes it.

## Layout

```
usr/
├── README.md          # This file
├── bin/               # Executable scripts (run from repo root or usr/bin)
│   ├── release.rb     # Release checklist: bundle, appraisal, rubocop, rspec, build, push, tag
│   ├── analyze.rb     # Library structure and quality analysis → tmp/analyze.log
│   └── rspec_sample.rb # Run rspec, output first failure only (for tooling)
└── etc/
    └── local/         # Optional: isolated Docker-based dev/test (see below)
```

## Running scripts

From the repository root (recommended):

```bash
bundle exec ruby usr/bin/release.rb
bundle exec ruby usr/bin/analyze.rb
bundle exec ruby usr/bin/rspec_sample.rb
```

Or run with Ruby directly (scripts use repo root when invoked without args):

```bash
ruby usr/bin/analyze.rb
ruby usr/bin/rspec_sample.rb
```

## Isolated dev/test (usr/etc/local)

For a reproducible, isolated environment (e.g. agentic or bot-driven runs), use the minimal Docker setup under `usr/etc/local/`:

- Dockerfile: Ruby + Bundler; no app code in the image.
- docker-compose.yml: Mounts the repo and runs commands there (e.g. `bundle install`, `bundle exec rspec`).

From the repository root:

```bash
cd usr/etc/local
docker compose run --rm app bundle install
docker compose run --rm app bundle exec rspec
```

Or a one-liner from repo root:

```bash
docker compose -f usr/etc/local/docker-compose.yml run --rm -w /app app bundle exec rspec
```

This keeps the host clean and gives a consistent Ruby/Bundler environment for automation.

## Relation to workspace-wide usr

If this repo lives under a workspace that has a top-level `usr/` (shared dev container with SSH, mise, etc.), you can use that for full interactive development. The `usr/` inside this repo is for:

- Scripts and automation that belong to this project.
- A minimal, self-contained way to run tests in isolation without depending on the workspace layout.

## Gem distribution

The gem’s file list in `active_version.gemspec` explicitly excludes `usr/`. Only `lib/`, docs, and standard gem files are packaged. Anything you add under `usr/` stays in the repo and is available to anyone who clones it.

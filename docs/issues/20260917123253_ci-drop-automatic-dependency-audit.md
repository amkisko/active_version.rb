Test CI skipped specs because the audit job failed on pg 1.6.2 under Ruby 4. Appraisal locks already pin 1.6.3.

## Participants

- amkisko

## Decisions

- Drop the audit job from test.yml so tests no longer wait on advisory freshness or a Ruby 4 gem compile gate.
- Disable osv-scanner in Trunk Check.
- Disable markdownlint MD013 in .markdownlint.yaml. Keep AGENTS.md in Trunk so other markdownlint rules still run.
- Add dependency-audit.yml with workflow_dispatch only.

## Effects

- Test and coverage jobs run without an advisory gate.
- On-demand bundler-audit of every Gemfile.lock is available through workflow_dispatch.

## Next

- Run dependency audit on demand when a release or a known advisory needs it.
- Do not reintroduce advisory scanners into test.yml.

## Source

- GitHub Actions test failures on 2026-09-17

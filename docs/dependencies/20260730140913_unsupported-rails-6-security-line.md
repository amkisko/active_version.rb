# Unsupported Rails 6 security line

## Dependency

Rails and Active Support 6.1 in the rails6 appraisal and the library's former runtime compatibility floor.

## Symptom

The Rails 6 graph could not satisfy the repository policy that every maintained compatibility graph resolve to supported versions with available security fixes. Keeping the appraisal also implied support that the current CI matrix could not safely prove.

## Evidence

The portfolio dependency audit found advisory-bearing legacy Rails graphs while the current Rails 7.2 and 8.1 graphs resolved to patched versions. The rails6 appraisal was removed, and the runtime Active Support and development Active Record floors now begin at 7.2.3.2.

The complete root make test command passed after the compatibility change. All remaining root, appraisal, and example Ruby lockfiles passed bundle-audit.

## Suggested fix

Support Rails 7.2.3.2 through Rails 8 only. Users that must remain on Rails 6 should pin an older library release and treat that framework line as unsupported.

## Next

- Keep the minimum Rails floor synchronized between the gemspec, examples, documentation, and CI.
- Add a new compatibility line only when it can be continuously tested and kept advisory-clean.

## Source

- active_version.gemspec
- Appraisals
- .github/workflows/test.yml
- README.md
- examples/rails_demo/Gemfile.lock
- examples/sinatra_demo/Gemfile.lock

---
name: engineering-audit
description: >-
  Audit code with an evidence-first, pipeline-aware review format. Use for
  engineering audits, systems reviews, hot-path and Big-O analysis, and
  pipeline inspection. When the system has external services, devices,
  operators, or physical actuators, also run boundary and control mode.
---

# Engineering audit

Use when asked for an engineering audit, systems review, hot-path analysis, Big-O review, or pipeline-style inspection.

Read `engineering-audit.md` in this skill directory for dimensions, stage checks, boundary and control mode, finding format, and ranking.

## Quick reference

Pipeline:

```text
ingress → app logic → cache → database → queue → worker → external API → egress
```

Order findings by danger, then certainty, then impact, then fix cost. Present the smallest credible fix before structural rewrite. Separate missing coverage from futile coverage.

When the system has external services, devices, operators, or physical actuators, also run boundary and control mode: who commands whom, interface deviations, and whether intended, commanded, reported, inferred, and physical state can diverge without an alarm.

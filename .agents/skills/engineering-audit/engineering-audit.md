# Engineering audit (pipeline + evidence)

Use when asked for an engineering audit, systems review, hot-path analysis, Big-O review, or pipeline-style inspection. When the system talks to external services, devices, operators, or physical actuators, also run boundary and control mode below.

## Voice and prose

Structured finding fields stay as specified below. Free-form audit text stays blunt, compressed, and evidence-first. No engagement filler.

- no sales language, trend packaging, or methodology pitches;
- no negation-first hooks; state the fact and move on;
- do not repeat the same claim in positive and negative form in adjacent lines;
- prefer commas, colons, semicolons, and full stops over em dashes;
- findings destined for `usr/docs/issues/`: plain prose, no markdown tables, bold, italic, or other styling unless the repository explicitly allows it.

## Role

Operate as a senior engineer. Treat the system as a pipeline:

```text
ingress → app logic → cache → database → queue → worker → external API → egress
```

Map each finding to a stage when relevant.

## Eight core dimensions

Scan for:

1. broken or incomplete behavior;
2. inadequate test coverage;
3. futile test coverage (distinguish explicitly from missing coverage);
4. redundancy and tangled ownership;
5. code quality and organization that hurts maintenance;
6. asymptotic and hot-path shape (N+1 queries, repeated scans, probable O(n²) regions);
7. purpose and ownership (ground dead-code claims with tree and search evidence);
8. language-native features the code fights instead of using.

## Pipeline stage checks

When the audit scope includes these layers, inspect explicitly.

Cache: key design, TTL correctness, stampede protection, invalidation ownership, whether misses amplify upstream load.

Database: N+1 queries, unbounded result sets, missing indexes, lock contention, tenant or shard skew hotspots.

Queue and worker: retry storms, poison jobs, duplicate work, drain rate versus enqueue rate, starvation, head-of-line blocking, missing backpressure, idempotency gaps.

External API: jobs orchestrate; client adapters own protocol details; retries, backoff, and idempotency tested at the correct boundary.

## Systems lens

Ask where work waits, repeats, bottlenecks, or amplifies; where load skews; where latency spikes or throughput caps; where idempotency or bounds are missing.

## Boundary and control mode

Run this mode when the audited system has external services, devices, operators, or physical actuators. Skip it for a library with no IO. Keep the same finding fields. Optional extra fields when they help: who commanded what; how the command went wrong (missing, harmful, mistimed, held too long); which state (intended, commanded, reported, inferred, physical).

Shared trust matters more than how many integrations you count. One identity or unlock service that every actuator trusts fails everyone together; many independent read-only feeds usually do not.

Sketch who commands whom, what feedback returns, and who is allowed to command a physical or identity-changing action. Then for each command (send, unlock, bind identity, show results, type a device message):

- required command not sent;
- harmful command sent;
- sent too early, too late, duplicated, or out of sequence;
- applied too long or stopped too soon.

At each interface, try: no message, duplicate, stale, late, wrong identity, wrong unit or encoding, wrong destination, other than the intended device or person.

Name five states when they can diverge without an alarm: intended, commanded, reported, inferred, observed physical. Software consensus against a disagreeing physical process is higher danger than a clean crash.

Ask whether any safety check is independent of the integration it polices. A freeze, match, or occupancy bit that lives inside the same shop or device path only checks that path.

Ask about hazards from a correctly functioning dependency whose assumptions are false: label uniqueness, occupancy listing freshness, a sensor or classifier outside its training conditions.

Ask who remains operational after partial failure, and whether two commanders can both believe they own the same lock, order, or identity.

A logically valid command that moves a lock, types a scale, or labels a sample is a safety and privacy event. Hand spoofable identity keys and missing TLS verify to security review.

Human: can an operator or customer act on a stale or colliding label, and can they tell empty, occupied, refused, or never-synced apart.

Related: `io-simulation` injects those interface faults in a plant; `finite-state-machines` names digital and physical lifecycles.

## Required output per finding

| Field | Content |
|-------|---------|
| Severity | critical, high, medium, low |
| Confidence | high, medium, low |
| Location | file, symbol, endpoint, queue, job, query, worker, or subsystem |
| Why it matters | short, concrete |
| Kind | observed fact vs inference |
| Smallest credible fix | minimal change that addresses the issue |
| Deeper fix | optional structural change when the small fix is insufficient |

Label every claim not proven by code, tests, logs, traces, or query plans as inference and include the exact check needed to confirm or reject it.

## Ranking

Order work by danger, certainty, impact, and fix cost. Present the smallest real fix first.

## Subsystem and hot-path mode

When inspecting a subsystem for hot paths:

1. identify likely hot paths (handlers, serializers, loops over large collections, ORM-heavy paths, workers);
2. estimate rough complexity of main loops;
3. rank fixes by likely payoff versus implementation risk;
4. no micro-optimizations without bottleneck evidence.

## Ignore

Stylistic trivia unless it harms correctness, operability, maintainability, or auditability under realistic load. Theatrical severity without evidence.

## Checklist before finishing

- findings mapped to pipeline stages where relevant;
- boundary mode run when external services, devices, operators, or actuators exist, or explicitly skipped with reason;
- missing versus futile coverage separated;
- each finding has severity, confidence, location, kind, smallest fix;
- inferences label the confirming check;
- ranked by danger, certainty, impact, fix cost;
- purpose and ownership claims grounded in tree plus search evidence.

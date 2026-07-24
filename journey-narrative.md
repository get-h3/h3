# How a Hermes Agent Bootstrapped Its Own Coding Fleet

> **A teaching narrative.** This document explains WHY each piece of this stack exists — what problem forced its creation, and what it unlocked next. If you're another Hermes agent trying to understand or reproduce this architecture, read the problems before the solutions. The tools make sense only when you know what they're running from.

---

## 1. Genesis — The Blank Hermes Install

You have a fresh Hermes Agent. It runs once when you talk to it and stops. It has no memory between sessions, no ability to check on things while you sleep, no way to keep multiple projects moving without you explicitly managing each one.

The first thing we built was a **skill**. Not a cron job, not a scheduler, not a worker — a skill. Specifically, skills that encoded *what we learned about making Hermes effective*: how to write prompts that don't drift under load (`prompt-foundry`), how to debug by eliminating the impossible (`sherlock-deduction`), how to do deep research with real citations. Wojons dropped a series of gists — dense, opinionated, battle-tested — and we turned each one into a self-describing SKILL.md file that a model could load on its own.

**Why skills first?** Because every subsequent tool would need to know *how* to do things. A cron job without a skill is just a blind timer. A foreman without skills is just a model burning tokens guessing at conventions. Skills are the operating system's instruction set — everything else runs on top of them.

But skills alone meant a human still had to trigger everything. We wanted code written while we slept. So we built **cron jobs**.

## 2. From Cron Jobs to a Fleet — The First Pain

Cron jobs worked. A cron job fires, loads the right skills, does the work, reports back. One project, one cron — simple.

Then we had five cron jobs. Then ten. Then twenty-five.

**The first major pain point:** every cron job had its own inline prompt. When we improved the foreman workflow — fixing a bug, adding a self-heal step, changing the worker spawn pattern — we had to update every cron job's prompt body individually. Most of them drifted. Some referenced skills that no longer existed. Others had the old spawn patterns hardcoded.

We built `coding-hermes-cron` — a **canonical schema skill** — because cron drift kept silently breaking the fleet. This skill defines exactly what a valid cron job looks like: the schedule format (must be a dict, never a plain string — because plain strings crash the scheduler's `get_due_jobs()`), the model/provider pattern, the skills array, the workdir convention. It became the single source of truth. The supervisor loads it to heal broken foremen. Foremen load it to validate themselves.

**What this unlocked:** we could now audit the fleet against a schema. Before the canonical cron spec, we didn't even know how many foremen were configured wrong. After it, the supervisor could detect drift automatically.

## 3. The Scheduling Problem — Why We Built the Broker

With 25+ cron jobs on fixed intervals, we hit a second pain point: **no coordination, no backpressure.**

Every cron fired on its own static schedule. Some projects needed attention every 15 minutes. Others were essentially done but still burned tokens every 4 hours doing discovery sweeps that found nothing. We discovered that 13 projects were in idle/complete state, collectively burning 150-300K tokens per day running the exact same checks: build, test, vuln scan, TODO scan. Zero productive output.

Worse: when a project stalled, its cron just kept firing. When a project was on fire, its cron couldn't fire any faster.

We built the **weight-budget knapsack scheduler** (`coding-hermes-broker`) because we needed to answer one question: "given that I can only run N things at once, what should I run RIGHT NOW?"

The scheduler has two independent axes:
- **Weight** (1-100): how much of the concurrency budget a project consumes when it runs
- **Priority** (1-10): how aggressively the project seeks a slot, powered by an urgency formula that ensures starvation is mathematically impossible

This let us differentiate: a high-priority, low-weight project runs constantly and costs almost nothing. A low-priority, high-weight project rarely runs but dominates the budget when it does. The urgency decay function means even a priority-1 project eventually runs — the system can't starve anything.

**What this unlocked:** we could add dozens of projects without worrying about scheduling collisions. The scheduler decides; we don't manually configure intervals.

## 4. The Three-Tier Architecture — Why Separate Concerns

Once we had scheduling, we needed execution. The naive approach — one agent looping through tasks — failed in specific, predictable ways.

**Pain point #1: Workers burned the foreman's provider key.** `delegate_task` inherited the parent's model and provider. The foreman was on PAYG (DeepSeek) so it could always load. But when workers used `delegate_task`, they silently charged the PAYG account instead of the prepaid flat-rate buckets they were supposed to burn through. One foreman racked up a noticeable bill before we noticed.

The fix was architectural, not textual: we removed `delegation` from foremen's enabled toolsets entirely. Worker spawning moved to `hermes chat -q -m <model> --provider <prepaid-bucket>` — explicit provider, explicit model, no inheritance.

**Pain point #2: Foremen that can't load are dead foremen.** A foreman on a prepaid plan that locks (bucket exhausted) can't load its skills, can't read its board, can't spawn workers. The entire project goes dark until the billing cycle resets. The golden rule emerged: **foremen MUST be on PAYG.** PAYG is always rescuable — add credit, foreman comes back online. Workers burn prepaid buckets; when one locks, the foreman auto-switches to the next.

This is why the architecture became three tiers:

```
Bane + Hermes          ← Strategy, architecture, fleet commands
    │
Supervisor (1)         ← Fleet-level: heal, audit, rebalance, report. Runs every 4h.
    │
Foremen (25+)          ← Per-project: scan board, compile prompts, spawn workers
    │
Workers (spawned)      ← Ephemeral: write code, run tests, commit, die
```

Each tier has its own provider strategy, its own failure mode, and its own recovery path.

## 5. The Pipeline Flow — From Task to Commit

Here's how code actually gets written. A foreman tick fires (triggered by the scheduler). This is the 10-step loop:

```
TICK FIRES
  │
  0. SELF-HEAL — git identity, pull, dependency fixes, transient cleanup
  │
  1. READ BOARD — .coding-hermes/tasks.md, picks highest-priority task
  │   └── Board empty? → 1.5 DISCOVERY SWEEP (build/vet/test/lint/vulns scan)
  │       ├── Found work? → create tasks → loop back
  │       └── Nothing + E2E passes? → self-pause (graduated: 3 idle ticks → longer interval → pause)
  │
  2. HILO IMPACT ANALYSIS — code graph: what depends on what, blast radius
  │
  3. DUCKBRAIN RECALL — load past decisions, pitfalls, patterns for this project
  │
  4. PRE-LOAD — assemble context package through prompt-foundry
  │   (Worker gets ONE message — no skills, no architecture, no fleet context)
  │
  5. SPAWN WORKER — hermes chat -q, independent model/provider, coding bucket
  │   Worker loads coding-hermes-worker skill: read first, match conventions, write tests, build before commit
  │
  6. GITREINS GUARD — Tier 1: secrets, build, lint, tests
  │
  7. GITREINS JUDGE — Tier 2: LLM evaluation vs acceptance criteria
  │
  8. COMMIT — targeted add only, co-author mandatory, descriptive message
  │
  9. OFF-BY-ONE — submit solved problem, discover cached solutions for next task
  │
  10. DUCKBRAIN WRITE — store findings, patterns, pitfalls, idle counter
  │
  1.6 SCAN SIGNALS — external changes, CI status, new issues, dependencies
  │
  ➡️ NEXT TASK
```

**Why each step exists in that order:**

- **Self-heal (Step 0)** came first because foremen kept stalling on git identity errors — wrong email on commits, missing remotes, uncommitted changes from previous failed ticks. Before self-heal, the foreman would hit a git error on Step 8 and waste the entire tick.

- **DuckBrain recall (Step 3)** exists because foremen walked into projects blind every tick. Without loading `/project/<name>/status`, they didn't know what architecture decisions were made, which models worked, what was already built. They burned tokens rediscovering. With DuckBrain, they walk in with memory — they know the project like they never left.

- **Hilo (Step 2)** exists because workers kept "fixing one thing and breaking three others." Without dependency graph analysis, a worker touching `parser.go` had no idea that `lexer.go`, `ast.go`, and `formatter.go` depended on it.

- **GitReins guard + judge (Steps 6-7)** exist because workers are LLMs — they make mistakes. The guard catches mechanical failures (broken build, failing tests, leaked secrets). The judge catches semantic failures (does this actually meet the acceptance criteria?). Together they're a quality gate that catches what unit tests miss.

- **Off-by-One (Step 9)** exists because we kept solving the same problems in different projects. A parser fix for one Go project was the same parser fix another project needed. Off-by-One is a pre-solve cache — submit what worked, discover cached solutions for similar tasks. It's cross-project learning.

## 6. Why Each MCP Server Exists

**DuckBrain MCP** — because foremen have no memory between ticks. Without DuckBrain, every tick is Day One. DuckBrain is a git-backed persistent store where foremen write and read project state, decisions, pitfalls, and patterns. The `hermes-dagger` namespace alone has 50+ findings — bugs, CI fixes, thread exhaustion incidents — that the foreman loads before touching code. Without DuckBrain, the foreman repeats every mistake.

**GitReins MCP** — because LLM-written code needs automated quality gates. GitReins provides `guard_run` (Tier 1: secrets, build, lint, tests) and `judge_evaluate` (Tier 2: LLM evaluation against acceptance criteria). It also manages tasks with `task_create`/`task_start`/`task_complete`. Before GitReins, foremen committed broken code and discovered the failure next tick. With GitReins, the commit is blocked if the code doesn't pass.

**Chimera MCP** — because sometimes you need multiple models deliberating on the same question. Chimera runs multi-model deliberation with configurable formations. When a foreman encounters a genuinely hard architectural question — the kind where one model's blind spot is another model's strength — Chimera synthesizes a merged answer from multiple perspectives.

**Google Flights MCP** — an example of domain-specific infrastructure. The fleet doesn't just write code; it handles real-world logistics. This MCP exists because travel planning benefits from structured data that a general-purpose LLM shouldn't have to scrape from web pages.

## 7. The Self-Improvement Loop — Failure → Skill → Smarter Fleet

This is the most important pattern in the entire stack. Here's how it works:

### Phase 1: A failure happens.

On July 19, 2026, the gateway went down. Every process under UID 1000 died. Terminal sessions, background daemons, editors, the gateway itself — gone. The logs showed `killpg(1)` — a process group kill targeting PID 1, which is init, which is *everything*.

### Phase 2: Root cause is found.

It was a Python `MagicMock` object. A unit test mock that, when serialized through a particular code path, resolved to PID 1 — and a process-group kill meant to clean up the test harness instead killed every process owned by the user.

### Phase 3: The fix is encoded as a skill or reference document.

The MagicMock incident became a diagnostic checklist in the supervisor's reference library. The `coding-hermes-supervisor` skill (version 2.41.0) now has 70+ reference documents covering every failure mode the fleet has ever hit — TasksMax exhaustion, killpg(1) from MagicMock, scheduler amplification, context length starvation, LSP idle reaper, gateway memory tuning, cron background review hangs, v0.18 schedule format crashes, and dozens more.

### Phase 4: The fix prevents the failure from recurring.

Because skills are self-describing and foremen auto-load them, every foreman now knows: don't use `delegate_task` (burns PAYG), always use `timeout` on GitReins guard calls (prevents zombie hangs), never use plain-string schedule formats (crashes the scheduler), check for bg-review hangs after 49+ tool turns, verify co-author is set before committing, wrap builds in GOMAXPROCS control when thread exhaustion is detected.

### Phase 5: The fleet gets smarter every time it breaks.

This is the real architecture. Not the three tiers. Not the cron schedules. The architecture is the accumulated knowledge of every failure, encoded into skills that prevent the next one.

Look at the `coding-hermes-north-star` pitfalls list — it's 20+ entries, each a story:
- **Foreman cron prompts go stale** — the inline prompt body doesn't auto-update when skill text changes. Keep cron prompts minimal.
- **Cron skill-not-found is a silent failure** — a cron referencing a missing skill logs a warning but the scheduler marks it `ok`. The supervisor validates every skill reference against the filesystem.
- **Never-done audit must create tasks, not just report gaps** — 80+ ticks of "SECURITY.md missing" with zero action. Every audit finding must produce a matrix row.
- **Verify hooks exist before building plugins** — an entire plugin was built against a nonexistent `terminal.command.transform` hook. Before wiring anything, grep the hook registry.
- **Unit tests are not enough** — foremen routinely mark features "done" after unit tests pass, without ever starting the server or running real queries. For RethinkDB, 22,000 lines of CDC/vector/FTS/partition code were written with zero end-to-end verification.
- **The 99% complete task board trap** — foremen declare projects done at Level 2 (functional, shim tests pass) when the completeness-validator's 5 levels reveal only surface completion.
- **LSP idle reaper must survive upgrades** — 56 gateway crashes in one day traced to orphaned gopls processes. The fix was auto-stashed and lost during a Hermes update. After every upgrade, check `git stash list`.

### The Dependency Chain of Smarter Tools

This self-improvement loop doesn't just produce better skills — it produces better tools:

1. **Skills → Cron jobs.** A proven approach encoded as a skill becomes a cron job that runs autonomously.

2. **Cron drift → Canonical schema.** When cron jobs drift from each other, we build a schema to validate them against.

3. **Schema validation → Supervisor.** When validating 25+ crons manually becomes impossible, we build a supervisor cron that audits the entire fleet.

4. **Supervisor blind spots → DuckBrain.** When the supervisor can't remember what it found last audit, we give it persistent memory.

5. **DuckBrain namespace collisions → Switch protection.** When foremen corrupt each other's data by switching the default namespace, we harden the API to require explicit namespace parameters.

6. **Rate limit cascades → Provider palettes.** When a single provider outage blocks multiple foremen, we build multi-provider fallback chains.

7. **Worker provider leakage → Toolset surgery.** When text instructions can't prevent `delegate_task` usage, we remove the tool from the agent's capabilities entirely.

Each tool was built because the previous tool's limitations caused a specific, measurable failure. Each tool unlocked the next by removing a bottleneck that nobody could see until the previous bottleneck was gone.

## 8. How to Reproduce This Stack

If you're another Hermes agent trying to build something like this, here's the order:

**Start with a skill.** Pick a thing you do repeatedly. Encode it as a SKILL.md. Make it self-describing — a model should be able to read the description and know when to load it.

**Run it as a cron.** `hermes cron create` with a simple prompt: "Load skill X, do Y, report." The cron fires on a schedule. You wake up to results.

**Add DuckBrain memory.** The cron writes its state to DuckBrain after every tick. Next tick, it loads its state first. Now you have continuity across runs.

**Add a second cron.** Now you have drift. Build a schema skill that defines the canonical shape of a cron. Use it to validate both crons.

**Add a supervisor.** A meta-cron that audits all other crons against the schema, heals broken ones, and produces a health report.

**Add GitReins.** Before any code commit, the guard must pass. Secrets scan, build, lint, tests. The judge evaluates against acceptance criteria.

**Add Hilo.** Before touching code, understand the dependency graph. What depends on what?

**Add Off-by-One.** Every solved problem is a cached solution. Every new task checks the cache first.

**Add the scheduler.** When you have 5+ projects, fixed cron intervals stop working. The weight-budget knapsack scheduler decides what runs when.

**Encode every failure as a skill.** The MagicMock incident becomes a reference document. The LSP leak becomes a reference document. The schedule format crash becomes a reference document. Your fleet is now accumulating institutional knowledge.

## 9. The Philosophy

**Foremen run on PAYG.** A foreman that can't load is a foreman that can't schedule work, and a foreman that can't schedule work is a dead project. PAYG is the heartbeat — it must never stop.

**Workers run on prepaid flat-rate plans.** Workers are disposable. If a worker burns through its quota mid-task, the foreman notices, kills it, and spawns a replacement on a different provider. The quota is a leash, not a lifeline.

**The system must survive model provider outages.** Any single provider going dark should be a speed bump, not a wall. Six commercial APIs with enumerated fallback chains.

**Context length is a trap.** 1M tokens of accumulated context makes every tick cost 180 seconds of prompt processing. The most efficient foremen are the ones with the tightest context windows.

**Trust but verify.** Foreman self-reports ("all tests pass," "Phase 0 complete") are progress indicators, not proof. Always run actual tests, check actual git commits, hit actual endpoints.

**Every failure is a skill.** The fleet gets smarter every time it breaks. That's the real architecture — not the three tiers, not the cron schedules, but the accumulated knowledge of every failure, encoded into skills that prevent the next one.

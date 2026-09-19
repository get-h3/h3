# Stand-in workdir to target board resolution — the theater-row class

**Scope:** every satellite lane whose tick runs from a stand-in workdir — PM
(`~/.hermes/stand-in/pm-lane/<project>`), QA (`~/.hermes/stand-in/pm/<project>`), dogfood
(`~/.hermes/stand-in/dogfood/<project>`), sync (`~/.hermes/sync-workdirs/<project>-sync`) — plus the
`scheduler.db` `pm` namespace prompt and the PM cycle skills that name a board path.
**Status:** binding for all board writers — PM cycles, QA and dogfood lanes, sync lanes, foremen.
Prompt and skill fix: fleet-wide. Satellite links: applied to the **h3 family only** (DF-H3PM-04,
foreman tick #406).

## The rule

Rule: anchor every board path at the TARGET project's workdir — never at the directory the tick runs in

A satellite tick's cwd is a stand-in path. Its `<standin>/.coding-hermes/` is empty by design (or, on
some lanes, a link — see below). A board row written cwd-relatively into a stand-in directory is
invisible to the foreman that owns the project, is never dispatched, and is never closed: the write
succeeds, the row is theater. Gate G4 (`coding-hermes-project-manager`, "Scheduler sees it") asks
only whether the board is at *the path the foreman reads* — which is true of the TARGET's board and
false of the stand-in's, so the gate must be read with the anchor, not cwd-relatively.

Corollaries:

- **Resolve TARGET first, every cycle, before reading or writing any board path.** The name suffix is
  lane metadata, not part of the project name: `h3-pm` → `h3`, `h3-qa` → `h3`, `h3-dogfood` → `h3`.
  The workdir comes from the scheduler DB, never from `$PWD` and never from
  `basename "$PWD"`.
- **A stand-in `.coding-hermes/` is empty by design.** Never create `tasks.md`, `tasks.jsonl` or
  `events.jsonl` under one. If TARGET does not resolve to a workdir with a real board file, STOP and
  report ESCALATE — "writable" is not the same as "read".
- **`ls` cannot tell an empty stand-in dir from a live link.** Both show a `board` entry; only
  `readlink -f <standin>/.coding-hermes/board` proves which file a cwd-relative write lands in. The
  satellite pattern (below) makes a cwd-relative write correct-by-construction — but only after the
  link is verified.
- **Gate G4 now carries the anchor.** For the TARGET resolved by the recipe, the board is
  `<TARGET_WORKDIR>/.coding-hermes/board/tasks.jsonl` (with `events.jsonl` beside it) — never a path
  under `~/.hermes/stand-in/**` or `~/.hermes/sync-workdirs/**`.
- **The same anchor applies to every reader**, not just the PM: a QA or dogfood lane that verifies or
  dedupes against a stand-in board reads an empty file and reports "nothing outstanding" for a
  project with open rows.

## The resolution recipe

```bash
TARGET="${CODING_HERMES_PROJECT%-pm}"     # strip the lane suffix (-pm / -qa / -dogfood)
TARGET_WORKDIR=$(sqlite3 ~/.hermes/coding-hermes/scheduler.db \
  "SELECT workdir FROM projects WHERE name='$TARGET';")
BOARD="$TARGET_WORKDIR/.coding-hermes/board/tasks.jsonl"   # + events.jsonl for row history
readlink -f "$BOARD"                                       # prove which file you are about to touch
```

Measured on this host (2026-09-19), for the two enabled h3-family satellites:

```bash
sqlite3 ~/.hermes/coding-hermes/scheduler.db "SELECT name,workdir FROM projects WHERE name IN ('h3','h3-pm','h3-qa','h3-dogfood','h3-umbrella-sync');"
```

```
h3                              /home/kara/get-h3/h3
h3-pm                           /home/kara/.hermes/stand-in/pm-lane/h3
h3-qa                           /home/kara/.hermes/stand-in/pm/h3
h3-dogfood                      /home/kara/.hermes/stand-in/dogfood/h3
h3-umbrella-sync                /home/kara/.hermes/sync-workdirs/h3-umbrella-sync
```

So the four h3 satellites all resolve to `TARGET=h3` and therefore to the single board
`/home/kara/get-h3/h3/.coding-hermes/board/tasks.jsonl`.

## The satellite link pattern (and its readlink proof)

The pattern is a link named `board` **inside** `.coding-hermes` (not a link named `.coding-hermes`):
the lane keeps its own real `.coding-hermes/` for its own artifacts (`dogfood-log.md` and friends),
while the board directory itself resolves to the owner's.

```bash
mkdir -p ~/.hermes/stand-in/pm-lane/h3/.coding-hermes
ln -s /home/kara/get-h3/h3/.coding-hermes/board ~/.hermes/stand-in/pm-lane/h3/.coding-hermes/board
readlink -f ~/.hermes/stand-in/pm-lane/h3/.coding-hermes/board
# -> /home/kara/get-h3/h3/.coding-hermes/board
```

Precedent, present on this host before this work and not created by it:

```bash
ls -la /home/kara/.hermes/stand-in/pm/hermes-dagger/.coding-hermes/
readlink -f /home/kara/.hermes/stand-in/pm/hermes-dagger/.coding-hermes/board
```

```
board -> /home/kara/hermes-dagger/.coding-hermes/board
/home/kara/hermes-dagger/.coding-hermes/board
```

Rules for applying it:

- **Never overwrite.** If the target path already exists as a real file or a real directory, STOP on
  that entry and report it — a real `board/` under a stand-in may already hold rows that have to be
  moved to the owner board first (see the fleet-wide remainder).
- **The link target must exist and be a directory** (`[ -d <TARGET_WORKDIR>/.coding-hermes/board ]`)
  before the link is created; a dangling link re-creates the silent-write failure in a form that
  `readlink -f` reports as the link path itself.
- **Prove it after creating it** by reading through the link — `wc -l < <standin>/.coding-hermes/board/tasks.jsonl`
  must return the owner's row count, not 0.

## Measured before-state (2026-09-19, tick #406)

| stand-in dir | before | after |
|---|---|---|
| `~/.hermes/stand-in/pm-lane/h3` | `.coding-hermes/` existed with ZERO entries | `board -> /home/kara/get-h3/h3/.coding-hermes/board` |
| `~/.hermes/stand-in/pm-lane/h3-sdk-go-foreman` | `.coding-hermes/` existed with ZERO entries | `board -> /home/kara/get-h3/sdk-go/.coding-hermes/board` |
| `~/.hermes/stand-in/pm-lane/h3-sdk-python-foreman` | `.coding-hermes/` existed with ZERO entries | `board -> /home/kara/get-h3/sdk-python/.coding-hermes/board` |
| `~/.hermes/stand-in/pm-lane/h3-sdk-typescript-foreman` | `.coding-hermes/` existed with ZERO entries | `board -> /home/kara/get-h3/sdk-typescript/.coding-hermes/board` |
| `~/.hermes/stand-in/pm-lane/h3-shim-foreman` | `.coding-hermes/` existed with ZERO entries | `board -> /home/kara/get-h3/shim/.coding-hermes/board` |
| `~/.hermes/stand-in/pm/h3` | NO `.coding-hermes` at all | `board -> /home/kara/get-h3/h3/.coding-hermes/board` |
| `~/.hermes/stand-in/dogfood/h3` | NO `.coding-hermes` at all | `board -> /home/kara/get-h3/h3/.coding-hermes/board` |
| `~/.hermes/sync-workdirs/h3-umbrella-sync` | NO `.coding-hermes` at all | `board -> /home/kara/get-h3/h3/.coding-hermes/board` |

All eight resolve to the owner board and read the owner's real rows through the link — `h3` 205,
`sdk-go` 76, `sdk-python` 85, `sdk-typescript` 65, `shim` 104; the four h3 satellites
(`pm-lane/h3`, `pm/h3`, `dogfood/h3`, `sync-workdirs/h3-umbrella-sync`) each read the same 205-row
umbrella board. Before the links, three of those four had no `.coding-hermes` at all and the fourth
had an empty one.

The class is not hypothetical. Two stand-in dirs outside the h3 family were found holding REAL local
board files, and none of their rows exist on the owner board — the theater write, caught live:

```bash
ls -la /home/kara/.hermes/stand-in/pm/off-by-one/.coding-hermes/board/
ls -la /home/kara/.hermes/stand-in/pm/hermes-canopy/.coding-hermes/board/
```

```
-rw-rw-r-- 1 kara kara 1559 Sep 17 17:14 tasks.jsonl    # off-by-one QA stand-in
-rw-rw-r-- 1 kara kara  662 Sep 16 16:59 tasks.jsonl    # hermes-canopy QA stand-in
```

```
QA-OFF-BY-ONE-QA-1        on-owner-board=0    (owner board has 123 rows)
QA-OFF-BY-ONE-QA-2 [P1]   on-owner-board=0
QA-HERMES-CANOPY-QA-1     on-owner-board=0    (owner board has 360 rows)
```

Three rows, one of them P1 ("QA battery launch phase never executed"), that no foreman has ever read.

## The prompt and the skills (the fleet-wide half of the fix)

The symlinks are per-directory and can only cover what exists today; the anchor has to travel with the
tick. Two edits carry it:

- **`scheduler.db` `namespaces.default_prompt` for `id='pm'`** — one appended final paragraph
  ("TARGET RESOLUTION - which board you read and write…"). The DB is authoritative; `~/.hermes/fleet.toml`
  is EMITTED from it by `~/.hermes/scripts/fleet-cooldown-policy.py`, so editing the TOML is wrong and
  would be overwritten on the next regen. The append is concatenation, not replacement: the original
  prompt text is preserved as a prefix.
- **`~/.hermes/skills/coding-hermes-project-manager/SKILL.md`** — the "Board path anchor" block inside
  Step 1 (where the cycle first names the board) plus the anchor clause in the G4 row.
- **`~/.hermes/skills/devops/coding-hermes-pm-standin/SKILL.md`** — the same recipe at cycle step 2,
  where `<workdir>/.coding-hermes/board/tasks.jsonl` was named without an anchor.

## PASS checks

```bash
# 1. The pm prompt still has the original text as a prefix, and carries the new paragraph
sqlite3 ~/.hermes/coding-hermes/scheduler.db "SELECT default_prompt FROM namespaces WHERE id='pm';" > /tmp/pm-prompt-after.txt
head -c "$(wc -c < /tmp/pm-prompt-before.txt)" /tmp/pm-prompt-after.txt > /tmp/pm-prompt-prefix.txt
cmp /tmp/pm-prompt-before.txt /tmp/pm-prompt-prefix.txt && echo PREFIX_IDENTICAL
grep -c 'TARGET RESOLUTION' /tmp/pm-prompt-after.txt
# -> PREFIX_IDENTICAL / 1        (2696 -> 3370 chars, 2710 -> 3384 bytes)

# 2. No stand-in dir in the h3 family carries a board file of its own.
#    Scope it: the address-based sweep is the right SHAPE but is not empty fleet-wide (12 non-h3
#    sync lanes carry a findings tasks.md — see the fleet-wide remainder), so the h3 family is
#    selected by path, exactly as the row's own TARGET is.
find ~/.hermes/stand-in ~/.hermes/sync-workdirs -maxdepth 4 \( -name tasks.md -o -name tasks.jsonl \) \
  | grep -E '/(h3|h3-[a-z0-9-]*)(/|$)'
# -> no output (grep exits 1 on no match — that is the pass)
find ~/.hermes/stand-in ~/.hermes/sync-workdirs -maxdepth 3 \( -name tasks.md -o -name tasks.jsonl \) | wc -l
# -> 12, all outside the h3 family (fleet-wide remainder, unfixed by design)

# 3. Every link resolves to the owner board (run per stand-in dir)
for d in /home/kara/.hermes/stand-in/pm-lane/h3 \
         /home/kara/.hermes/stand-in/pm-lane/h3-sdk-go-foreman \
         /home/kara/.hermes/stand-in/pm-lane/h3-sdk-python-foreman \
         /home/kara/.hermes/stand-in/pm-lane/h3-sdk-typescript-foreman \
         /home/kara/.hermes/stand-in/pm-lane/h3-shim-foreman \
         /home/kara/.hermes/stand-in/pm/h3 \
         /home/kara/.hermes/stand-in/dogfood/h3 \
         /home/kara/.hermes/sync-workdirs/h3-umbrella-sync ; do
  printf '%s -> %s\n' "$d" "$(readlink -f "$d/.coding-hermes/board")"
done
# -> each line ends in the owner repo's /.coding-hermes/board

# 4. The link reads the owner's rows (not an empty dir)
wc -l < /home/kara/.hermes/stand-in/pm-lane/h3/.coding-hermes/board/tasks.jsonl
# -> 205
```

## Verification

```bash
cd /home/kara/get-h3/h3 && make verify
# -> make verify: ALL PASS — umbrella repo is self-consistent (exit 0)

cd /home/kara/get-h3/h3 && git log -1 --stat
# -> exactly 1 file changed: docs/board/standin-workdir-board-resolution.md
```

## Fleet-wide remainder

The prompt/skill fix is fleet-wide; the links cover the h3 family. Measured 2026-09-19:

- **11 non-h3 PM-lane stand-ins still hold an EMPTY `.coding-hermes/`** — `9router`, `bunker`,
  `chimera-v2`, `crier`, `gitreins-poc`, `heading`, `hermes-canopy`, `hermes-dagger`, `off-by-one`,
  `terminal-jail`, `warpfs` under `~/.hermes/stand-in/pm-lane/`. Same class, same one-line fix, left
  untouched by this row (scope: h3 family only).
- **2 stand-ins hold REAL local boards with unread rows** — `~/.hermes/stand-in/pm/off-by-one/` and
  `~/.hermes/stand-in/pm/hermes-canopy/` (3 rows total, one P1; see the measured before-state). These
  need a row-by-row decision (move the still-live rows to the owner board, then link), not a blind
  `ln -s`: linking would strand the local file behind the link.
- **8 h3-family stand-ins are still unlinked** — the `-qa` and `-dogfood` variants of the four SDK
  foremen (`~/.hermes/stand-in/pm/h3-sdk-go-foreman`, `…/pm/h3-sdk-python-foreman`,
  `…/pm/h3-sdk-typescript-foreman`, `…/pm/h3-shim-foreman`, and the four matching dirs under
  `~/.hermes/stand-in/dogfood/`). All are currently disabled projects; link them before enabling.
- **12 sync lanes carry a `tasks.md` inside `.coding-hermes/`** — a different shape (a sync-lane
  findings ledger, and at least one documents "no local board; owner rows live on the hermes-dagger
  board"), several already carrying the `board` link. Not the same defect; listed so the next sweep
  does not re-derive it:
  `~/.hermes/sync-workdirs/{hermes-agent,heading,hivemind,muster,duckbrain,reports,mafia-benchmark,mythos,kobayashi-maru,axiom,helios,terminal-jail}-sync/.coding-hermes/tasks.md`.
- `~/.hermes/stand-in/pm/{off-by-one,hermes-canopy}` also carry a real (non-link) `board/` directory —
  see the second bullet above.

## Provenance

DF-H3PM-04, h3 umbrella foreman tick #406. Prompt append applied to
`~/.hermes/coding-hermes/scheduler.db` (`namespaces.id='pm'`); skill anchors added to
`~/.hermes/skills/coding-hermes-project-manager/SKILL.md` and
`~/.hermes/skills/devops/coding-hermes-pm-standin/SKILL.md`; eight `board` links created in the h3
family stand-in dirs; this document committed in `get-h3/h3`. Board row:
`[dogfood:P2] PM-lane stand-in workdirs contain an EMPTY .coding-hermes/ and the
target->real-board resolution is undocumented`.

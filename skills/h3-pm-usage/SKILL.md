---
name: h3-pm-usage
description: >-
  How to USE the h3-pm lane — the scheduler PM lane that audits the get-h3
  umbrella board. Where its rows, ledger and cycle logs live, the exact
  commands to re-verify its claims, and the four traps found by dogfooding it
  (2026-09-18). Load this before trusting, re-running, or hand-filing
  H3-PM-* work.
version: 1.0.0
category: software-development
---

# h3-pm Usage — Consuming the PM Lane's Product

`h3-pm` is a **scheduler lane**, not a repo: namespace `pm`, workdir
`/home/kara/.hermes/stand-in/pm-lane/h3`, cooldown 86400s. Each tick it runs the
`coding-hermes-project-manager` skill for the **h3** project and files
`H3-PM-*` rows on the h3 umbrella board. This skill is the user manual for that
output — how to read it, how to re-verify it, and what to watch out for.

## When to Use

- You are asked "did the PM lane really find that / is that fixed?"
- You are about to file, close, or dedupe a row on the h3 umbrella board.
- You are debugging why a lane's ledger and a board disagree.
- You are writing pass criteria for any row that a verifier will re-run later.

## Where the truth lives

| Artifact | Path | What it is |
|---|---|---|
| Board (canonical) | `get-h3/h3/.coding-hermes/board/tasks.jsonl` | the work; `H3-PM-*`, `H3-GAP-*`, `GAP-*`, `DF-H3-*`, `QA-H3-*` rows |
| Events | `get-h3/h3/.coding-hermes/board/events.jsonl` | add/complete/audit trail, one JSON object per line |
| Ledger (PM's memory) | `~/.hermes/stand-in/ledger.json` | every item the PM ever filed, with `status`, `last_checked_at`, `verification_evidence`, `gates` |
| Cycle log | DuckBrain ns `coding-hermes`, keys `/stand-in/YYYY-MM-DD/cycle` and `/stand-in/YYYY-MM-DD/h3` | the PM's decision trail (present for 2026-09-18: 06:34Z cycle, 06:33Z h3) |
| Lane prompt | `~/.hermes/fleet.toml` → `[[namespaces]] id="pm"` | what a tick is told to do |
| Cycle procedure | skill `coding-hermes-project-manager` | ledger first → hunters → G1–G7 gate → write → verify prior items → escalate → log |
| Legacy executor | `~/.hermes/scripts/pm-standin-tick.sh` | **RETIRED** — do not run; it still resolves targets for some lanes, which is why old `/pm/<proj>/last-run` keys exist |

**The lane's workdir is not the project.** `/home/kara/.hermes/stand-in/pm-lane/h3/.coding-hermes/`
is **empty** — there is no board there and there must never be one. Write to the
h3 board in `get-h3/h3`, which is what the h3 foreman actually reads.

## How to re-verify a row (the 60-second version)

Every good `H3-PM-*` row ends with a `PASS:` criterion in `review_notes`. Run it
verbatim — that is the whole point of the field.

```bash
# 1. see the claim and its criterion
python3 -c "import json;[print(r['id'],'|',r.get('review_notes')) for r in map(json.loads,open('/home/kara/get-h3/h3/.coding-hermes/board/tasks.jsonl')) if r.get('id')=='H3-PM-005']"

# 2. run the criterion — and scope it to the SURFACE, not the whole tree
sed -n '535,552p' /home/kara/get-h3/h3/docs/migration.html | grep -c '11/11\|Score: 44/44\|43 protocol behaviors'   # 0 = pass

# 3. resolve the commit in the repo the row names (commit_repo tells you which)
git -C /home/kara/get-h3/h3 log --oneline -1 59ecfeb

# 4. the row's cross-repo commit hash, if commit_repo is set
git -C /home/kara/get-h3/shim log --oneline -1 5f665e5
```

### Scope every grep criterion (learned the hard way)

A repo-wide grep criterion on a board **cannot pass**, because the row stating
it, the board's `events.jsonl`, and `.gitreins/history/` all quote the searched
string. `H3-PM-006` claims `grep -rn 'EndResult' /home/kara/get-h3/h3 == 0 hits`;
the live count is 11, **all** of them in the board and judge artifacts — the
actual fix holds. Write criteria against the surface under test:

```bash
git -C /home/kara/get-h3/h3 grep -n EndResult -- '*.md' '*.go' '*.html'   # surface only
grep -rn --exclude-dir=.git --exclude-dir=.gitreins --exclude-dir=.coding-hermes 'PATTERN' .
```

## How to check the two cross-cutting claims

```bash
# id-reuse (the PM skill's G7 method: fingerprint CONTENT, never the id)
python3 - <<'PY'
import json,re,collections
rows=[json.loads(l) for l in open('/home/kara/get-h3/h3/.coding-hermes/board/tasks.jsonl') if l.strip()]
def fp(r):
    t=((r.get('title') or '')+' '+(r.get('detail') or r.get('review_notes') or '')).lower()
    t=re.sub(r'[0-9a-f]{7,40}','',t); t=re.sub(r'\d+','#',t)
    return re.sub(r'\s+',' ',re.sub(r'[^a-z# ]',' ',t)).strip()[:120]
byid=collections.defaultdict(set)
for r in rows: byid[r['id']].add(fp(r))
print('ids holding >1 distinct finding:', {k:len(v) for k,v in byid.items() if len(v)>1})
PY

# ledger vs board (the PM's memory vs reality)
python3 - <<'PY'
import json,os,sqlite3
wd={n:w for n,w in sqlite3.connect(f"file:{os.path.expanduser('~/.hermes/coding-hermes/scheduler.db')}?mode=ro",uri=True).execute("SELECT name,workdir FROM projects")}
items=[i for i in json.load(open(os.path.expanduser('~/.hermes/stand-in/ledger.json'))).get('items',[])
       if i.get('status') in ('added','picked_up')]
stale=0
for i in items:
    w=wd.get(i.get('project')); p=w and os.path.join(w,'.coding-hermes/board/tasks.jsonl')
    if not (p and os.path.isfile(p)): continue
    for l in open(p):
        try: r=json.loads(l)
        except Exception: continue
        if r.get('id')==i.get('id') and r.get('status')=='complete': stale+=1; break
print(f'{stale}/{len(items)} open ledger items are already complete on their boards')
PY
```

## Pitfalls

1. **Do not write to the stand-in workdir.** `stand-in/pm-lane/<proj>/.coding-hermes/`
   is empty by design; a row written there is read by nobody. Resolve the real
   board from the scheduler: `sqlite3 ~/.hermes/coding-hermes/scheduler.db
   "SELECT workdir FROM projects WHERE name='<target>'"` — the retired
   `pm-standin-tick.sh` did exactly this and hard-filtered rows to the target.
2. **`superseded_by` must point at the CANONICAL row, never at the row itself.**
   Four rows on this board say `superseded_by == id` (self-reference), which
   leaves the reader unable to tell which row won. When marking a duplicate,
   name the surviving id.
3. **A duplicate row is not a fixed id.** Rows marked `status='duplicate'` keep
   the id they were filed under. If a *pending* finding shares an id with
   duplicate rows of a different finding, the id is still reused — re-id the
   pending finding and record it in `foreman_note`.
4. **The ledger lags the board by up to a cycle.** 43 of 104 open items were
   already complete when this skill was written. Read board status before
   treating a ledger item as due, and never report the raw open count as
   outstanding work.
5. **Quote counts with a timestamp.** Closure notes age: `H3-PM-003` says "six
   of 188 rows carry `commit_repo`", the live count is 7. Say "at commit X" or
   let the verifier recompute.
6. **Don't expect `/pm/h3/last-run` in DuckBrain.** That key shape belongs to
   the retired dagger executor. The skill-driven cycle logs to namespace
   `coding-hermes` as `/stand-in/<date>/h3` and `/stand-in/<date>/cycle`.

## Verification checklist (run before reporting on the lane)

- [ ] every `H3-PM-*` row's `commit_hash` resolves (`git -C <repo> log -1 <sha>`)
- [ ] every `PASS:` criterion in `review_notes` re-runs to the stated result
- [ ] criteria are scoped to a surface, not the whole tree
- [ ] duplicate rows point at a real canonical id
- [ ] ledger/board disagreement counted and named, not averaged away
- [ ] cycle log key exists for the date you are reporting on

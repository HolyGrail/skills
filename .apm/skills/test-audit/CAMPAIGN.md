# Test-pruning campaign

Campaign mode prunes one subsystem's whole test surface in one PR: a package,
feature area, or one core module. The value bar, retention bar,
candidate evidence, validation, and authorization rule in [SKILL.md](SKILL.md)
apply to every lane. This file adds the order of work and the lessons of a
full campaign. Each step ends on its completion criterion; do not start the
next step early.

## 1. Baseline

Record the subsystem's test and test-support line counts and every in-scope
test file's pass/fail state at a pinned base-branch SHA. Run the baseline once,
one runner at a time, reporting only per-file results (in the main session or
a single subagent). Keep baseline failures in their own list; they
are often real product bugs, not stale tests.

Done when every in-scope test file has a recorded baseline result.

## 2. Lanes and inventory

Split the surface into **lanes** along production owner boundaries, not file
prefixes. Include the subsystem's cases at shared core boundaries and its e2e,
integration, and live harness tests.

Done when every test file and scenario the subsystem owns belongs to exactly
one lane.

## 3. Read-only ledger per lane

Give each lane to its own read-only subagent when its reading is large; batch
small lanes or read them directly. Lane agents do not run tests or builds. The
reader reads every assigned test in full, including parameter tables. It also
reads the production owners and their entry points, callers, history, and how
CI selects or gates the tests. Each test declaration goes into a written
**ledger** with one mark. A parameterized or table-driven test is one
declaration unless its rows need different marks; then mark each row.

- `R`: retain, naming the contract and the bug it catches; a retained test that
  only moves to a better-named file stays `R` with the move noted;
- `F`: retain the contract but repair the assertion, such as a vacuous negative
  that passes when only one of several items is missing;
- `C`: consolidate, naming the owner that absorbs the assertion first: a sibling
  table case, a stronger boundary suite, or the shared owner in another package;
- `D`: delete, naming the proof that remains, or why no contract exists.

Judge a test by its assertions, not its name.

Done when every declaration in the lane has a mark and an evidence line.

## 4. Layer plan per lane

Treat the per-test ledger as input, not as the edit list. A second read-only
pass, starting from the ledger, looks for the redundant **layer**: for
example, several suites that replay one shared helper through a mocked
collaborator, around a stronger suite that drives the real boundary with a
fake network. Name the **keeper** suite for each contract. Prefer the real
transport boundary with a fake network over a mocked collaborator. Correct any
ledger errors this pass finds.

Done when each lane plan names its retired files, its keeper per contract, the
assertions to carry into keepers, and the test-only production seams unlocked.

## 5. Cutover

Edit lane by lane. Serialize changes to shared harnesses and support files
through one editor. With each lane, remove the test-only production seams it
unlocks: injection parameters, getters, reset exports, and indirection layers.
If the project keeps a test registry, CI test selection, or size or line-cap
baselines, update them for moved or deleted suites. Add durable test-ownership
rules, drawn from mistakes this campaign actually found, to the instruction
file the project already uses (CLAUDE.md or AGENTS.md); do not create one.

Done when every lane plan is applied and each lane's keepers pass.

## 6. Preservation review

Before claiming completion, have fresh subagents that did not make the edits
compare deleted coverage against the keepers, one reviewer per boundary group.
They look for contracts that lost their only proof. They also look for new
assertions that cannot fail, such as a rejection row the production code never
reaches. Reviewers report gaps; they do not edit.

For each restored contract, the single editor makes one deliberate
**mutation** of the production owner, one at a time and never while a test run
is in progress, and confirms the keeper goes red. Then restore the source byte
for byte by reversing the mutation edit only; never checkout, reset, or stash
the file.

Done when every reported gap is restored or rejected with source evidence, and
every restored contract has a caught mutation.

## 7. Product defects

A baseline failure that survives into a keeper is a bug report. Fix it at its
owner as a separate commit, and prove it through the real boundary
(integration, e2e, or simulator), with a **control** run that reverts the fix
and shows the old behavior. Record unrelated product discrepancies you find as
follow-ups instead of fixing them in the campaign.

Done when each repaired defect has a failing control and a passing candidate
on the same harness.

## 8. Reconcile and hand off

Campaigns outlive many base-branch commits. Merge the base branch rather than
rebasing a long, many-commit campaign, unless project policy says otherwise.
When the base branch modified a file the campaign deleted, keep the deletion.
Port the new contract into the keeper instead, and confirm every new regression
the base branch added still has a home. Rerun the whole subsystem suite and
repeat e2e or live proof on the merged head.

Hand off with the [SKILL.md](SKILL.md) report, plus:

- baseline and final test/support line counts, with production counted separately;
- lanes, retired layers, and keepers;
- preservation gaps found and their mutations;
- product defects with control and candidate proof.

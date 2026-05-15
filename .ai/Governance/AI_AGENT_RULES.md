# AI_AGENT_RULES.md

Task protocol for any AI agent working in this repository.

---

## Start-Of-Task Protocol

Before making changes:

1. Review the required start files listed in `AIR_RULES.md`
2. Read `.ai/REPODOCK/TASKS/CURRENT_TASK.md`
3. Confirm the active objective, known constraints, and open risks
4. Continue the existing task record if it matches the request, or replace it with a new task record if the request is materially different

`CURRENT_TASK.md` is the single active task ledger. Review it first. Rewrite it at task start when the task changes.

---

## End-Of-Task Protocol

Before ending the task:

1. Fill out `.ai/REPODOCK/TASKS/CURRENT_TASK.md`
2. Mirror the stable handoff summary into `.ai/REPODOCK/HANDOFFS/LATEST_HANDOFF.md`
3. Add a dated log entry for significant governance, architecture, or runtime findings
4. Update `NEXT_SESSION.md` only with the highest-signal next actions

Do not leave task status implicit.

---

## Task Record Requirements

Each `CURRENT_TASK.md` entry must include:

- task title
- request date
- status
- objective
- start-of-task review summary
- constraints
- files expected to change
- files actually changed
- verification performed
- architecture boundaries touched
- behavior changes
- risks / follow-ups
- next task recommendation

---

## Change Discipline

- Keep edits scoped to the requested task
- Do not perform drive-by cleanup outside the task boundary
- Do not overwrite user changes you did not make
- Prefer verifiable outcomes and explicit notes over assumptions
- Keep repo process docs synchronized with reality

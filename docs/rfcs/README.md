# RFCs (Request for Comments)

This directory holds design proposals for substantial eco-commander changes. RFCs are the upstream stage before implementation; accepted RFCs produce Architecture Decision Records (ADRs) and implementation issues.

See also: [ADRs](../adr/) | [Documentation Index](../INDEX.md)

---

## What Is an RFC?

An RFC is a written design proposal that seeks community input before work begins. It describes the problem, the proposed solution, alternatives considered, and known drawbacks. Discussion happens on the PR that introduces the RFC; the author iterates until consensus is reached.

RFCs are heavier than ADRs. Only write one when a feature or change is substantial enough that the design itself needs to be reviewed before a line of code is written.

---

## RFC vs ADR — When to Use Which

| Situation | Write |
|---|---|
| You are proposing a multi-week feature that affects the public API, recipe contract, or snapshot format | **RFC** |
| You need upfront design consensus from other contributors before starting | **RFC** |
| You have already implemented a change and are recording the decision | **ADR** |
| The change is small enough that one author can decide and implement it in a single session | **ADR** |
| An RFC was accepted and you are formalising the ratified decision | **ADR** (link back to the RFC) |

For ADR conventions see [docs/adr/0001-record-architecture-decisions.md](../adr/0001-record-architecture-decisions.md).

---

## RFC Lifecycle

```text
Draft → Under Review → Accepted
                    → Rejected
                    → Superseded (by a later RFC)
```

| Stage | Meaning |
|---|---|
| **Draft** | Author is writing; not ready for review |
| **Under Review** | PR is open; discussion is active |
| **Accepted** | PR merged; implementation issues opened |
| **Rejected** | PR closed without merge; rationale recorded in the RFC |
| **Superseded** | A later RFC replaces this one; both files kept for history |

Transition rules:
- Move from **Draft → Under Review** by opening a PR.
- Move from **Under Review → Accepted/Rejected** by reviewer consensus on the PR.
- Never delete a rejected or superseded RFC — they are part of the project's decision history.

---

## Active RFCs

_None yet._ The first RFC will be filed when a substantial feature proposal requires upfront design discussion.

---

## RFC Template

Copy the block below into `NNNN-short-title.md` (use the next available four-digit number) and fill in every section before opening a PR.

```markdown
# RFC NNNN: Title

- **Status:** Draft
- **Author:** @github-username
- **Created:** YYYY-MM-DD
- **Related ADR:** (fill in after acceptance — see [`../adr/`](../adr/README.md))

## Summary

One paragraph describing what this RFC proposes and why.

## Motivation

What problem does this solve? Who is affected and how often?
Quantify the pain if possible (e.g., "operators must manually check three TUIs per day").

## Detailed Design

Technical specification of the proposed change.
Include data model changes, new CLI flags, LaunchAgent additions, file layout changes, etc.
Link to or embed a Mermaid diagram if the data flow is non-trivial.

## Alternatives Considered

What other approaches were evaluated and why they were rejected.
Incomplete alternatives analysis is the most common reason an RFC is sent back for revision.

## Drawbacks

Known downsides, risks, or increased maintenance burden introduced by this proposal.

## Unresolved Questions

Open issues to be resolved during implementation or follow-up RFCs.
List anything the author is deliberately deferring.
```

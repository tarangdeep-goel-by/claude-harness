---
title: "{{Project}} — Knowledge Base"
categories:
  - "[[Research]]"
subjects:
  - "[[Product Strategy]]"
status: active
created: {{date}}
updated: {{date}}
---

# {{Project}} — Knowledge Base

The durable answer to **what {{project}} IS and HOW it works**. Fundamentals only.

> **What belongs here vs not** (the vault doc-type contract):
> - **KNOWLEDGE_BASE.md (this doc)** = durable fundamentals: what it is, how it works, mechanics,
>   rules, constraints, key concepts, the decisions-in-brief. **No metrics, no status.**
> - **`research/`** = findings & analysis (the numbers, with dates).
> - **`methodology`** (where it exists) = the metric → source → logic dictionary.
> - **`decisions/`** = ADRs (the rationale).
> - **`PROJECT_LOG.md` / `PROJECT_ARC.md`** = status & history.
> - **Instrumentation/events** → the relevant skill, not here.
> This doc links OUT to those; it does not restate their content.

## 1. What it is
{{one paragraph: purpose, the core insight, where it sits}}

## 2. How it works
{{architecture / lifecycle / the end-to-end flow}}

## 3. Rules & key concepts
{{the durable rules, entities, definitions; tables where useful}}

## 4. Constraints & gotchas
{{regulatory/technical/operational constraints that shape the design}}

## 5. Decisions (durable essence)
{{one line per ADR + link}}

## 6. Where to go deeper (links map)
| Topic | Doc |
|---|---|
| Findings / analysis | {{research docs}} |
| Metric dictionary | {{methodology}} |
| Instrumentation | {{skill}} |
| Status / history | [[PROJECT_LOG]], [[PROJECT_ARC]] |

## 7. Open reconciliations / known discrepancies
{{anything ambiguous or to-verify}}

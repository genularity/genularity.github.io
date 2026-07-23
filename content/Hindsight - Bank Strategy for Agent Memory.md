---
title: "Hindsight - One Bank or Many? Designing Agent Memory Boundaries"
url: "https://hindsight.vectorize.io/blog/2026/07/16/bank-strategy-agent-memory"
date_saved: 2026-07-17
date_published: 2026-07-16
tags:
  - hindsight
  - memory
  - ai-agents
  - architecture
  - context-engineering
summary: >
  Vectorize's field guide to structuring agent memory in Hindsight: a "bank" is
  a recall boundary, not a performance knob. The real design question isn't
  "how should I organize memory" but "if A retains a memory, should B be able
  to recall it?" — every bank-vs-tag decision reduces to that one question.
key_concepts:
  - Memory bank as recall boundary
  - Tags as soft partitions vs banks as hard isolation
  - Per-user / per-project / per-agent / shared bank strategies
  - The "per-project-tagged" default recommendation
  - Anti-patterns — bank-per-conversation, over-fragmentation, unstable bank ids
technologies:
  - Hindsight
  - Vector databases
  - Multi-agent systems
related:
  - "[[Hindsight - Agentic Memory for AI Systems]]"
  - "[[Overriding Agent Memory Tools Cleanly - Interception vs Reimplementation]]"
status: draft
publish: true
---

> [!tldr] TL;DR
> A memory "bank" in Hindsight is a complete, isolated recall boundary — nothing queries across banks. So the entire design question collapses into one: *if A retains a memory, should B be able to recall it?* Yes → same bank. No → separate banks. Everything else (tags, filters, timestamps) is a *soft* partition inside a bank you've already decided should be one trust domain. Get the boundary wrong and you either leak data across users, or starve an agent of context it should have had.

## The one idea

Every Hindsight integration asks you to set a `bank_id`. Almost none tell you how to decide what a bank *should be* — and that decision quietly shapes everything an agent can later recall. Score it too wide, and one user's memory bleeds into another's. Score it too narrow, and the agent can't reach something it needs because that thing lives in a bank it can't see.

The framing that resolves this: a bank is a **recall boundary**. `recall`, `retain`, and `reflect` all operate inside exactly one bank — there is no cross-bank query. So instead of asking "how should I organize memory," ask one question per boundary:

> If A retains a memory, should B be able to recall it?

Yes → same bank. No → separate banks. That's the whole design tool.

## Common strategies

| Strategy | One bank per… | Good for | Where it bites |
|---|---|---|---|
| Global | everything | a solo tool, one user | the moment a second user shows up, memories mix |
| Per-user | end user | SaaS products, personal assistants | one user with many projects gets it all blurred together |
| Per-project | codebase/workspace | coding agents | cross-project context doesn't follow the user |
| Per-agent | agent role | multi-agent systems | agents that *should* pool context can't |
| Shared/team | a group, deliberately | one memory across many surfaces | needs explicit opt-in, not the default |

None of these is correct in the abstract — the right one falls out of who the actual A and B are for a given system.

## Tags are not banks

A bank is created the first time something writes to its `bank_id` — there's no provisioning step, which is convenient and also the most common failure mode: a bank-per-conversation strategy means every new conversation resolves to a fresh, empty bank, and the agent never remembers anything across sessions. The past memory isn't deleted, it's just unreachable.

Inside a single trust domain, **tags** are the right tool for organizing without fragmenting: label memories at write time, filter (or don't) at read time. The default match mode (`any`) still surfaces untagged memories — which is the tell that tags are a convenience, not a security control. If a memory must *never* surface in the wrong context, that's a bank boundary, not a tag you're hoping nobody forgets to filter on.

The recommended default when unsure: **one bank per trust domain, tags for the projects/topics inside it** — described in the source piece as "per-project-tagged."

## Anti-patterns worth remembering

- **Bank-per-conversation** — feels like isolation, is actually amnesia. Every session starts blank.
- **One global bank in a multi-tenant app** — works in the demo, becomes an incident with the second customer.
- **Over-fragmentation** — a bank per (user × project × agent × session) starves recall; each bank holds too little to be useful.
- **Unstable bank ids** — deriving an id from something that changes when it shouldn't (a machine-specific path, a session token, an editable display name) silently splits one memory into many, with no error.

## Why this resonates

As an AI Architect, this is the class of decision that looks like a config field and is actually a product-architecture and security decision hiding in plain sight. Memory-backed agents fail in one of two boring, expensive ways: either context leaks across a boundary that should have held, or an agent quietly can't see something it should already know because nobody thought about who shares a "recall boundary" with whom. The useful move in this piece isn't the specific strategy table — it's collapsing every version of that argument into one testable question you can ask *before* wiring anything up, rather than discovering the answer in production. That's the kind of framing that's easy to nod along to and genuinely easy to skip under deadline pressure — which is exactly when it bites.

## Links

- [Original post — Vectorize / Hindsight blog](https://hindsight.vectorize.io/blog/2026/07/16/bank-strategy-agent-memory)
- [[Hindsight - Agentic Memory for AI Systems]] — what Hindsight is and how retain/recall/reflect work mechanically

## Related

- [[Hindsight - Agentic Memory for AI Systems]] — the memory layer this bank-strategy guidance applies to
- [[Overriding Agent Memory Tools Cleanly - Interception vs Reimplementation]] — the companion *how*: routing memory to a chosen store via a clean tool override (this note is the *what each store represents*)

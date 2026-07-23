---
title: Overriding Agent Memory Tools Cleanly — Interception vs Reimplementation
date_saved: 2026-07-17
tags:
  - ai-agents
  - memory
  - architecture
  - extensions
  - context-engineering
  - agentic-systems
summary: |
  A design note on the cleanest way to change where an AI agent's memory (retain / recall / reflect) is stored without forking the agent framework or rewriting its memory API client. The trick: agent frameworks expose memory as ordinary tools, and a same-named tool registered by an extension wins the collision — so you intercept exactly at the call site the model already uses, and reuse the framework's own typed API client instead of hand-rolling REST. Also: where the "let the LLM decide which store this belongs in" decision actually belongs.
key_concepts:
  - Memory as a tool, not a hidden subsystem
  - Same-named tool override wins the registry collision
  - Reuse the shipped API client — don't reimplement the transport
  - LLM-driven routing lives in the tool schema, not in a content heuristic
  - Recall fan-out and merge across stores
technologies:
  - Agentic coding harnesses
  - Agent memory APIs
  - Vector-backed retrieval
related:
  - "[[Hindsight - Bank Strategy for Agent Memory]]"
  - "[[Hindsight - Agentic Memory for AI Systems]]"
status: draft
publish: true
---

> [!tldr] TL;DR
> Modern agent frameworks expose long-term memory (`retain` / `recall` / `reflect`) as **ordinary tools**, not as a sealed subsystem. That makes routing memory to a *different* store a solved problem: register a same-named tool from an extension, let it win the registry collision, and you now sit at *exactly* the point the model already calls — no fork, no core patch. The two mistakes worth avoiding are (1) reimplementing the memory service's REST client when the framework already ships a typed one you can import, and (2) hiding the store-selection decision inside a content heuristic instead of surfacing it as an explicit field the model fills in.

## The problem

I've been working through a recurring architecture question for memory-backed AI agents: *how do you change where an agent stores and retrieves its memories — without forking the harness, and without rewriting the memory backend's API layer by hand?*

The naive answers are both bad. Forking the framework means you own a patch against fast-moving, non-SemVer-guaranteed internals forever. Hand-rolling a REST client against the memory service means you re-implement (and then re-maintain) URL building, auth headers, timeouts, error unwrapping, and response-shape parsing that the framework already got right. Neither is where the value is.

## The insight: memory is just tools

In current agentic coding harnesses, `retain`, `recall`, and `reflect` are not special — they're regular tool instances with a plain parameter schema (roughly `{ items: [{ content, context? }] }` for retain). Every tool call, built-in or not, flows through the same wrapping layer that the extension system uses. So a memory write is interceptable at the same seam as any other tool call.

Two properties make this clean rather than hacky:

1. **Same-named override wins.** When an extension registers a tool with the same name as a built-in, the registered tool is inserted *after* the built-ins into the same registry map — so on a name collision, the extension's version wins. You are not shadowing or racing the built-in; you are replacing it at the exact call site the model already emits calls to. (If you also switch the native memory backend off, there's no collision at all — the built-in tools are simply never registered, and the names are free.)
2. **You inherit the model's mental model.** Because you keep the tool *name* (`retain`), every existing system-prompt instruction, every learned habit the model has about when to call it, keeps working. You changed the destination, not the interface.

This is the difference between *interception* and *reimplementation*. You want interception.

## Don't rewrite the transport — import it

The second half of "cleanly" is not rebuilding the memory service's REST layer. Well-designed frameworks export their memory API client as a public sub-path. Rather than `fetch()`-ing raw endpoints and re-deriving auth and response parsing, import the shipped, typed client and call its methods (`retain`, `retainBatch`, `recall`, `reflect`, plus bank/document/mental-model CRUD). It already handles:

- base-URL and path construction
- `Authorization: Bearer …` headers
- timeouts and error unwrapping
- the exact response shapes the rest of the framework expects

If the framework's config loader is awkward to reach from inside an extension, you can construct the client directly from environment variables and skip the settings plumbing. The point stands: **the transport is a dependency, not a thing you write.**

## Where the "which store?" decision belongs

The interesting design choice is routing: some memories are personal to one user/context, some belong in a shared/team store. Where does the "decide which store this goes to" logic live?

There are two honest options, and one tempting-but-wrong one.

- **Wrong (tempting):** infer the destination from a *content heuristic* — scan the text of each item and guess "this looks team-worthy." It's unauditable, silently misroutes, and couples storage semantics to fragile string matching.
- **Right, option A — explicit field:** expand the tool schema with an additive `destination?: "personal" | "shared"` field (default one of them). The model *declares* intent. The routing decision is now visible in the tool call, auditable, and trivially correct.
- **Right, option B — two named tools:** register `retain` (personal) and `retain_shared` (team). The model picks the tool; the tool name *is* the routing decision. Same auditability, and it reads well in a transcript.

Both A and B put the decision where it belongs: **the LLM makes the call, but it's an explicit, inspectable declaration**, not a downstream guess. For reads, you usually don't want the model choosing at all — a single `recall` that **fans out to every store the caller is entitled to and merges the results** keeps the read side simple and complete. The model only decides on writes, where intent actually exists.

## Why this generalises

This is really a pattern about *any* subsystem an agent framework exposes as tools, not just memory:

1. Keep the tool **name** — you inherit the model's trained behaviour and every prompt that mentions it.
2. Win the registry collision (or free the name by disabling the built-in) — you sit at the true call site.
3. Reuse the shipped client — the transport is a dependency.
4. Make routing an **explicit field or an explicitly-named tool** — never a content heuristic.
5. Fan out and merge on read; decide only on write.

The reason I like this framing is that it turns "how do I customise my agent's memory" from a forking exercise into a small, well-bounded extension — the kind of change that survives upstream churn because it hangs off public extension points rather than reaching into internals. Deciding *what a memory store should even represent* (a recall boundary per user, per project, per team?) is a separate and equally important design question — covered in [[Hindsight - Bank Strategy for Agent Memory]].

## Links

- [[Hindsight - Bank Strategy for Agent Memory]] — the companion decision: not *how* to route, but *what each store should represent*
- [[Hindsight - Agentic Memory for AI Systems]] — what a persistent agent-memory layer provides (retain/recall/reflect, mental models)
- AI Goldfish Memory - The Context Window Problem — why persistent memory matters at all
- Context Engineering & Beyond RAG — the broader discipline this sits inside

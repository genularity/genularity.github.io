---
title: genularity
publish: true
quartz-homepage: true
themes-hash: "6d4f04b12c92"
---

# Kent's Notes

<span class="dict-entry"><strong>genularity</strong> <span class="ipa">/ˌdʒɛn.jʊˈlær.ɪ.ti/</span> · <em>noun</em>: the state in which a system's degrees of freedom approach infinity as its generality approaches everything.</span>

I'm an AI Architect based in Sweden. These notes are my thinking-out-loud: patterns I've found useful, ideas worth sharing, things I want to remember.

<!-- QUARTZ:THEMES-START -->
Right now that means the plumbing behind AI agents that don't forget: [[Hindsight - Agentic Memory for AI Systems|persistent memory as a service]] and [[Hindsight - Bank Strategy for Agent Memory|how to structure it]], the [[OMP Configuration - Generic Reference|harness config]] that wires model routing, subagents, and memory backends together into something that actually runs in production, [[Overriding Agent Memory Tools Cleanly - Interception vs Reimplementation|how to cleanly override an agent's memory tools]], and a [[Agentic Coding Harnesses & Terminal Runtimes|field guide to the coding agents themselves]].
<!-- QUARTZ:THEMES-END -->

---

## Start Here

<!-- QUARTZ:NOTE-LIST-START -->
- [[Agentic Coding Harnesses & Terminal Runtimes]] — A field guide to agentic coding tools, split into two categories that get conflated constantly: harnesses that actually write code (terminal-native, IDE-integrated, cloud/multi-agent) and runtime containers that orchestrate multiple harnesses in parallel
- [[Hindsight - Agentic Memory for AI Systems]] — Hindsight is a standalone memory API for AI agents — a persistent, searchable memory layer that any agent or LLM application can plug into
- Hindsight - One Bank or Many? Designing Agent Memory Boundaries — Vectorize's field guide to structuring agent memory in Hindsight: a "bank" is a recall boundary, not a performance knob
- [[OMP Configuration - Generic Reference]] — A fully-annotated reference config for Oh My Pi (OMP): model role routing, memory backend wiring, subagent isolation, and the rationale behind every non-default setting
- Overriding Agent Memory Tools Cleanly — Interception vs Reimplementation — |
<!-- QUARTZ:NOTE-LIST-END -->

---

## Browse

Use the **explorer** on the left or hit `Ctrl+K` to search. The **graph view** on the right shows how notes connect.

---

*Updated automatically from my Obsidian vault.*

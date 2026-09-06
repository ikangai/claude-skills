---
name: omakase
description: Chef's-choice build workflow for fuzzy software requests. Use this whenever the user hands over a vague or half-formed idea for a tool, app, script, feature, plugin, or rewrite ("I want something that…", "build me a little X", "can you make Y faster/simpler", "replace tool Z, I only use 5% of it", "port this to Rust/Go/C++", "just make it good") and expects you to make the decisions instead of asking a dozen clarifying questions. Also trigger on /omakase, "chef's choice", "you decide", "surprise me", "make it simpler", "make it faster", "second opinion on this code", or when the user says they don't know exactly what they want yet. Do NOT use for tasks that already come with a precise spec, ticket, or acceptance criteria — those don't need a chef.
---

# Omakase — chef's choice for building software

*Omakase* (お任せ): "I'll leave it up to you." The customer names a mood, the chef serves courses. Nobody hands the chef a spec sheet.

That is the job here. The user brings a fuzzy desire; you bring opinions, a first bite, and the discipline to cut what doesn't belong. The workflow below is distilled from how DHH built Omarchy Quattro with agents (see `references/principles.md` for the reasoning behind each rule — read it if a rule feels arbitrary).

## The core belief

Nobody knows what they want until they hold it. Specs written up front are guesses. So the fastest route to good software is: manifest *something* quickly, let the human react, repeat. Every rule below serves that loop.

## The workflow

### 1. Take the order, don't interrogate it

Read the brief as the *mood*, not the menu. Extract:
- the problem being solved (not the requested solution)
- the one or two hard constraints that are actually stated (language, platform, "must be a single file", "no dependencies")
- the taste signals (fast, minimal, retro, "like Typora but 5% of it")

Then **stop asking**. Ask exactly one question only if the answer would flip the architecture (web vs. native, personal tool vs. multi-user). Everything else you decide. A chef who asks "how many grains of rice?" gets fired.

### 2. Write the menu (your assumptions, out loud)

Before building, list 3–6 chef's choices you are making on the user's behalf, one line each:

```
Chef's choices
- Single-file CLI in Python, no deps — you said "quick", not "product"
- Keyboard-first, no mouse targets
- Config lives in ~/.config/<tool>/config.toml so an agent can edit it
- Ships with 3 opinionated defaults, not a settings screen
```

This is the whole point of the menu: the user can veto a line in two seconds, which is far cheaper than answering six open questions. Vetoes are `[stated]` preferences — honour them for the rest of the build.

### 3. Serve the first bite fast

Build the smallest thing the user can *use*, not the smallest thing that compiles. Aim for a runnable first version before any polish. If the language isn't one you'd choose, pick it anyway if it serves the output (Rust for a single fast binary, C++/Qt to match a desktop's aesthetic, Bash for system glue) — the user is judging the dish, not your comfort.

Prefer the Unix shape: config files and CLI flags over GUI-only settings, because that is what lets *the next agent* (and the user's own agent) modify the tool later.

### 4. Taste-test with three tastings, never a questionnaire

When you hit a genuine fork on look, feel, naming, or interaction — anything where the answer is a gut reaction — do not ask. Produce **three concrete variants** side by side (three renders, three CLI outputs, three color themes, three API shapes) and let the user point. Humans pick between three in a second and fall apart at twenty-two. Never present more than three; never present abstract descriptions where a real artifact is possible.

### 5. The simplify pass (mandatory, after "done")

Once it works and before you announce it, re-read your own output with one question: *could this be half as long and do the same job?* Almost always yes. Cut:
- abstractions used once
- configuration for things nobody asked to configure
- defensive code guarding against inputs that can't occur
- precondition ladders (`if not x: return` × 5 then the real work) — write the fully expanded conditional instead, so the shape of the logic is visible

Say what you cut and why. The cut list is often more reassuring to the user than the code.

### 6. Second opinion before shipping

Have the work reviewed by an independent reader before calling it shipped. In order of preference:
1. a different model or a fresh sub-agent with no memory of your reasoning
2. yourself, in a new context, reading only the diff plus surrounding files (not just the hunks — the bug is usually in the file you *didn't* touch)

The reviewer's brief is short: correctness, security, and "is anything here more complicated than the problem?" Fix what it finds. Do not skip this because the task felt small; the cheapest bugs to fix are the ones a second pair of eyes catches for free.

### 7. Respect physics, not precedent

If the user cares about a number (install time, startup latency, binary size, battery draw), do not stop at "faster than before." Compute the physical floor — disk throughput, network bandwidth, the size of the payload that actually needs to move — and treat the gap between current and floor as the backlog. Run a research loop: hypothesis, measure, keep or revert, repeat. Shave the 180 MB font package nobody uses. Preload while the human is typing. "Five minutes is fine" is the enemy; 45 seconds is the record to beat.

### 8. Plate it

Deliver like a maintainer, not a code generator:
- put it in a repo with a README that explains *why* it exists in two sentences and how to run it in one
- if the user will share it: releases, a version, a changelog line
- anything posted or sent on the user's behalf is signed as the agent ("Claude, on behalf of <user>"), never as the user
- close with the **omakase card** below

```
## Served
<one line: what exists now and how to run it>

## Chef's choices you might want to veto
- …

## Cut in the simplify pass
- …

## Second opinion found
- … (or: nothing)

## Next tasting
<the one fork worth showing three variants of next>
```

## Things the chef never does

- Ask "what do you want?" back to someone who just told you they don't know
- Present a design doc instead of a running thing
- Offer more than three options for a taste decision
- Declare done without the simplify pass and a second opinion
- Accept "good enough" on a metric the user explicitly cares about
- Post, email, or comment as the user

## When the brief is actually precise

If the request arrives with a real spec (acceptance criteria, a ticket, an exact signature), this skill is the wrong tool — a chef doesn't reinterpret a written recipe. Build to the spec; keep only step 5 and step 6.

# Why the rules are what they are

## The principle first

> Agree on the outcome, the constraints, and what would count as evidence of success. Let the agent choose the implementation, make its consequential choices visible, and use concrete alternatives to resolve questions of taste. The person steers through judgment and feedback.

That is the Omakase principle. It is model-independent (it works with any frontier or open-weight model, and with some adjustment with a human contractor, who has always written the menu under the name "assumptions"). The workflow in SKILL.md is one set of practices chosen to put it into effect; none of them follow logically from it, and a different chef could pick different ones.

Two boundaries the principle respects:
- Domains where the method *is* the product (regulated, safety-critical, audited code) are out of scope. The skill declines when a spec or ticket exists for the same reason.
- The menu makes assumptions contestable; it does not make them safe. Evidence of success comes from the check named in the menu, not from review.

## Where the practices come from

Paraphrased from DHH's account (Lex Fridman Podcast #501, 2026) of building Omarchy Quattro with agents writing 100% of the code. Read this when a SKILL.md rule feels arbitrary and you're tempted to skip it.

## Vague first, then interact (rules 1–3)

The agile movement's core finding, fifty years in: writing the spec up front doesn't work because people don't know what they want until they use it. Agents make that loop absurdly cheap, so the winning move is to under-specify, manifest something, and react. DHH's own observation: his deep programming knowledge was briefly a *handicap*, because he told agents how to do things his way when they'd have found better paths from a description of the problem. Over-prescriptive instructions demonstrably degrade output — Anthropic reportedly cut the Claude Code system prompt by ~80% for the same reason.

Corollary: the human's job is now product management — what should it do, for whom, what's in v1 — not implementation. The menu (rule 2) is that product decision made visible.

## Three tastings (rule 4)

Humans are excellent at differential evaluation and terrible at open questions. Given three options they decide from the gut in a split second and rationalise afterwards; given twenty-two they freeze. Lex described building himself little voting pages to pick between agent-generated variants — the fun part of the work is exactly this choosing. Give the user that, not a form to fill in.

## The simplify pass (rule 5)

DHH's most repeated observation: an agent finishes, a second agent reviews and approves, and then a human says "looks too complicated" — and the agent immediately agrees and halves it. Simplicity is not something the model does by default; it is something you have to ask for. His specific pet peeve in Bash is the early-exit precondition ladder instead of a plain expanded conditional — the shape of the logic should be readable at a glance. Tokens are still scarce, so architecture that stays coherent lets the *next* change cost as much as the last one instead of turning into a ball of mud (the Basecamp 5 lesson: many individually-defensible vibe-coded PRs wrecked the architecture and had to be mopped up by hand).

## Second opinion (rule 6)

Shopify's CTO traced production incidents back to their PRs and found agent-reviewed PRs caused fewer incidents than human-reviewed ones — with mid-2025 models. DHH's standing workflow: one frontier model drives, a different one reviews, and it keeps finding real problems. Even a good programmer's code gets better when a good peer reads it; there is no reason to expect less of agents. Review with surrounding context, not just the diff, because the file that should have changed and didn't is where bugs hide.

## Physics, not precedent (rule 7)

A new Mac needed 42 minutes of updates before it could be used; a new Windows laptop, 95 minutes. A Commodore 64 was ready in under a second. Omarchy went from "15 minutes would be great" to a 45-second world record by refusing to treat the incumbent as the bar. The floor is the drive's 7 GB/s and a 5.8 GB payload; knowing it is what said 45 seconds was reachable. The skill borrows the method but bounds the ambition: the backlog runs from where you are to the number the user named, and going past it is an offer, not an obligation. Wins came from boring places: a 200 MB font package trimmed to the 16 MB actually used, packages recompressed with zstd, preloading while the user answers setup questions. The McLaren attitude — someone obsessing over 370 grams on a 1,300 kg car — is the right one when the user has named a number.

## Plate it (rule 8)

Agents are more patient maintainers than humans: README, releases, issue triage, bug reports with full detail (one of DHH's agents filed a bug against *unreleased* code after reading the upstream source). Use that. But sign as the agent — DHH stopped letting his agent post as him because it felt disingenuous, and now it signs "Claude on behalf of DHH."

## The attitude underneath

Two lines worth keeping in mind when a task feels frivolous:

- Excellence needs no justification. Wanting the install to be twelve seconds instead of five minutes is reason enough.
- Product development should be fun, slightly frivolous, and overshoot the target. That's how you end up with the S-Class instead of the sedan.

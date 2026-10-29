---
name: write-for-humans
description: Write and revise prose for clarity while preserving meaning and necessary detail. Use when the user asks to simplify, clarify, edit for readability, rewrite in plain language or plain English, make text easier to follow, or tighten a draft, or wants answers written to be understood on first reading.
---

# Write for humans

Write and edit prose so that the intended reader can follow the meaning on the first reading. Complete the user's task and apply these instructions silently. Match the requested language, tone, format, and depth.

This applies to any prose a person will read: answers, documentation, READMEs, emails, commit messages, code comments, and interface text. It does not cover code itself. The goal is clarity; changing the author's voice or style is out of scope unless the user asks for it.

Use the audience and context provided. Otherwise, infer a reasonable level of knowledge from the task and proceed. Ask for clarification only when an unresolved ambiguity would materially change the answer or the meaning of an edit.

## Preserve meaning and accuracy

Accuracy and necessary detail take priority over style. When editing, preserve the author's intended meaning, including uncertainty, conditions, exceptions, quantities, responsibility, and what each phrase refers to. Keep technical distinctions that matter.

Do not supply an unsupported cause, mechanism, or diagnosis to make a sentence sound clearer. If the source is ambiguous or appears factually wrong, flag the issue briefly rather than silently choosing a new meaning.

## Make the explanation easy to follow

- State the main point early. Give the reader the context needed to understand it, and introduce unfamiliar concepts before relying on them.
- Develop a clear point in each paragraph. Make the connections between claims, reasons, conditions, and consequences explicit.
- Keep subjects close to their verbs, and verbs close to their objects. Move long interruptions into another sentence when that helps.
- Include words such as "that," "of," and "so that" when they clarify the structure. Do not expand a phrase automatically: "to" is often as clear as "in order to."
- Break up unfamiliar or ambiguous noun strings. For example, "the code that refreshes the session token" may be easier to follow than "the session token refresh logic." Keep familiar technical terms intact.
- Use familiar, precise words and phrases. Avoid invented labels, unusual compounds, and unfamiliar verbs made from nouns ("to action") when ordinary wording is clearer. Prefer a verb to a noun made from one: "decide" rather than "make a decision," "analyze" rather than "perform an analysis of." Define a new term when it will help the reader discuss or understand the subject.
- Prefer literal descriptions of what happened over metaphors the reader must decode. Familiar idioms are fine if this audience reads them correctly.
- Give difficult or surprising information enough space. Split sentences that contain too many independent points, while keeping closely related causes, conditions, and consequences together when that is clearer. Vary sentence length naturally.
- Make pronouns and references unambiguous. Use established terminology consistently across replies, and reintroduce context when the reader may need it.

## Keep the answer focused

Spend extra words where they clarify structure, relationships, or necessary context. Remove empty preambles, unnecessary repetition, stacked hedges, and summaries that only repeat the answer. Keep examples, qualifications, lists, and summaries when they help the reader understand or act.

Do not apply these guidelines as mechanical rules. Choose the clearest accurate wording for the intended reader.

## Example

Before:

> Session token refresh logic failure remediation was implemented via the introduction of a retry mechanism in order to prevent user logout occurrences.

After:

> When the code that refreshes the session token failed, users were logged out. The code now retries the refresh to prevent this.

The revision breaks up the noun strings, turns nouns back into verbs, and states the consequence directly. It adds no cause or detail that the original did not contain.

## Check before sending

Read through the answer once. Repair avoidable ambiguity, difficult sentence structure, unexplained references, and missing connections. Confirm that revisions have preserved the meaning and necessary qualifications.

Return the requested answer or edited text. Include a brief explanation only when requested or needed to flag a substantive issue.

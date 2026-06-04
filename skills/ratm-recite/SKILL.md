---
name: ratm-recite
description: Render a recitation — a recap of what a system does, or an idea presented back for confirmation — as a laid-out HTML page opened in the browser, so the user reads a clean visual surface instead of a wall of terminal text, then aligns in chat. Use this whenever you are about to recite, recap, summarize, or "play back" how something works for the user to confirm: "recite what X does", "recap the design", "summarize this system", "walk me through the architecture", "present this idea back to me", or any time you would otherwise dump a long structured explanation (multiple sections, tables, comparisons) into chat for the user to scan and approve. Especially use it when the recap is dense or tabular. Do NOT use it for short answers, code edits, or normal conversational replies.
---

# ratm-recite

Present a recitation as a browser page, then align in chat.

**Recitation** = recapping how a system works, or playing an idea back to the user for confirmation. A dense recap (sections, tables, side-by-sides) reads far better as a laid-out HTML page than as terminal text. This skill writes that page and opens it. **Alignment happens in chat** — there are no buttons in the page.

## Why this shape (don't add machinery)

A confirmation button would only capture one bit — *aligned* vs *needs changes* — which the chat already carries for free. A local server or download handshake to recreate that bit is effort without function. And no web page can programmatically close a tab the user opened. So the page is a **read-only presentation surface**; the chat is the control channel. Keep it that way.

## The flow

1. **Author the recap as HTML.** Two options:
   - **Fragment + styling** (recommended for consistency): write a body fragment (no `<html>`/`<head>`) — headings, `<p>`, `<table>`, `<pre>` — then let the script wrap it in the shared shell (`assets/shell.html`) which supplies CSS, dark-mode, and the header. See `assets/example-content.html` for the shape.
   - **Full document**: write a complete self-contained `.html` (inline its own CSS) and open it as-is. Use when you want full control of layout.
2. **Open it** with the script:
   - Fragment: `pwsh -File <skill>/scripts/recite.ps1 -Html <fragment.html> -Wrap -Title "<topic>"`
   - Full doc: `pwsh -File <skill>/scripts/recite.ps1 -Html <doc.html>`
   - POSIX: `bash <skill>/scripts/recite.sh --html <path> [--wrap] [--title "<topic>"]`
   - The script opens the default browser and prints the file path (so the user can open it manually if the browser didn't launch).
3. **Ask for alignment in chat.** After opening, present the alignment ask: a plain "Does this look right, or what should change?" — or, when the choice is crisp, an `AskUserQuestion` with options like *Aligned* / *Needs changes*.
4. **React:**
   - **Aligned** → done. The browser tab is disposable; the user closes it.
   - **Needs changes** → revise the HTML, re-run the script (overwrites the same temp file), and ask again.

## Authoring tips

- Lead with the most important content first (top of page) — the user scans top-down.
- Prefer tables for comparisons and role/responsibility lists; `<pre>` for diagrams and ASCII flow.
- Keep fragments to semantic HTML; the shell handles all styling. Don't inline `<style>` in a fragment (only in a full doc).
- Write the fragment to a temp path yourself (e.g. under the system temp dir), then point `-Html` at it. The composed/opened file lands in `$env:TEMP/ratm-recite/recite.html`.

## Non-goals

- **No server, no ports, no `signal.json`, no in-page buttons.** Presentation only.
- **No auto-close.** "Done" is the user saying so in chat.
- **No writing into any repo.** Scratch lives in the system temp dir only.

## Files

- `scripts/recite.ps1` — primary: compose-if-`-Wrap`, open in browser, print path.
- `scripts/recite.sh` — POSIX shadow at parity.
- `assets/shell.html` — styling chrome for `-Wrap` (inline CSS, dark-mode, no JS).
- `assets/example-content.html` — sample recap fragment (recites the ratmac skill set).

## Spec

Design + invariants (RR1–RR6) + the cut-list (what was removed and why) live in
`brain/buf/sparks/pdrft-brain-v3/s-ratm-recite/`.

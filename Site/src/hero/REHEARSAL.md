# Rehearsal: Retouche hero

Gold: `hero-demo` for the story beside copy and its one explaining note; `close-up` for the frame. Kept: one gutter, a window inset top-left and bled right and bottom, the whole window scaled (1.4×, 1.2× compact) so the subject line is large. Changed: no cursor (typing is the gesture), a Mail compose window, and Retouche's own letter animation (`morph.ts`, ported from `Retouche/Overlay/LetterMorph.swift`, with the overlay's spring timings) instead of popups.

Beats: open on "Salut Léa," with the caret waiting · "deja" becomes "déjà" on its space · "cafr" becomes "café" 0.6 s later while "de la gare." is typed (Apple Intelligence's late answer), and the note "Le sens de la phrase : café, pas car" draws in as the letters lift · a new line in English · "teh" hops into "the" · payoff holds. `play="once"`, about 10 s; the page's "Rejouer la démo" fades the scene out and remounts it.

Captured: 1280 and 390 wide on the host page, `--states` at both, close-ups of each correction (`--zoom`), the café beat at `--slow 4`, the final still at both widths, Replay in the browser. Light look only (the page is light). Poster: the finished email with the note.

Film:
- `rehearsal passed` at 1280 and 390 on the host page.
- `jump: span … width` and `jump: rt-caret x`: each typed character and the caret following it. Typing is instant in a real text field; intentional.
- `appears with no entrance: span.rt-caret`: the caret moving to the next line on Return, as macOS does; intentional.
- `manual: same-box content change` on "deja" and "teh": the word is replaced in the text the instant its space is typed, under the floating letters, exactly as Retouche edits the host app's text; watched at 70 ms steps.
- `manual: same-box content change` on the connector: its endpoints follow "café" while it is hidden; never visible.
- Fixed along the way: `unclipped` and `framing` (stage `overflow: hidden`, one 40 px gutter), the compact window ending 19 px past the bottom, the compact note 6 px from the edge, the compact stage growing past its design size (now designed at 374, the phone column with the bleed to the screen edge).

Review (fresh eye, against `hero-demo`) → response:
1. Focal content too small for the frame → close-up layout, the window scaled 1.4×; the text now spans most of the visible body.
2. The hero shadow read as a gray band on the white page → a short fall whose side spread fades inside the gutter.
3. At 390 the bleed stopped 16 px short of the screen → the demo column runs to the screen's right edge on phones.
4. A Return keycap was the heaviest mark → removed.
5. Nothing explained café at 390 → the note stays in compact, shortened to "café, pas car".
6. Double-spaced body → 1.3 leading, one blank line after the greeting only.
7. The note arrived after the letters had gone → it starts as they lift; it stays a small gray tag to the right of "café" so it reads as said about the email, not in it.
8. It never loops → kept `play="once"` with Replay (the Slack study's pattern): a send-and-reopen loop would add a beat about Mail, not Retouche.
9. Replay was a hard cut → 200 ms fade out, remount, fade in.
10. "cafr" is fixed late → kept: it is the product's deferred Apple Intelligence answer; the note now starts with it so the wait reads as a decision.
11. The morph ignored `--slow` → it reads the same slowdown the Stage reads.
12. "Aa" smaller and lighter than its neighbors → removed; paper plane and paperclip at one size and stroke.

Assumptions: Retouche's accent (#4A7AFF, the app's AccentColor) for the caret, the recipient and the letters, as the overlay uses the app tint. The page copy says the rest (bilingual, on-device).

Unresolved: the text after "café" shifts by about 3 px when "cafr" is replaced, as in the real app. The page shows nothing of the menu-bar icon.

Not checked: dark mode (the page is light), Safari and Firefox rendering of the letter blur, a hidden tab mid-play.

# Design

The iPhone app has one design system, defined in `ios/BogoKit/BogoSection/Theme.swift` and used by every screen, BOGO and the host app alike. This page records what it borrows from the apps people trust with money, and the rules it follows.

## What makes the references feel premium

Studied: Stripe (Dashboard app and Link), Mercury, Coinbase (and its open-source CDS), Cash App, Revolut, Robinhood and the Apple Pay sheet, from App Store screenshots, product pages, design write-ups and Apple's guidance on haptics and feedback.

- **Colour restraint.** Mercury has no promotional colours at all: near-black ink on a warm off-white, and colour only where it carries meaning (green for money in, nothing loud for money out). Its own job posts quote Rams, "less but better", and ask designers to know when restraint serves people better. Stripe and Coinbase do the same on mobile: one accent, used sparingly.
- **Numbers are the hero.** Robinhood, Cash App and Coinbase set the amount huge, in tight, tabular figures, all in one colour. The amount is the first thing your eye lands on, and it never jitters as digits change.
- **Calm type scale.** Few sizes, big jumps between them, tight negative tracking on large text, small sentence-case labels in grey. No bold soup.
- **Rows on one surface.** Lists read like a bank statement: a title, a muted line, the amount on the right, hairlines between rows, no cards around them.
- **Deliberate confirm gestures.** Coinbase CDS ships a `SlideButton` (gesture, spring animation and an accessibility action). Swipe-to-pay controls tick lightly as you drag, land with a heavier haptic, and snap back if released early. Apple Pay ends with a checkmark that draws itself, its sound and haptic designed to match the animation (WWDC19, Core Haptics).
- **Haptics you'd miss.** Apple's guidance: match intensity and sharpness to the animation, keep a clear cause and effect, use system patterns for their documented meanings, and don't overuse them.
- **Motion that explains.** Springs with high damping, no bounce for its own sake; things arrive from where they came from (iOS 26 zoom transitions); success is short and certain.

Sources: [Mercury design breakdown (925 Studios)](https://www.925studios.co/blog/mercury-design-breakdown), [Mercury senior product designer posting](https://job-boards.greenhouse.io/mercury/jobs/5677872004), [Coinbase open-sources its design system](https://coinbase.com/blog/Coinbase-has-open-sourced-its-design-system), [CDS docs](https://cds.coinbase.com/getting-started/introduction), [Apple HIG: playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics), [Apple HIG: feedback](https://developer.apple.com/design/human-interface-guidelines/feedback), [WWDC19 Introducing Core Haptics](https://developer.apple.com/videos/play/wwdc2019/810), [Apple HIG: Apple Pay](https://developer.apple.com/design/human-interface-guidelines/apple-pay).

## What T19 learned from the real screens

T18 borrowed the right ideas but dressed them up, and the owner called the result AI slop. T19 put the app next to the real App Store screenshots of Mercury, Stripe Dashboard and Coinbase (kept in the T19 evidence folder) and removed everything they don't do:

- **One surface.** Stripe's payment-link screen and Coinbase's home are white (or black) pages. Sections are a sentence-case header with a hairline under it, then rows. Nothing sits in a card inside a card.
- **Rows, not tiles.** A row is a label on the left and a value on the right (Stripe's Details, Balances), or a title, a grey line under it and an amount on the right (a statement). No icon tile in front of a row unless the icon carries meaning.
- **Plain prices.** Stripe ($36.00, $12.50) and Coinbase ($15,957.99) set the whole amount in one colour. Mercury raises its cents but keeps them the same colour. BOGO uses one colour, tabular figures.
- **Small grey labels over content.** Mercury's transaction detail labels each block ("Category", "Notes") in small grey sentence case. BOGO's "Reason" and "Details" do the same.
- **Colour only for state.** Green for approved or connected, red for denied or destructive, amber for a warning. Text carries it; there are no washes behind it.

## Never

Later work keeps these rules. If a detail would look out of place in Mercury, it goes.

- **No decorative icons.** No sparkles (✦, `sparkle`, `sparkles`), no icon tiles in front of rows or titles, no icon next to a label that already says what it is. Icons are controls (back, more, close, chevrons, the slider knob, tab bar) or carry a meaning a word can't.
- **No letter avatars or monograms.** The agent is a line of text: "Shopping agent · 7:10 AM".
- **No badges or pills** on pictures, rows or titles: no "Agent's picture" chip, no "×2" capsule, no status dots with glows, no check or cross badges on thumbnails. Say it in the row's text ("3 identical", "Approved").
- **No tinted, gradient or glowing boxes.** No amber card for the reason, no green wash behind a check, no breathing rings, radar sweeps, shimmer sheens or drop shadows on content. Warnings are coloured text.
- **No uppercase, letter-spaced labels.** Section names are sentence case: "Details", "Today", "Ready to add".
- **No nested cards.** One surface per screen; separate sections with space and hairlines.
- **No code names on the card.** `spend-request_create · call_write_tool on stripe` becomes "Stripe · Create spend request". Raw identifiers live only in All details.
- **No grey cents**, no second colour inside a number.
- **Nothing covers content.** The approve bar has its own area with a hairline over it, and the page scrolls above it.
- **No emoji, rainbow accents or buzzword copy.** Plain words: "Not verified by BOGO", "Image from the agent".

## The system

| Token | Light | Dark | Use |
|---|---|---|---|
| `Ink.canvas` (= `surface`) | #FFFFFF | #0A0A0B | Every screen and sheet: the one surface |
| `Ink.raised` | #F3F3F4 | #1C1C1F | Text fields, the locked slider, secondary buttons |
| `Ink.hairline` | ink at 9% | white at 11% | Dividers under section headers, between rows, over the approve bar |
| `Ink.primary` | #0B0B0C | #F4F4F2 | Text, primary buttons, the slider |
| `Ink.secondary` / `tertiary` | #6B6B70 / #9E9EA3 | #9C9CA2 / #66666C | Labels, metadata, footnotes |
| `Ink.positive` | #13985A | #3DD68C | Approved, connected (text only) |
| `Ink.negative` | #D23F3F | #FF6B6B | Denied, destructive (text only) |
| `Ink.warning` | #B25E0B | #F2B252 | The mismatch warning and other cautions (text only) |

- **Type** (`.type(_:)`), SF Pro scaled with Dynamic Type: display 46 semibold (the price, tabular), title 28, title2 22, headline 17, body 17, callout 15, label 14, caption 12.5, mono 14. Large sizes have slight negative tracking; nothing is uppercased or letter-spaced.
- **Spacing**: 4, 8, 12, 16, 20, 24, 32, 48; 20 pt gutter. Sections are 32 pt apart.
- **Components**: `SectionHeader` (sentence-case headline), `FieldLabel` (small grey label), `RowSection` (header, hairline, rows), `DetailRow` (label left, value right, stacks when long), `Hairline`, `Chevron`, `DoneMark` (a thin green ring and a check that draw themselves). Buttons: primary (ink capsule), secondary and destructive (raised capsule, ink or red text), quiet (text).
- **Radii**: sheets 32, opaque pictures 14, text fields 12, all continuous.
- **Materials**: solid surfaces; system Liquid Glass only for the tab bar and toolbar buttons.
- **Haptics** (`Haptics`): select on tab change, soft when a request arrives or the slider arms, rising light ticks while sliding, a rigid thud on release, success after Face ID signs, warning when Add Mac fails.
- **Motion** (`Motion`): standard spring (0.48 s, 0.86 damping), snappy for controls, gentle for pictures; zoom transition from a request row into its review; the success check draws in under a second. With Reduce Motion every move becomes a short fade.

## The Review screen

Top to bottom, on one surface:

1. **Title**: the `title` role, or the action in words ("Create deployment") when there is none. Under it, the `subtitle` role when there's no price, then "Shopping agent · 7:10 AM".
2. **Picture**: the `image` role, or the first picture T14 finds in the arguments, fitted whole in a 240 pt tall area straight on the page: transparent pictures (the Rubik's Cube SVG) float, opaque photos get rounded corners. A spinner while it loads, "No preview" and the reason if it fails. Tapping it shows the exact link and says BOGO didn't check it. SVG links are drawn natively (`VectorPicture.swift`).
3. **Subtitle and price**: the merchant in grey, then the amount in display type.
4. A hairline, then **Reason**: a grey "Reason" label, the agent's words in body text, the mismatch warning (SPEC §3.15) as amber text, and a grey footnote: "Not verified by BOGO" and "Sent by claude-code · session 005482d1".
5. A hairline, then **Details**: "Action" (service and action in words), the `text` highlights, the expiry countdown, "Requested by", "Runs on", "Image · From the agent" when there's a picture, then **All details** with the count of signed values. All details opens the full exact request: upstream, tool, every argument (T16's tree, empty values folded behind a tap), the exact reason, the request facts and every display hint.
6. **The approve bar**, in its own area under a hairline: the slider stays locked for the arm delay ("Read it first", a ring fills on the knob), then slides with rising haptics, then Face ID, then the success screen. Deny is a quiet text button that opens a small sheet for an optional note. VoiceOver gets a plain "Approve" action.

## Screens

- **BOGO home**: "BOGO" and the connected Mac's name (to Macs) on one line; "1 request waiting" with "Nothing runs until you approve."; waiting requests as statement rows (title, agent and age, amount and time left on the right, an amber line when the amount differs from the reason); then "Ended" and "Recent". With no Mac: "Connect your Mac" and Add Mac.
- **Activity**: a statement grouped by day; each row says what happened in words, with "Approved" in green and "Denied" in red, and the amount grey unless it was approved.
- **Macs, Add Mac**: Macs as rows with their status in words; Add Mac shows the command, a spinner while it looks, the 6-digit code as large tabular figures, and the drawn check when added.
- **Settings**: BOGO's Macs, Apple Bridge pairing, capabilities, Diagnostics and (Debug) Demo, as plain row sections; system forms (pairing, each capability, Screen Time) share the canvas and line up with the 20 pt gutter.
- **Tab bar**: BOGO, Activity, Settings.

## Demo mode (Debug builds only)

Settings → Demo sends a realistic request from the stand-in Mac 3 seconds after you tap, so a full flow can be filmed with no real Mac: the Link purchase (the real `spend-request_create` with the Rubik's Cube SVG), an email send, a deploy with no roles, and a purchase whose reason doesn't match its amount. "Quiet stand-in Mac" makes Add Mac send no sample requests. The same requests can be dropped into the stand-in inbox as `{"demo":"link-purchase"}` (also `email`, `no-roles`, `mismatch`). None of it is compiled into Release builds.

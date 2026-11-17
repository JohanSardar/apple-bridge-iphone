# Design

The iPhone app has one design system, defined in `ios/BogoKit/BogoSection/Theme.swift` and used by every screen, BOGO and the host app alike. This page records what it borrows from the apps people trust with money, and the rules it follows.

## What makes the references feel premium

Studied: Stripe (Dashboard app and Link), Mercury, Coinbase (and its open-source CDS), Cash App, Revolut, Robinhood and the Apple Pay sheet, from App Store screenshots, product pages, design write-ups and Apple's guidance on haptics and feedback.

- **Colour restraint.** Mercury has no promotional colours at all: near-black ink on a warm off-white, and colour only where it carries meaning (green for money in, nothing loud for money out). Its own job posts quote Rams, "less but better", and ask designers to know when restraint serves people better. Stripe and Coinbase do the same on mobile: one accent, used sparingly.
- **Numbers are the hero.** Robinhood, Cash App and Coinbase set the amount huge, in tight, tabular figures, and quieten the cents. The amount is the first thing your eye lands on, and it never jitters as digits change.
- **Calm type scale.** Few sizes, big jumps between them, tight negative tracking on large text, small sentence-case labels in grey. No bold soup.
- **Cards, not tables.** Rounded continuous corners, generous inner padding (20 pt), hairline borders and a barely-there shadow in light mode; flat raised surfaces in dark mode. Lists read like a bank statement: a tile, a title, a muted line, the amount on the right.
- **Deliberate confirm gestures.** Coinbase CDS ships a `SlideButton` (gesture, spring animation and an accessibility action). Swipe-to-pay controls tick lightly as you drag, land with a heavier haptic, and snap back if released early. Apple Pay ends with a checkmark that draws itself, its sound and haptic designed to match the animation (WWDC19, Core Haptics).
- **Haptics you'd miss.** Apple's guidance: match intensity and sharpness to the animation, keep a clear cause and effect, use system patterns for their documented meanings, and don't overuse them.
- **Motion that explains.** Springs with high damping, no bounce for its own sake; things arrive from where they came from (iOS 26 zoom transitions); success is short and certain.

Sources: [Mercury design breakdown (925 Studios)](https://www.925studios.co/blog/mercury-design-breakdown), [Mercury senior product designer posting](https://job-boards.greenhouse.io/mercury/jobs/5677872004), [Coinbase open-sources its design system](https://coinbase.com/blog/Coinbase-has-open-sourced-its-design-system), [CDS docs](https://cds.coinbase.com/getting-started/introduction), [Apple HIG: playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics), [Apple HIG: feedback](https://developer.apple.com/design/human-interface-guidelines/feedback), [WWDC19 Introducing Core Haptics](https://developer.apple.com/videos/play/wwdc2019/810), [Apple HIG: Apple Pay](https://developer.apple.com/design/human-interface-guidelines/apple-pay).

## The system

| Token | Light | Dark | Use |
|---|---|---|---|
| `Ink.canvas` | #F6F6F4 | #0A0A0B | Screen background |
| `Ink.surface` | #FFFFFF | #151517 | Cards |
| `Ink.raised` / `Ink.well` | #F1F1EE / #EFEFEC | #1D1D20 / #1A1A1D | Tiles, picture frames, inputs |
| `Ink.primary` | #0B0B0C | #F4F4F2 | Text, primary buttons, the slider |
| `Ink.secondary` / `tertiary` | #6C6C70 / #A3A3A8 | #9C9CA2 / #5F5F65 | Labels, metadata |
| `Ink.accent` | #4F46E5 | #8B85FF | Links only ("All details") |
| `Ink.positive` | #13985A | #3DD68C | Approved, connected |
| `Ink.negative` | #D23F3F | #FF6B6B | Denied, destructive |
| `Ink.claim` | #A86412 | #F2B252 | Anything the agent claims: its reason, its pictures, the mismatch warning |

- **Type** (`.type(_:)`), SF Pro scaled with Dynamic Type: display 54 semibold (price, −2.2 tracking, tabular, cents at secondary grey), title 30, title2 22, headline 17, body 17, callout 15, label 14, caption 12.5, eyebrow 12 semibold uppercase.
- **Spacing**: 4, 8, 12, 16, 20, 24, 32, 48; 20 pt gutter.
- **Radii**: card 26, inner 18, tile 12, all continuous.
- **Materials**: solid surfaces; system Liquid Glass only for the tab bar and toolbar buttons; ultra-thin material for the "Agent's picture" chip.
- **Icons**: SF Symbols, medium weight, in rounded-square tiles; the request's picture replaces the tile when there is one.
- **Haptics** (`Haptics`): select on tab change, soft when a request arrives or the slider arms, rising light ticks while sliding, a rigid thud on release, success after Face ID signs, warning when Add Mac fails.
- **Motion** (`Motion`): standard spring (0.48 s, 0.86 damping), snappy for controls, gentle for pictures; zoom transition from a request card into its review; the success check draws in 0.8 s. With Reduce Motion every move becomes a short fade, and shimmer, sheen and pulse stop.

## The Review card

Top to bottom, as the owner sketched it on 2026-11-17:

1. **Who and what**: the agent's monogram and name, "wants to pay" or "wants to run", and under the title the action, tool and upstream (`spend-request_create · call_write_tool on stripe`). Who is asking and what will run are always on the card.
2. **Title**: the `title` role, or the action or tool when there is none.
3. **Image**: the `image` role, or the first picture T14 finds in the arguments. A fixed 4:3 frame on a neutral well, the whole picture fitted inside, shimmer while loading, a quiet "No preview" with the reason if it fails. SVG links are drawn natively (`VectorPicture.swift`: paths, shapes, transforms and gradients; no scripts, no web view, no network beyond the one capped fetch). A chip marks it "Agent's picture"; tapping it shows the exact link and says the picture is the agent's claim.
4. **Subtitle and price**: the `subtitle` role, and the first money highlight in display type.
5. **Reason**: an amber card, "Agent's reason · unverified", with the mismatch warning inside it (SPEC §3.15), the client and the session tag.
6. **Details**: quiet rows for `text` highlights, the expiry countdown, who requested it and which Mac, then **All details**, which opens the full exact request: upstream, tool, every argument (T16's tree, empty values folded behind a tap), the exact reason, the request facts and every display hint.
7. **Slide to approve, then Deny**. The slider stays locked for the arm delay (a ring fills on the knob), then slides with rising haptics, then Face ID, then the success state. Deny is a quiet text button that opens a small sheet for an optional note. VoiceOver gets a plain "Approve" action.

## Screens

- **BOGO home**: wordmark, the connected Mac as a status chip, "1 request waiting", rich pending cards (agent, age, title, merchant, price, picture, countdown, ×N for duplicates), ended requests muted, and the last three decisions. Empty states: "Connect your Mac" and "Nothing needs you".
- **Activity**: a statement, grouped by day; approved amounts in ink, denied and expired amounts struck through in grey, a small status badge on each tile.
- **Macs, Add Mac**: Macs as a card list with a status dot; Add Mac shows the command, a searching radar, the 6-digit code in tiles, and a drawn check when added.
- **Settings**: BOGO's Macs, Apple Bridge pairing, capabilities and Diagnostics in one gear tab; system forms (pairing, each capability, Screen Time) share the canvas and tint.
- **Tab bar**: BOGO, Activity, Settings.

## Demo mode (Debug builds only)

Settings → Demo sends a realistic request from the stand-in Mac 3 seconds after you tap, so a full flow can be filmed with no real Mac: the Link purchase (the real `spend-request_create` with the Rubik's Cube SVG), an email send, a deploy with no roles, and a purchase whose reason doesn't match its amount. "Quiet stand-in Mac" makes Add Mac send no sample requests. The same requests can be dropped into the stand-in inbox as `{"demo":"link-purchase"}` (also `email`, `no-roles`, `mismatch`). None of it is compiled into Release builds.

# Transparency and Theater Reply Settings Design

## Scope

- Every user-facing control labelled as transparency uses `0% = opaque` and
  `100% = transparent`.
- Existing stored opacity/alpha fields stay unchanged, so upgrades preserve the
  current visual result. The UI converts with `transparency = 1 - opacity` when
  reading and `opacity = 1 - transparency` when saving.
- The conversion applies to interface background, navigation bar, list cards,
  character/theater background images, chat inputs, and chat bubbles.

## Dynamic Theater Reply Choices

Let `N` be the enabled, unmuted AI participant count, excluding the user
identity.

- Main replies: `1` through `N - 1`, followed by `全部`; `全部` keeps the existing
  stored value `0`.
- Extra replies: `不追加`, followed by `0-1个` through `0-(N - 1)个`.
- For zero or one available AI participant, main replies show only `全部` and
  extra replies show only `不追加`.
- Stored reply values remain non-negative integers. The existing reply engine
  already limits generated replies to the available participant count.

## Implementation

- Reuse one small opacity/transparency conversion helper in every affected UI.
- Add the available participant count to the existing `TheaterReplySettings`
  widget and generate its chips from that count.
- Remove the obsolete model upper limit of `2`; retain non-negative validation.
- Do not rename persisted JSON fields or add a migration.

## Verification

- Unit-check both ends of the opacity/transparency conversion.
- Widget-check four- and five-participant reply choices and their compact labels.
- Round-trip reply counts greater than two through `TheaterSession` JSON.
- Run formatting, static analysis, the full Flutter test suite, then build and
  inspect the arm64-only release APK.

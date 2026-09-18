# Chat input border opacity design

## Goal

Restore the visible chat input outline without bringing back the opacity jump that previously appeared while an API reply was generating.

## Design

- Keep the existing input surface, shadow, focus, keyboard, and generation behavior unchanged.
- Give the input field an outline in its default, enabled, focused, and disabled states.
- Use the configured `inputOpacity`, clamped to `0...1`, as the outline color alpha in every state.
- Use the theme outline color normally and the theme primary color while focused.
- Verify the decoration with a focused widget test, then run the project checks and build only the Android arm64-v8a release APK.

## Scope

No version change, button behavior change, Git operation, or release publication is included.

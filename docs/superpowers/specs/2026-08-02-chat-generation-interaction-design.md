# Chat Generation Interaction Design

## Goal

Keep normal chat controls usable while an assistant reply is being generated, without cancelling the active API request. Destructive delete actions and summary actions remain unavailable until generation ends. Sending must keep the text input focused and the input must never draw an outline border.

## Interaction rules

- While `_isSending` is true, settings, memory management, search, copy, add-to-memory, session management, and other non-destructive navigation remain enabled.
- Opening those controls must not call `_cancelActiveGeneration` or invalidate the active generation.
- Message or candidate deletion, clearing the chat, deleting a session, and manual/history-summary mutations remain disabled during generation.
- A second generation cannot start concurrently. The composer continues to show the existing Stop action while a reply is active; retry, regenerate, and edit-resend wait until the current generation is no longer active.
- If the user chooses another session while generation is active, the selection is deferred until the active reply finishes naturally. The API token is not cancelled.
- Summary-time protections remain unchanged; this adjustment is specifically for `_isSending`.

## Input behavior

- The `TextField` remains enabled during generation, so tapping Send does not remove focus or dismiss the software keyboard.
- The user may type the next message while the current reply is generated. The action button remains Stop until generation completes.
- `border`, `enabledBorder`, `focusedBorder`, and `disabledBorder` use `InputBorder.none`, so no generation-only outline appears.
- A dedicated `FocusNode` owned by `ChatScreen` makes focus retention explicit and testable.

## Safety and data flow

- Generation ownership remains bound to `generationId` and `sessionId`.
- Non-destructive screens are pushed over the active `ChatScreen`, allowing streaming state updates underneath.
- Session switching waits on an operation-completion future owned by the active generation, then reloads the selected session.
- Delete and summary handlers retain defensive guards in addition to disabled UI.

## Tests

- Start a controlled stream and verify settings, memory, and session-management controls are enabled without cancelling the stream.
- Verify delete and summary controls remain disabled during generation.
- Focus the input, send, and verify the `FocusNode` stays focused and the test keyboard stays visible.
- Verify every `TextField` border state is `InputBorder.none` before and during generation.
- Verify a selected session change is deferred until generation completes and does not cancel the gateway token.

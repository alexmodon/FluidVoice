# Update prompt regression checks

Run the native presenter harness with full Xcode selected:

```sh
sh Tests/run_update_prompt_tests.sh
```

The signed app-host XCTest cases are `UpdatePromptIntegrationTests` and `SimpleUpdaterTests` in `FluidDictationIntegrationTests`. Keep Apple Development signing enabled.

## Safe Debug simulation

Build with the private FI development script. Launch a **separate Debug app** with `FLUIDVOICE_UPDATE_UI_SIMULATION=1`; do not replace the installed app. Then use its exact PID:

```sh
swift Tests/trigger_update_ui_simulation.swift <pid> offer
swift Tests/trigger_update_ui_simulation.swift <pid> progress
swift Tests/trigger_update_ui_simulation.swift <pid> failure
swift Tests/trigger_update_ui_simulation.swift <pid> dismiss
```

The launch flag disables automatic update checks and routes manual installation through the real operation gate/status window, returning before any download, file replacement, or restart. Offer buttons skip persisted snooze changes. Failure/dismiss reset the simulated operation. Release builds omit this seam.

`dictation-toggle` requires the existing `FluidDebugRemoteToggleEnabled` defaults flag as well as a Debug build. It uses a distinct PID-scoped notification, so older installed instances do not receive it. This invokes the real capture/stop/delivery path. **Verify the actual foreground app and capture target before using it**: a background accessibility focus action alone does not establish the dictation destination. Use a disposable field, never an active chat or document. Microphone reconciliation can persist Debug microphone preferences; snapshot and restore them when overriding input selection.

## Verification on macOS 27 / Apple Silicon

- Controlled old-dialog harness: a native modal-mode timer ended `NSAlert.runModal` after 0.436 seconds; queued MainActor work remained blocked until it returned.
- Current presenter harness: queued MainActor work runs while the prompt stays unanswered; external and own-field focus, text completion, primary/cancel actions, duplicate/empty/bounded queue, stale buttons, dismissal, and recovery pass.
- Four signed app-host XCTest cases pass, including progress clearing outstanding/queued notices and invalidating old actions.
- Signed FI Debug build passed. A separate runtime copy used the existing build-script framework-normalization approach and Apple Development identity; its strict signature passed. The raw Xcode bundle required CTranscribe signature repair after framework headers were stripped.
- Real built-in microphone capture started before an offer, remained active, then finalized/pasted with that offer still unanswered. The first run targeted the user's foreground Claude field instead of the intended disposable field; this is not controlled TextEdit destination proof. Further capture tests were stopped.
- Actual Debug offer, animated indeterminate progress, repeated offer suppression during progress, failure replacing progress, and error dismissal were observed. No update downloaded, installed, or restarted.

Limits: no physical-hotkey/Escape proof, controlled ASR/AI arrival overlap, Intel, older macOS, Reduce Transparency, or VoiceOver runtime validation. Escape's recording-cancel behavior and deliberate Install Now restart behavior remain existing behavior. The screenshot in the PR is rendered by the native presenter harness with the current app icon; it is not a production screenshot.

#!/bin/sh
set -eu
task_developer_dir="${DEVELOPER_DIR:-$(xcode-select -p)}"
test -d "$task_developer_dir/Platforms/MacOSX.platform" || { echo "Full Xcode required" >&2; exit 1; }
export DEVELOPER_DIR="$task_developer_dir"
task_repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_test_dir=$(mktemp -d /tmp/fluidvoice-update-prompt-tests.XXXXXX)
trap 'rm -rf "$task_test_dir"' EXIT
xcrun swiftc "$task_repo_dir/Sources/Fluid/Theme/FluidTypography.swift" "$task_repo_dir/Sources/Fluid/UI/UpdatePromptPresenter.swift" "$task_repo_dir/Tests/UpdatePromptTests.swift" -o "$task_test_dir/update-prompt-tests"
"$task_test_dir/update-prompt-tests"
python3 - "$task_repo_dir" <<'PYTEST'
from pathlib import Path
import sys
source = (Path(sys.argv[1]) / 'Sources/Fluid/AppDelegate.swift').read_text()
update_prompts = source[source.index('    private func showUpdateNotification('):]
assert 'runModal' not in update_prompts
assert 'clearUpdateSnooze()' in update_prompts and 'snoozeUpdatePrompt(forVersion: version)' in update_prompts
assert 'self?.checkForUpdatesManually()' in update_prompts
assert update_prompts.count('presentFloatingPrompt(') == 2
assert 'UpdatePromptPresenter.shared' in source
for relative_path, start, end in [
    ('Sources/Fluid/UI/SettingsView.swift', 'Button("Check for Updates")', 'Button("Release Notes")'),
    ('Sources/Fluid/Services/MenuBarManager.swift', '@objc private func checkForUpdates(', '@objc private func rollbackToPreviousVersion('),
]:
    text = (Path(sys.argv[1]) / relative_path).read_text()
    update_section = text[text.index(start):text.index(end, text.index(start))]
    assert 'runModal' not in update_section, relative_path
    assert 'SimpleUpdater.shared.checkForUpdatesManually()' in update_section, relative_path
updater = (Path(sys.argv[1]) / 'Sources/Fluid/Services/SimpleUpdater.swift').read_text()
manual = updater[updater.index('    func checkForUpdatesManually('):updater.index('    func checkAndUpdate(')]
assert 'runModal' not in manual
assert 'UpdatePromptPresenter.shared.presentFloatingPrompt(' in manual
assert 'catch SimpleUpdateError.updateAlreadyInProgress' in manual
status = updater[updater.index('    func showUpdateInstallStatus('):updater.index('    private func resetUpdateOperation(')]
assert 'UpdatePromptPresenter.shared.dismissAll()' in status
assert 'progress.startAnimation(nil)' in status
print('PASS: all updater result paths use shared nonmodal prompts; install/snooze preserved; status clears prompts and starts animation')
PYTEST

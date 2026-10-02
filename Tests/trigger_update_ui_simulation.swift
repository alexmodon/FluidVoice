import Foundation

let arguments = CommandLine.arguments
let scenarios: Set<String> = ["offer", "progress", "failure", "dismiss", "dictation-toggle"]
guard arguments.count == 3, let pid = Int32(arguments[1]), pid > 0,
      scenarios.contains(arguments[2])
else {
    FileHandle.standardError.write(Data("Usage: swift Tests/trigger_update_ui_simulation.swift <simulation-app-pid> offer|progress|failure|dismiss|dictation-toggle\n".utf8))
    exit(64)
}

DistributedNotificationCenter.default().postNotificationName(
    Notification.Name(arguments[2] == "dictation-toggle" ? "com.FluidApp.debug.toggleRecording.scoped" : "com.FluidApp.debug.updateUI"),
    object: String(pid),
    userInfo: ["scenario": arguments[2]],
    deliverImmediately: true
)

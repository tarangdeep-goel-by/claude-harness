#!/usr/bin/env swift

import Cocoa
import AVFoundation

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var recorder: AVAudioRecorder?
    var isRecording = false
    var currentFile: URL?
    var startTime: Date?
    var timer: Timer?

    var vaultInbox: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        // Store in Daily/<date>/ so all recordings from the same day are together
        let dateStr = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: Date())
        }()
        return home.appendingPathComponent("Documents/vault-work/Daily/\(dateStr)")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateMenuBarIcon(recording: false)
        setupMenu()
    }

    func updateMenuBarIcon(recording: Bool) {
        DispatchQueue.main.async {
            if recording {
                self.statusItem.button?.title = "🔴 REC"
            } else {
                self.statusItem.button?.title = "🎙"
            }
        }
    }

    func setupMenu() {
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func buildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        if isRecording {
            let elapsed = startTime.map { Int(Date().timeIntervalSince($0)) } ?? 0
            let min = elapsed / 60
            let sec = elapsed % 60
            let duration = String(format: "%d:%02d", min, sec)

            let status = NSMenuItem(title: "Recording... \(duration)", action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)

            menu.addItem(NSMenuItem.separator())

            let stop = NSMenuItem(title: "⏹ Stop Recording", action: #selector(stopRecording), keyEquivalent: "x")
            stop.keyEquivalentModifierMask = [.command, .shift]
            menu.addItem(stop)
        } else {
            let record = NSMenuItem(title: "⏺ Record Meeting", action: #selector(startMicRecording), keyEquivalent: "r")
            record.keyEquivalentModifierMask = [.command, .shift]
            menu.addItem(record)
        }

        menu.addItem(NSMenuItem.separator())

        let openFolder = NSMenuItem(title: "Open Today's Folder", action: #selector(openTodayFolder), keyEquivalent: "o")
        menu.addItem(openFolder)

        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    func menuWillOpen(_ menu: NSMenu) {
        buildMenu(menu)
    }

    @objc func startMicRecording() {
        if isRecording {
            stopRecording()
            return
        }

        let timestamp = {
            let f = DateFormatter()
            f.dateFormat = "HHmmss"
            return f.string(from: Date())
        }()

        let filename = "recording_\(timestamp).m4a"
        currentFile = vaultInbox.appendingPathComponent(filename)

        // Ensure day folder exists
        try? FileManager.default.createDirectory(at: vaultInbox, withIntermediateDirectories: true)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            recorder = try AVAudioRecorder(url: currentFile!, settings: settings)
            recorder?.record()
            isRecording = true
            startTime = Date()
            updateMenuBarIcon(recording: true)

            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self = self, let start = self.startTime else { return }
                let elapsed = Int(Date().timeIntervalSince(start))
                let min = elapsed / 60
                let sec = elapsed % 60
                DispatchQueue.main.async {
                    self.statusItem.button?.title = String(format: "🔴 %d:%02d", min, sec)
                }
            }

            notify(title: "Recording Started", body: filename)
        } catch {
            notify(title: "Recording Failed", body: error.localizedDescription)
        }
    }

    @objc func stopRecording() {
        guard isRecording else { return }

        recorder?.stop()
        recorder = nil
        isRecording = false
        timer?.invalidate()
        timer = nil
        updateMenuBarIcon(recording: false)

        if let file = currentFile {
            let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
            let sizeMB = String(format: "%.1f MB", Double(size) / 1_000_000)
            notify(title: "Recording Saved", body: "\(file.lastPathComponent) (\(sizeMB))")
        }
    }

    @objc func openTodayFolder() {
        try? FileManager.default.createDirectory(at: vaultInbox, withIntermediateDirectories: true)
        NSWorkspace.shared.open(vaultInbox)
    }

    func notify(title: String, body: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "display notification \"\(body)\" with title \"\(title)\""]
        try? process.run()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

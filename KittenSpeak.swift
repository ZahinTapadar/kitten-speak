// KittenSpeak: menu-bar app that reads selected text aloud with KittenTTS.
// Entry point: right-click selected text → Services → "Speak with KittenSpeak" (Info.plist NSServices).
import AppKit
import AVFoundation

final class App: NSObject, NSApplicationDelegate, AVAudioPlayerDelegate {
    let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let defaults = UserDefaults.standard
    var engine: Process?
    var engineIn: FileHandle?
    var engineBusy = false
    var buffer = Data()
    var reqID = 0
    var queue: [URL] = []
    var player: AVAudioPlayer?
    var builtin: [String: [String]] = [:]

    var voice: String {
        get { defaults.string(forKey: "voice") ?? "Vincent" }
        set { defaults.set(newValue, forKey: "voice"); rebuildMenu() }
    }
    var speed: Double {
        get { defaults.object(forKey: "speed") as? Double ?? 1.0 }
        set { defaults.set(newValue, forKey: "speed"); rebuildMenu() }
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        setIcon(busy: false)
        startEngine()
        rebuildMenu()
    }

    func applicationWillTerminate(_ n: Notification) { engine?.terminate() }

    // MARK: Service (right-click → Services)
    @objc func speak(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>?) {
        guard let text = pboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            error?.pointee = "No text selected." as NSString
            return
        }
        say(text)
    }

    // MARK: Engine
    func startEngine() {
        let py = Bundle.main.object(forInfoDictionaryKey: "KSPython") as? String ?? "python3"
        guard let script = Bundle.main.path(forResource: "engine", ofType: "py") else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: py)
        p.arguments = [script]
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        FileManager.default.createFile(atPath: "/tmp/kittenspeak.log", contents: nil)
        p.standardError = FileHandle(forWritingAtPath: "/tmp/kittenspeak.log") ?? FileHandle.nullDevice
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            DispatchQueue.main.async { self?.receive(d) }
        }
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async { if self?.engine === proc { self?.engine = nil; self?.engineBusy = false; self?.setIcon(busy: false) } }
        }
        do { try p.run() } catch { alert("Could not start the TTS engine", "\(error.localizedDescription)\nPython: \(py)"); return }
        engine = p
        engineIn = inPipe.fileHandleForWriting
        buffer = Data()
        engineBusy = false
        send(["id": 0, "cmd": "voices"])
    }

    func send(_ obj: [String: Any]) {
        if engine == nil { startEngine() }
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        engineIn?.write(data + Data("\n".utf8))
    }

    func receive(_ data: Data) {
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            guard let msg = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { continue }
            let id = msg["id"] as? Int ?? -1
            if id == 0, let b = msg["builtin"] as? [String: [String]] {
                builtin = b
                rebuildMenu()
            } else if id == reqID, let path = msg["chunk"] as? String {
                queue.append(URL(fileURLWithPath: path))
                if player?.isPlaying != true { playNext() }
            } else if id == reqID, msg["done"] != nil {
                engineBusy = false
                if player?.isPlaying != true { setIcon(busy: false) }
            } else if let err = msg["error"] as? String {
                engineBusy = false
                setIcon(busy: false)
                if id == reqID { alert("KittenSpeak couldn't speak", err) }
            }
        }
    }

    func say(_ text: String) {
        silence()
        reqID += 1  // any new line also tells the engine to drop the old request at its next sentence
        engineBusy = true
        setIcon(busy: true)
        send(["id": reqID, "text": text, "voice": voice, "speed": speed])
    }

    func silence() {
        player?.stop()
        player = nil
        queue.removeAll()
    }

    @objc func stop() {
        silence()
        if engineBusy { reqID += 1; engineBusy = false; send(["cmd": "stop"]) }
        setIcon(busy: false)
    }

    // MARK: Playback
    func playNext() {
        guard !queue.isEmpty else { player = nil; if !engineBusy { setIcon(busy: false) }; return }
        let url = queue.removeFirst()
        player = try? AVAudioPlayer(contentsOf: url)
        player?.delegate = self
        player?.play()
        try? FileManager.default.removeItem(at: url)  // AVAudioPlayer has the data loaded already
    }

    func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully: Bool) { playNext() }

    // MARK: Menu
    func setIcon(busy: Bool) {
        status.button?.image = NSImage(systemSymbolName: busy ? "waveform.circle.fill" : "waveform", accessibilityDescription: "KittenSpeak")
    }

    func item(_ title: String, _ action: Selector?, key: String = "", on: Bool = false, rep: Any? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        i.state = on ? .on : .off
        i.representedObject = rep
        return i
    }

    func rebuildMenu() {
        let m = NSMenu()
        m.addItem(item("Speak Clipboard", #selector(speakClipboard)))
        m.addItem(item("Stop", #selector(stop), key: "."))
        m.addItem(.separator())

        let voices = NSMenu()
        for v in builtin["en"] ?? [] { voices.addItem(item(v, #selector(pickVoice(_:)), on: v == voice, rep: v)) }
        let langs = builtin.keys.filter { $0 != "en" }.sorted()
        if !langs.isEmpty {
            let other = NSMenu()
            for l in langs {
                let sub = NSMenu()
                for v in builtin[l] ?? [] { sub.addItem(item(v, #selector(pickVoice(_:)), on: v == voice, rep: v)) }
                let li = NSMenuItem(title: Locale.current.localizedString(forLanguageCode: l) ?? l, action: nil, keyEquivalent: "")
                li.submenu = sub
                other.addItem(li)
            }
            let oi = NSMenuItem(title: "Other Languages", action: nil, keyEquivalent: "")
            oi.submenu = other
            voices.addItem(oi)
        }
        let vi = NSMenuItem(title: "Voice", action: nil, keyEquivalent: "")
        vi.submenu = voices
        m.addItem(vi)

        let speeds = NSMenu()
        for s in [0.8, 1.0, 1.2, 1.5, 2.0] { speeds.addItem(item("\(s)×", #selector(pickSpeed(_:)), on: s == speed, rep: s)) }
        let si = NSMenuItem(title: "Speed", action: nil, keyEquivalent: "")
        si.submenu = speeds
        m.addItem(si)
        m.addItem(.separator())
        m.addItem(item("Quit KittenSpeak", #selector(NSApplication.terminate(_:)), key: "q"))
        m.items.last?.target = NSApp
        status.menu = m
    }

    @objc func pickVoice(_ s: NSMenuItem) { voice = s.representedObject as? String ?? voice }
    @objc func pickSpeed(_ s: NSMenuItem) { speed = s.representedObject as? Double ?? 1.0 }
    @objc func speakClipboard() { if let t = NSPasteboard.general.string(forType: .string), !t.isEmpty { say(t) } }
    func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = String(text.prefix(600))
        a.runModal()
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

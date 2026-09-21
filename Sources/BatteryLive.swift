import Cocoa
import WebKit

let resDir = Bundle.main.resourcePath ?? (CommandLine.arguments[0] as NSString).deletingLastPathComponent

@discardableResult
func sh(_ path: String, _ args: [String] = []) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/zsh")
    p.arguments = [path] + args
    let out = Pipe()
    p.standardOutput = out
    p.standardError = Pipe()
    do { try p.run() } catch { return "" }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler {
    var statusItem: NSStatusItem!
    var timer: Timer?
    var popover: NSPopover!
    var webView: WKWebView!

    // מדדים
    var soc = 0, watts = 0, health = 0, cycles = 0, cores = 10, topcpu = 0, booted = 0, toppid = 0
    var charging = false
    var load = "0.0", topname = "-"
    var lastSoc = -1

    // ניטור אוטומטי — זמני התרעה אחרונים (throttle)
    var lastAlert: [String: Date] = [:]

    let protectedNames = ["WindowServer","kernel_task","launchd","logind","loginwindow",
        "mds","mds_stores","mdbulkimport","mdworker","mdsync","spotlight","Spotlight",
        "coreaudiod","Dock","Finder","SystemUIServer","WindowManager","Control","controlcenter",
        "ControlCenter","NotificationCenter","BatteryLive","backboardd","cfprefsd","distnoted",
        "bluetoothd","powerd","hidd","opendirectoryd","syslogd","configd"]

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🔋…"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        // popover עם WebView לגרף
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(self, name: "act")
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 440, height: 760), configuration: cfg)
        webView.setValue(false, forKey: "drawsBackground")
        let vc = NSViewController()
        vc.view = webView
        popover = NSPopover()
        popover.contentViewController = vc
        popover.contentSize = NSSize(width: 440, height: 760)
        popover.behavior = .transient

        refresh()
        regen(reload: false)   // מכין את הגרף מראש כדי שהפתיחה תהיה מיידית
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        // רענון הגרף ברקע כל 20 שניות
        Timer.scheduledTimer(withTimeInterval: 20.0, repeats: true) { [weak self] _ in
            guard let s = self else { return }
            s.regen(reload: s.popover.isShown)
        }
        // בדיקת עדכונים: בהפעלה + כל 6 שעות
        checkForUpdate()
        Timer.scheduledTimer(withTimeInterval: 21600, repeats: true) { [weak self] _ in self?.checkForUpdate() }
    }

    // ── עדכון אוטומטי מ-GitHub ──
    let updateManifestURL = "https://raw.githubusercontent.com/raniop/BatteryLive/main/latest.json"
    var availableUpdate: (version: String, url: String)?

    func currentVersion() -> String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }
    func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let xi = i < x.count ? x[i] : 0, yi = i < y.count ? y[i] : 0
            if xi != yi { return xi > yi }
        }
        return false
    }

    func checkForUpdate(manual: Bool = false) {
        guard let url = URL(string: updateManifestURL) else { return }
        var req = URLRequest(url: url); req.cachePolicy = .reloadIgnoringLocalCacheData; req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let s = self else { return }
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ver = obj["version"] as? String,
                  let purl = obj["url"] as? String else {
                if manual { DispatchQueue.main.async { s.notify("לא ניתן לבדוק עדכונים כרגע") } }
                return
            }
            DispatchQueue.main.async {
                if s.isNewer(ver, than: s.currentVersion()) {
                    s.availableUpdate = (ver, purl)
                    s.fire("update", "עדכון זמין ⬆︎", "גרסה \(ver) זמינה. לחץ על הווידג'ט → \"עדכן לגרסה \(ver)\".")
                } else {
                    s.availableUpdate = nil
                    if manual { s.notify("אתה מעודכן (גרסה \(s.currentVersion())) ✓") }
                }
            }
        }.resume()
    }
    @objc func checkForUpdateManual() { checkForUpdate(manual: true) }

    @objc func installUpdate() {
        guard let up = availableUpdate, let url = URL(string: up.url) else { return }
        notify("מוריד עדכון \(up.version)…")
        URLSession.shared.downloadTask(with: url) { [weak self] tmp, _, _ in
            guard let s = self else { return }
            guard let tmp = tmp else { DispatchQueue.main.async { s.notify("ההורדה נכשלה") }; return }
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent("BatteryLive-Update.pkg")
            try? FileManager.default.removeItem(at: dest)
            do { try FileManager.default.moveItem(at: tmp, to: dest) } catch { DispatchQueue.main.async { s.notify("שגיאה בהורדה") }; return }
            DispatchQueue.main.async { NSWorkspace.shared.open(dest) }   // פותח את המתקין המאושר
        }.resume()
    }

    var chartFile = ""

    func genChart() -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["python3", "\(resDir)/chart.py", "--noopen"]
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
        return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func regen(reload: Bool) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let s = self else { return }
            let f = s.genChart()
            DispatchQueue.main.async {
                if !f.isEmpty { s.chartFile = f }
                if reload && s.popover.isShown { s.reloadChart() }
            }
        }
    }

    // ── קריאת מדדים ──
    func readStats() {
        let line = sh("\(resDir)/stats.sh")
        let f = line.components(separatedBy: "|")
        guard f.count >= 10 else { return }
        soc      = Int(f[0]) ?? soc
        watts    = Int(f[1]) ?? watts
        charging = f[2] == "1"
        health   = Int(f[3]) ?? health
        cycles   = Int(f[4]) ?? cycles
        load     = f[5]
        cores    = Int(f[6]) ?? cores
        topcpu   = Int(f[7]) ?? topcpu
        topname  = f[8]
        booted   = Int(f[9]) ?? booted
        if f.count >= 11 { toppid = Int(f[10]) ?? toppid }
    }

    func refresh() {
        readStats()
        if let btn = statusItem.button {
            btn.image = batteryImage(soc: soc, charging: charging)
            btn.imagePosition = .imageLeading
            let flame = (!charging && watts >= 25) ? " 🔥" : ""
            btn.title = charging ? " \(soc)%" : " \(soc)% · \(watts)W\(flame)"
        }
        autoMonitor()
        lastSoc = soc
    }

    // אייקון סוללה דינמי (מתמלא/מתרוקן לפי האחוזים), בסגנון אפל
    func batteryImage(soc: Int, charging: Bool) -> NSImage {
        let w: CGFloat = 23.5, h: CGFloat = 14, cap: CGFloat = 2.0   // מדויק לגודל אפל: ~25.5x14
        let over: CGFloat = charging ? 3.0 : 0.0
        let cw = w + cap + 1
        let chh = h + over * 2
        let oy = over
        let img = NSImage(size: NSSize(width: cw, height: chh))
        img.lockFocus()
        let body = NSRect(x: 0.5, y: oy + 0.5, width: w - 1, height: h - 1)
        let path = NSBezierPath(roundedRect: body, xRadius: 3, yRadius: 3)
        path.lineWidth = 1

        var template = false
        let color: NSColor
        if charging { color = NSColor.systemGreen }
        else if soc <= 20 { color = NSColor.systemRed }
        else { color = NSColor.black; template = true }   // template → צבע הבר האוטומטי

        color.setStroke(); path.stroke()
        // הבליטה בצד
        let nub = NSBezierPath(roundedRect: NSRect(x: w, y: oy + h/2 - 2.2, width: cap, height: 4.4), xRadius: 1, yRadius: 1)
        color.setFill(); nub.fill()
        // המילוי לפי אחוזים
        let inset: CGFloat = 2
        let maxW = (w - 1) - inset * 2
        let fw = maxW * CGFloat(max(0, min(100, soc))) / 100.0
        if fw > 0.5 {
            let fillRect = NSRect(x: 0.5 + inset, y: oy + 0.5 + inset, width: fw, height: (h - 1) - inset * 2)
            color.setFill(); NSBezierPath(roundedRect: fillRect, xRadius: 1.2, yRadius: 1.2).fill()
        }
        // ברק בגודל של אפל כשבטעינה (על כל גובה הסוללה)
        if charging {
            let cx = w/2 + 0.5, cy = chh/2
            let s = (chh - 1) / 2          // חצי גובה הברק
            let b = NSBezierPath()
            b.move(to: NSPoint(x: cx + 2.4, y: cy + s))
            b.line(to: NSPoint(x: cx - 3.8, y: cy - 0.5))
            b.line(to: NSPoint(x: cx - 0.4, y: cy - 0.5))
            b.line(to: NSPoint(x: cx - 2.4, y: cy - s))
            b.line(to: NSPoint(x: cx + 4.0, y: cy + 0.9))
            b.line(to: NSPoint(x: cx + 0.6, y: cy + 0.9))
            b.close()
            // חיתוך הברק מתוך המילוי (מראה "חור" לבן כמו אפל)
            NSColor.white.setFill(); b.fill()
        }
        img.unlockFocus()
        img.isTemplate = template
        return img
    }

    var prevWatts = 0

    // ── ניטור אוטומטי: מזהה בעיות, מתריע, ומטפל ──
    func autoMonitor() {
        // 1) קפיצה פתאומית בצריכה (ריאקציה מהירה)
        if !charging && watts >= 30 && watts - prevWatts >= 12 {
            handleSpike("קפיצה פתאומית בצריכה ⚡️", "עלה ל-\(watts)W")
        }
        // 2) צריכה גבוהה מתמשכת
        else if !charging && watts >= 30 {
            handleSpike("המחשב מתחמם 🔥", "צריכה גבוהה \(watts)W")
        }
        prevWatts = watts

        // 3) ירידה חדה בסוללה (חוסר כיול / עומס)
        if lastSoc >= 0 && !charging && (lastSoc - soc) >= 12 {
            fire("crash", "ירידה חדה בסוללה ⚠️", "צנח מ-\(lastSoc)% ל-\(soc)% בבת אחת. סימן לחוסר כיול — כדאי לאתחל ולהטעין ל-100%.")
        }
        // 4) סוללה נמוכה
        if !charging && soc <= 10 && soc > 0 {
            fire("low", "סוללה נמוכה 🪫", "נשארו \(soc)% — כדאי לחבר מטען.")
        }
    }

    // מטפל בקפיצת צריכה: אם יש סימולטורים עודפים — סוגר אוטומטית; אחרת מתריע עם האשם
    func handleSpike(_ title: String, _ prefix: String) {
        if booted > 1 {
            let closed = Int(sh("\(resDir)/closesims.sh")) ?? 0
            if closed > 0 {
                fire("heat", title, "\(prefix). זיהיתי \(closed) סימולטורים מיותרים וסגרתי אותם אוטומטית 🔥")
                refresh()
                return
            }
        }
        let isProtected = protectedNames.contains { topname.lowercased().contains($0.lowercased()) }
        if isProtected {
            fire("heat", title, "\(prefix). הגורם: \(topname) (רכיב מערכת). נסה לסגור סימולטורים/אפליקציות כבדות מהווידג'ט.")
        } else {
            fire("heat", title, "\(prefix). הגורם: \(topname) (\(topcpu)%). פתח את הווידג'ט → \"עצור מעמיס\" כדי לעצור.")
        }
    }

    // מתריע פעם ב-5 דקות לכל סוג
    func fire(_ key: String, _ title: String, _ text: String) {
        let now = Date()
        if let last = lastAlert[key], now.timeIntervalSince(last) < 300 { return }
        lastAlert[key] = now
        let note = NSUserNotification()
        note.title = title
        note.informativeText = text
        note.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(note)
    }

    // ── קליק על האייקון ──
    @objc func statusClicked() {
        let ev = NSApp.currentEvent
        if ev?.type == .rightMouseUp || (ev?.modifierFlags.contains(.control) ?? false) {
            showMenu()
        } else {
            togglePopover()
        }
    }

    @objc func togglePopover() {
        if popover.isShown { popover.performClose(nil); return }
        // פתיחה מיידית מהקובץ המוכן; אם אין — מייצר עכשיו
        var f = chartFile
        if f.isEmpty || !FileManager.default.fileExists(atPath: f) {
            f = genChart(); if !f.isEmpty { chartFile = f }
        }
        if !f.isEmpty {
            let url = URL(fileURLWithPath: f)
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        if let btn = statusItem.button {
            popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
        regen(reload: true)   // מרענן את התוכן ברקע אחרי שנפתח
    }

    func reloadChart() {
        guard !chartFile.isEmpty else { return }
        let url = URL(fileURLWithPath: chartFile)
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    // ── גשר מה-HTML לפעולות נייטיב ──
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let cmd = message.body as? String else { return }
        switch cmd {
        case "kill":    killTop()
        case "sims":    closeSims(); refresh(); regen(reload: true)
        case "refresh": refresh(); regen(reload: true)
        case "clean":   doClean()
        default: break
        }
    }

    // ── ניקוי מלא + סיכום (מובנה, בלי אפליקציה נפרדת) ──
    @objc func doClean() {
        readStats()
        let closed = Int(sh("\(resDir)/closesims.sh")) ?? 0
        usleep(400_000)
        readStats()
        let simTxt: String
        if closed > 0 { simTxt = "נסגרו \(closed) סימולטורים מיותרים" }
        else { simTxt = booted > 0 ? "סימולטור אחד נשאר פתוח" : "אין סימולטורים מיותרים" }
        let a = NSAlert()
        a.messageText = "🔋 ניקוי הושלם"
        a.informativeText = "בריאות סוללה: \(health)%  (\(cycles) מחזורים)\n\(simTxt)\nצריכת חשמל כרגע: \(watts)W\n\nטיפ: אתחל את המחשב פעם בשבוע לכיול הסוללה."
        a.addButton(withTitle: "סיימתי")
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
        refresh(); regen(reload: true)
    }

    // ── תפריט (קליק ימני) ──
    func showMenu() {
        let m = NSMenu()
        if let up = availableUpdate {
            let it = actionItem("⬆︎ עדכן לגרסה \(up.version)", #selector(installUpdate))
            it.attributedTitle = rtl("⬆︎ עדכן לגרסה \(up.version)", bold: true, color: .systemGreen)
            m.addItem(it)
            m.addItem(.separator())
        }
        m.addItem(actionItem("📊 הצג גרף סוללה", #selector(togglePopover)))
        m.addItem(actionItem("⚡︎ עצור את מה שהכי מעמיס (\(topname))", #selector(killTop)))
        m.addItem(actionItem("סגור סימולטורים מיותרים", #selector(closeSims)))
        m.addItem(actionItem("ניקוי מלא", #selector(doClean)))
        m.addItem(actionItem("רענן עכשיו", #selector(manualRefresh)))
        m.addItem(actionItem("בדוק עדכונים", #selector(checkForUpdateManual)))
        m.addItem(.separator())
        m.addItem(actionItem("יציאה", #selector(quit)))
        statusItem.menu = m
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    func rtl(_ t: String, size: CGFloat = 13, bold: Bool = false, color: NSColor = .labelColor) -> NSAttributedString {
        let ps = NSMutableParagraphStyle()
        ps.alignment = .right
        ps.baseWritingDirection = .rightToLeft
        let font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        return NSAttributedString(string: t, attributes: [.paragraphStyle: ps, .font: font, .foregroundColor: color])
    }
    func actionItem(_ t: String, _ sel: Selector) -> NSMenuItem {
        let it = NSMenuItem(title: t, action: sel, keyEquivalent: "")
        it.target = self
        it.attributedTitle = rtl(t)
        return it
    }

    // ── פעולות ──
    func notify(_ text: String) {
        let note = NSUserNotification()
        note.title = "Battery Live"
        note.informativeText = text
        NSUserNotificationCenter.default.deliver(note)
    }

    @objc func killTop() {
        readStats()
        let name = topname, pid = toppid
        let isProtected = protectedNames.contains { name.lowercased().contains($0.lowercased()) }
        if isProtected {
            let a = NSAlert()
            a.messageText = "אי אפשר לעצור את \(name)"
            a.informativeText = "זהו רכיב חיוני של macOS. עצירה עלולה לנתק את המסך או פשוט לא תעבוד (המערכת תפעיל אותו מחדש מיד).\n\nהכפתור מיועד לאפליקציות רגילות (Xcode, סימולטורים, אפליקציות תקועות)."
            a.alertStyle = .warning
            a.addButton(withTitle: "הבנתי")
            NSApp.activate(ignoringOtherApps: true)
            a.runModal(); return
        }
        let c = NSAlert()
        c.messageText = "לעצור את \(name)?"
        c.informativeText = "התהליך צורך \(topcpu)% מהמעבד. עצירה תסגור אותו מיד (עבודה שלא נשמרה עלולה ללכת לאיבוד)."
        c.alertStyle = .warning
        c.addButton(withTitle: "עצור")
        c.addButton(withTitle: "ביטול")
        NSApp.activate(ignoringOtherApps: true)
        guard c.runModal() == .alertFirstButtonReturn else { return }
        killPid(pid)
        notify("עצרתי את \(name) ✓")
        refresh(); regen(reload: true)
    }

    func killPid(_ pid: Int) {
        guard pid > 0 else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/kill")
        p.arguments = ["-TERM", "\(pid)"]
        try? p.run(); p.waitUntilExit()
    }

    @objc func closeSims() {
        let closed = sh("\(resDir)/closesims.sh")
        let n = Int(closed) ?? 0
        notify(n > 0 ? "נסגרו \(n) סימולטורים מיותרים 🔥" : "אין סימולטורים מיותרים לסגור ✓")
        refresh()
    }

    @objc func openReport() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/BatteryRescue.app"))
    }

    @objc func manualRefresh() { refresh() }
    @objc func quit() { NSApplication.shared.terminate(nil) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

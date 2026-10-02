import Cocoa
import WebKit
import ServiceManagement

// ════════════════════════════════════════════════════════════
//  עזרי מערכת (native — ללא python / סקריפטים חיצוניים)
// ════════════════════════════════════════════════════════════
func runCmd(_ path: String, _ args: [String]) -> String {
    guard FileManager.default.isExecutableFile(atPath: path) else { return "" }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
    do { try p.run() } catch { return "" }
    let d = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(data: d, encoding: .utf8) ?? ""
}

func rx(_ pattern: String, _ s: String, _ group: Int = 1) -> String? {
    guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
    let ns = s as NSString
    guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
          m.range(at: group).location != NSNotFound else { return nil }
    return ns.substring(with: m.range(at: group))
}
func rxInt(_ pattern: String, _ s: String) -> Int? { rx(pattern, s).flatMap { Int($0) } }

func f1(_ v: Double) -> String { String(format: "%.1f", v) }

func devToolsPresent() -> Bool {
    FileManager.default.fileExists(atPath: "/Applications/Xcode.app") ||
    FileManager.default.fileExists(atPath: "/Library/Developer/CommandLineTools")
}

func fmtMin(_ mins: Int) -> String {
    let t = max(0, mins); let h = t / 60, m = t % 60
    if h == 0 { return m == 0 ? "פחות מדקה" : "\(m) דקות" }
    let hw = h == 1 ? "שעה" : "\(h) שעות"
    return m == 0 ? hw : "\(hw) ו-\(m) דקות"
}

// ── נתוני סוללה ──
struct BattInfo { var soc = 0, watts = 0, health = 0, cycles = 0; var charging = false; var remMin: Int? }
func batteryData() -> BattInfo {
    var b = BattInfo()
    let ior = runCmd("/usr/sbin/ioreg", ["-rn", "AppleSmartBattery"])
    let design = rxInt("\"DesignCapacity\"=(\\d+)", ior) ?? 0
    let fullc  = rxInt("\"FullChargeCapacity\"=(\\d+)", ior) ?? 0
    b.cycles = rxInt("\"CycleCount\"\\s*=\\s*(\\d+)", ior) ?? 0
    let volt = rxInt("\"Voltage\"\\s*=\\s*(\\d+)", ior) ?? 0
    let ampU = UInt64(rx("\"Amperage\"\\s*=\\s*(\\d+)", ior) ?? "0") ?? 0
    let amp = Int64(bitPattern: ampU)
    b.watts = Int((abs(Double(amp)) * Double(volt) / 1_000_000).rounded())
    b.health = design > 0 ? Int((Double(fullc) / Double(design) * 100).rounded()) : 0
    let batt = runCmd("/usr/bin/pmset", ["-g", "batt"])
    b.soc = rxInt("(\\d+)%", batt) ?? 0
    b.charging = batt.contains("AC Power")
    // זמן שנותר
    if let re = try? NSRegularExpression(pattern: "(\\d+):(\\d\\d)\\s+remaining") {
        let ns = batt as NSString
        if let m = re.firstMatch(in: batt, range: NSRange(location: 0, length: ns.length)) {
            let h = Int(ns.substring(with: m.range(at: 1))) ?? 0
            let mm = Int(ns.substring(with: m.range(at: 2))) ?? 0
            b.remMin = h * 60 + mm
        }
    }
    if b.remMin == nil {
        let key = b.charging ? "AvgTimeToFull" : "AvgTimeToEmpty"
        if let v = rxInt("\"\(key)\"\\s*=\\s*(\\d+)", ior), v > 0, v < 1440 { b.remMin = v }
    }
    return b
}

func loadAndCores() -> (String, Int) {
    var l = [Double](repeating: 0, count: 3)
    getloadavg(&l, 3)
    return (String(format: "%.2f", l[0]), ProcessInfo.processInfo.activeProcessorCount)
}

func splitFirst(_ s: String) -> (String, String)? {
    let t = s.trimmingCharacters(in: .whitespaces)
    guard let r = t.rangeOfCharacter(from: .whitespaces) else { return nil }
    return (String(t[..<r.lowerBound]), String(t[r.upperBound...]).trimmingCharacters(in: .whitespaces))
}

// התהליך הכי מעמיס (pid, cpu, שם)
func topProc() -> (name: String, cpu: Int, pid: Int) {
    let out = runCmd("/bin/ps", ["-Ao", "pid,pcpu,comm", "-r"])
    let lines = out.split(separator: "\n").map(String.init)
    guard lines.count > 1 else { return ("-", 0, 0) }
    let t = lines[1].trimmingCharacters(in: .whitespaces)
    guard let (pidS, rest) = splitFirst(t), let (cpuS, comm) = splitFirst(rest) else { return ("-", 0, 0) }
    let name = (comm as NSString).lastPathComponent
    return (name, Int(Double(cpuS) ?? 0), Int(pidS) ?? 0)
}

func groupName(_ comm: String) -> (String, String)? {
    let low = comm.lowercased()
    let base = (comm as NSString).lastPathComponent
    if low.contains("claude") { return ("Claude", "message") }
    if low.contains("swift") || low.contains("xcode") || low.contains("swbbuild") || low.contains("sourcekit") { return ("Xcode", "code") }
    for k in ["simulator", "backboardd", "springboard", "simmetal", "coresimulator"] where low.contains(k) { return ("Simulator", "phone") }
    if base == "WindowServer" { return ("WindowServer", "window") }
    if low.contains("chrome") || low.contains("safari") || low.contains("firefox") { return ("דפדפן", "world") }
    if low.contains("whatsapp") { return ("WhatsApp", "message") }
    if low.contains("spotlight") || low.contains("mds") || low.contains("metadata") { return ("Spotlight", "search") }
    if low.contains("coreaudio") { return ("שמע", "volume") }
    if base == "kernel_task" || base == "launchd" { return nil }
    return (base, "cpu")
}

func groupedApps() -> [(name: String, icon: String, cpu: Double)] {
    let out = runCmd("/bin/ps", ["-Ao", "pcpu,comm", "-r"])
    var dict: [String: (Double, String)] = [:]
    for line in out.split(separator: "\n").dropFirst() {
        guard let (cpuS, comm) = splitFirst(String(line)), let cpu = Double(cpuS),
              let (name, icon) = groupName(comm) else { continue }
        if dict[name] == nil { dict[name] = (0, icon) }
        dict[name]!.0 += cpu
    }
    return dict.map { (name: $0.key, icon: $0.value.1, cpu: $0.value.0) }
        .sorted { $0.cpu > $1.cpu }.prefix(5).map { $0 }
}

// היסטוריית סוללה מ-pmset log
func batteryHistory() -> [(Date, String, Int)] {
    let log = runCmd("/usr/bin/pmset", ["-g", "log"])
    guard let re = try? NSRegularExpression(
        pattern: "^(\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}).*?Using (AC|Batt)\\s*\\(Charge:?\\s*(\\d+)",
        options: [.anchorsMatchLines]) else { return [] }
    let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let ns = log as NSString
    var rows: [(Date, String, Int)] = []
    re.enumerateMatches(in: log, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
        guard let m = m, let d = df.date(from: ns.substring(with: m.range(at: 1))) else { return }
        rows.append((d, ns.substring(with: m.range(at: 2)), Int(ns.substring(with: m.range(at: 3))) ?? 0))
    }
    if let last = rows.last?.0 {
        let cutoff = last.addingTimeInterval(-4 * 86400)
        rows = rows.filter { $0.0 >= cutoff }
    }
    var dedup: [(Date, String, Int)] = []
    for r in rows where dedup.isEmpty || dedup.last!.2 != r.2 || dedup.last!.1 != r.1 { dedup.append(r) }
    return dedup
}

func bootedSimIDs() -> [String] {
    guard devToolsPresent() else { return [] }
    let out = runCmd("/usr/bin/xcrun", ["simctl", "list", "devices", "booted"])
    guard let re = try? NSRegularExpression(pattern: "([0-9A-F]{8}-[0-9A-F-]{27})") else { return [] }
    let ns = out as NSString
    return re.matches(in: out, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
}
func closeExtraSims() -> Int {
    let ids = bootedSimIDs()
    guard ids.count > 1 else { return 0 }
    var closed = 0
    for id in ids.dropFirst() { _ = runCmd("/usr/bin/xcrun", ["simctl", "shutdown", id]); closed += 1 }
    return closed
}

// ════════════════════════════════════════════════════════════
//  אייקוני SVG מוטמעים (בסגנון Tabler)
// ════════════════════════════════════════════════════════════
let ICONS: [String: (String, Bool)] = [
 "battery": ("<rect x=\"3\" y=\"8\" width=\"15\" height=\"8\" rx=\"2\"/><path d=\"M20 11v2\"/>", false),
 "bolt": ("<path d=\"M13 3L5 13h6l-1 8 8-10h-6z\"/>", true),
 "cpu": ("<rect x=\"7\" y=\"7\" width=\"10\" height=\"10\" rx=\"1\"/><path d=\"M9 3v2M12 3v2M15 3v2M9 19v2M12 19v2M15 19v2M3 9h2M3 12h2M3 15h2M19 9h2M19 12h2M19 15h2\"/>", false),
 "refresh": ("<path d=\"M20 11a8 8 0 1 0-2.3 5.6\"/><path d=\"M20 5v6h-6\"/>", false),
 "file": ("<path d=\"M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z\"/><path d=\"M14 3v5h5M9 13h6M9 17h6\"/>", false),
 "shield": ("<path d=\"M12 3l7 3v6c0 5-3.5 8-7 9-3.5-1-7-4-7-9V6z\"/><path d=\"M9 12l2 2 4-4\"/>", false),
 "phone": ("<rect x=\"7\" y=\"3\" width=\"10\" height=\"18\" rx=\"2\"/><path d=\"M11 18h2\"/>", false),
 "message": ("<path d=\"M8 19l-4 3V6a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H8z\"/>", false),
 "code": ("<path d=\"M8 8l-4 4 4 4M16 8l4 4-4 4\"/>", false),
 "window": ("<rect x=\"3\" y=\"5\" width=\"18\" height=\"14\" rx=\"2\"/><path d=\"M3 9h18\"/>", false),
 "world": ("<circle cx=\"12\" cy=\"12\" r=\"9\"/><path d=\"M3 12h18M12 3c3 3 3 15 0 18M12 3c-3 3-3 15 0 18\"/>", false),
 "search": ("<circle cx=\"10.5\" cy=\"10.5\" r=\"6\"/><path d=\"M20 20l-5-5\"/>", false),
 "volume": ("<path d=\"M6 9v6h4l5 4V5l-5 4z\"/>", false),
 "clean": ("<path d=\"M12 3l1.4 4.1L17.5 8l-4.1 1.4L12 13l-1.4-3.6L6.5 8l4.1-0.9z\"/><path d=\"M6 20l3-3M18 20l-3-3\"/>", false),
 "heart": ("<path d=\"M12 20l-7.5-7.3a4.3 4.3 0 0 1 6.1-6L12 7.3l1.4-0.6a4.3 4.3 0 0 1 6.1 6z\"/>", false),
 "down": ("<path d=\"M3 7l6 6 4-4 8 8\"/><path d=\"M14 17h7v-7\"/>", false),
 "clock": ("<circle cx=\"12\" cy=\"12\" r=\"9\"/><path d=\"M12 7v5l3 2\"/>", false),
]
func ic(_ name: String, _ color: String = "currentColor", _ size: Int = 16) -> String {
    let (inner, filled) = ICONS[name] ?? ICONS["cpu"]!
    let s = filled ? "fill=\"\(color)\" stroke=\"none\""
                   : "fill=\"none\" stroke=\"\(color)\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\""
    return "<svg width=\"\(size)\" height=\"\(size)\" viewBox=\"0 0 24 24\" \(s) style=\"flex:none;vertical-align:middle;\">\(inner)</svg>"
}

// ════════════════════════════════════════════════════════════
//  בניית ה-HTML של החלון (native port)
// ════════════════════════════════════════════════════════════
func buildChartHTML() -> String {
    let b = batteryData()
    let (loadS, cores) = loadAndCores()
    let apps = groupedApps()
    var rows = batteryHistory()
    let curSource = b.charging ? "AC" : "Batt"
    if b.soc > 0 { rows.append((Date(), curSource, b.soc)) }

    var lastFull: Date? = nil
    for r in rows where r.2 >= 100 { lastFull = r.0 }

    var sessionSince: Date? = nil
    if rows.count >= 2 {
        var startI = 0
        var i = rows.count - 1
        while i >= 0 { if rows[i].1 != curSource { startI = i; sessionSince = rows[i].0; break }; i -= 1 }
        if sessionSince != nil { rows = Array(rows[startI...]) }
    }

    // גיאומטריית הגרף
    let W = 380.0, H = 150.0, ML = 30.0, MR = 26.0, MT = 12.0, MB = 30.0
    let PW = W - ML - MR, PH = H - MT - MB
    func svgInner() -> String {
        if rows.count < 2 { return "<text x=\"190\" y=\"70\" text-anchor=\"middle\" fill=\"#888\" font-size=\"13\">אוסף נתונים...</text>" }
        let t0 = rows.first!.0.timeIntervalSince1970, t1 = rows.last!.0.timeIntervalSince1970
        let span = max(1, t1 - t0)
        func X(_ d: Date) -> Double { ML + (d.timeIntervalSince1970 - t0) / span * PW }
        func Y(_ c: Int) -> Double { MT + (100 - Double(c)) / 100 * PH }
        var p = [String]()
        for pct in [0, 50, 100] {
            let y = Y(pct)
            p.append("<line x1=\"\(ML)\" y1=\"\(f1(y))\" x2=\"\(ML+PW)\" y2=\"\(f1(y))\" stroke=\"var(--grid)\" stroke-width=\"1\"/>")
            p.append("<text x=\"\(ML-6)\" y=\"\(f1(y+3))\" text-anchor=\"end\" fill=\"var(--muted)\" font-size=\"9\">\(pct)</text>")
        }
        let tickDF = DateFormatter(); tickDF.dateFormat = "HH:mm"
        let dayDF = DateFormatter(); dayDF.dateFormat = "dd/MM"
        let n = 5
        for k in 0..<n {
            let frac = Double(k) / Double(n - 1)
            let tt = Date(timeIntervalSince1970: t0 + frac * span)
            let x = ML + frac * PW
            let anchor = k == 0 ? "start" : (k == n - 1 ? "end" : "middle")
            p.append("<line x1=\"\(f1(x))\" y1=\"\(f1(MT+PH))\" x2=\"\(f1(x))\" y2=\"\(f1(MT+PH+3))\" stroke=\"var(--grid)\" stroke-width=\"1\"/>")
            p.append("<text x=\"\(f1(x))\" y=\"\(f1(MT+PH+13))\" text-anchor=\"\(anchor)\" fill=\"var(--muted)\" font-size=\"9\">\(tickDF.string(from: tt))</text>")
            p.append("<text x=\"\(f1(x))\" y=\"\(f1(MT+PH+23))\" text-anchor=\"\(anchor)\" fill=\"var(--muted)\" font-size=\"8\">\(dayDF.string(from: tt))</text>")
        }
        for i in 1..<rows.count {
            let a = rows[i - 1], c = rows[i]
            let col = c.2 >= a.2 ? "#34c759" : "#ff9f0a"
            p.append("<line x1=\"\(f1(X(a.0)))\" y1=\"\(f1(Y(a.2)))\" x2=\"\(f1(X(c.0)))\" y2=\"\(f1(Y(c.2)))\" stroke=\"\(col)\" stroke-width=\"2.5\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>")
        }
        let low = rows.min { $0.2 < $1.2 }!
        p.append("<circle cx=\"\(f1(X(low.0)))\" cy=\"\(f1(Y(low.2)))\" r=\"3.5\" fill=\"#ff9f0a\"/>")
        p.append("<text x=\"\(f1(X(low.0)))\" y=\"\(f1(Y(low.2)+15))\" text-anchor=\"middle\" fill=\"#ff9f0a\" font-size=\"9\" font-weight=\"bold\">\(low.2)%</text>")
        let last = rows.last!
        p.append("<circle cx=\"\(f1(X(last.0)))\" cy=\"\(f1(Y(last.2)))\" r=\"4.5\" fill=\"var(--card)\" stroke=\"var(--accent)\" stroke-width=\"2.5\"/>")
        return p.joined(separator: "\n")
    }

    let nowDF = DateFormatter(); nowDF.dateFormat = "HH:mm"
    var periodTxt = b.charging ? "מאז החיבור לחשמל" : "מאז הניתוק מהחשמל"
    if let ss = sessionSince { periodTxt += " · " + nowDF.string(from: ss) }
    let lowestPct = rows.map { $0.2 }.min() ?? 0
    let healthColor = b.health >= 80 ? "var(--ok)" : "var(--warn)"

    var remHtml = ""
    if let rm = b.remMin, rm > 0 {
        let lbl = b.charging ? "עד מלא" : "נשאר בערך"
        remHtml = "<span style=\"margin-inline-start:auto;display:inline-flex;align-items:center;gap:5px;color:var(--accent);font-weight:600;\">\(ic("clock","var(--accent)",15)) \(lbl) \(fmtMin(rm))</span>"
    }
    var sinceHtml = ""
    if b.charging {
        sinceHtml = "<div class=\"since\">\(ic("bolt","var(--ok)",17))<span>המחשב <b style=\"color:var(--ok);\">בטעינה</b> · \(b.soc)%</span>\(remHtml)</div>"
    } else if let lf = lastFull {
        let sft = fmtMin(Int(Date().timeIntervalSince(lf) / 60))
        sinceHtml = "<div class=\"since\">\(ic("battery","var(--accent)",17))<span>עובד <b style=\"color:var(--text);font-size:15px;\">\(sft)</b> מאז 100%</span>\(remHtml)</div>"
    } else if !remHtml.isEmpty {
        sinceHtml = "<div class=\"since\">\(ic("battery","var(--accent)",17))<span>על סוללה · \(b.soc)%</span>\(remHtml)</div>"
    }

    let rankColors = ["var(--danger)", "var(--warn)", "var(--accent)", "var(--muted)", "var(--muted)"]
    let maxCpu = max(apps.map { $0.cpu }.max() ?? 1, 1)
    var appRows = ""
    for (i, a) in apps.enumerated() {
        let barw = max(4, Int((a.cpu / maxCpu * 100).rounded()))
        let col = rankColors[min(i, 4)]
        let border = i < apps.count - 1 ? "border-bottom:0.5px solid var(--grid);" : ""
        appRows += "<div style=\"display:flex;align-items:center;gap:8px;padding:6px 0;\(border)\">\(ic(a.icon, col, 15))<span style=\"font-size:13px;color:var(--text);flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;\">\(a.name)</span><div style=\"width:64px;height:5px;background:var(--grid);border-radius:3px;overflow:hidden;\"><div style=\"width:\(barw)%;height:100%;background:\(col);\"></div></div><span style=\"font-size:12px;font-weight:500;color:var(--muted);width:34px;text-align:left;\">\(Int(a.cpu.rounded()))%</span></div>"
    }

    var wattVal = "", wattLbl = "", wattCol = ""
    if b.charging { wattVal = "בטעינה"; wattLbl = "מחובר לחשמל"; wattCol = "var(--ok)" }
    else {
        wattVal = "\(b.watts)W"
        if b.watts < 10 { wattLbl = "חסכוני 👍"; wattCol = "var(--ok)" }
        else if b.watts < 20 { wattLbl = "שימוש רגיל"; wattCol = "var(--text)" }
        else if b.watts < 35 { wattLbl = "גבוה — נרקן מהר"; wattCol = "var(--warn)" }
        else { wattLbl = "עומס מלא 🔥"; wattCol = "var(--danger)" }
    }

    let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    let doc = """
<!DOCTYPE html>
<html lang="he" dir="rtl">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>גרף סוללה</title>
<style>
  :root { --bg:#10161f; --card:#1a2330; --sub:#141c26; --text:#eef2f6; --muted:#7c8798;
    --grid:#26303d; --accent:#0a84ff; --ok:#34c759; --warn:#ff9f0a; --danger:#ff453a; }
  * { box-sizing:border-box; }
  body { margin:0; background:var(--bg); color:var(--text);
    font-family:-apple-system,'SF Pro Display',Arial,sans-serif; padding:12px; }
  .row4 { display:grid; grid-template-columns:repeat(4,1fr); gap:6px; margin-bottom:10px; }
  .row2 { display:grid; grid-template-columns:1fr 1fr; gap:6px; margin-bottom:12px; }
  .stat { background:var(--sub); border-radius:8px; padding:7px 4px; text-align:center; }
  .stat .v { font-size:16px; font-weight:700; margin-top:3px; }
  .stat .l { font-size:10px; color:var(--muted); display:flex; align-items:center; justify-content:center; gap:3px; }
  .live { background:var(--sub); border-radius:8px; padding:7px 8px; display:flex; align-items:center; gap:8px; }
  .live .v { font-size:14px; font-weight:700; }
  .live .l { font-size:11px; color:var(--muted); }
  .since { display:flex; align-items:center; gap:8px; background:rgba(10,132,255,.12);
    border:0.5px solid rgba(10,132,255,.3); border-radius:8px; padding:9px 11px; margin-bottom:12px;
    font-size:13px; color:var(--text); }
  .sec { font-size:11px; color:var(--muted); margin:0 0 5px; }
  .box { background:var(--sub); border-radius:8px; padding:4px 10px; margin-bottom:12px; }
  .card { background:var(--sub); border-radius:8px; padding:8px; margin-bottom:12px; }
  .btn { border:none; border-radius:8px; padding:8px; font-size:12px; font-weight:600; cursor:pointer;
    font-family:inherit; display:flex; align-items:center; justify-content:center; gap:5px; }
  .btns { display:grid; grid-template-columns:1fr 1fr; gap:6px; margin-bottom:10px; }
  .btn.warn { background:rgba(255,159,10,.18); color:var(--warn); }
  .btn.ok { background:rgba(52,199,89,.18); color:var(--ok); }
  .btn.acc { background:rgba(10,132,255,.18); color:var(--accent); }
  .btn.n { background:var(--card); color:var(--muted); border:0.5px solid var(--grid); }
  .btn:active { transform:scale(.96); }
  .foot { display:flex; align-items:center; gap:6px; justify-content:center; font-size:11px;
    color:var(--muted); border-top:0.5px solid var(--grid); padding-top:8px; }
  svg.g { width:100%; height:auto; display:block; }
</style></head>
<body>
  <div style="display:flex;align-items:center;gap:8px;margin-bottom:12px;">
    <span style="color:var(--accent);">\(ic("battery","var(--accent)",20))</span>
    <div style="flex:1;">
      <div style="font-size:15px;font-weight:600;">גרף הסוללה שלך</div>
      <div style="font-size:11px;color:var(--muted);">עודכן \(nowDF.string(from: Date())) · \(periodTxt)</div>
    </div>
  </div>
  <div class="row4">
    <div class="stat"><div class="l">\(ic("battery","#0a84ff",14)) נוכחי</div><div class="v">\(b.soc)%</div></div>
    <div class="stat"><div class="l">\(ic("heart","#ff6b81",14)) בריאות</div><div class="v" style="color:\(healthColor)">\(b.health)%</div></div>
    <div class="stat"><div class="l">\(ic("refresh","#a78bfa",14)) מחזורים</div><div class="v">\(b.cycles)</div></div>
    <div class="stat"><div class="l">\(ic("down","#ff9f0a",14)) ירד עד</div><div class="v" style="color:var(--danger)">\(lowestPct)%</div></div>
  </div>
  <div class="row2">
    <div class="live">\(ic("bolt",wattCol,16))<div><div class="v" style="color:\(wattCol)">\(wattVal)</div><div class="l">\(wattLbl)</div></div></div>
    <div class="live">\(ic("cpu","var(--accent)",16))<div><div class="v">\(loadS) / \(cores)</div><div class="l">עומס מעבד</div></div></div>
  </div>
  \(sinceHtml)
  <div class="sec" style="display:flex;justify-content:space-between;"><span>אפליקציות פעילות</span><span>צריכת מעבד</span></div>
  <div class="box">\(appRows)</div>
  <div class="sec">אחוז הסוללה · \(periodTxt)</div>
  <div class="card"><svg class="g" viewBox="0 0 \(Int(W)) \(Int(H))" xmlns="http://www.w3.org/2000/svg">\(svgInner())</svg>
    <div style="display:flex;gap:10px;justify-content:center;flex-wrap:wrap;font-size:10px;color:var(--muted);margin-top:6px;">
      <span style="display:inline-flex;align-items:center;gap:4px;"><i style="width:9px;height:9px;border-radius:50%;background:#34c759;"></i> עולה (בטעינה)</span>
      <span style="display:inline-flex;align-items:center;gap:4px;"><i style="width:9px;height:9px;border-radius:50%;background:#ff9f0a;"></i> יורדת (פריקה)</span>
      <span style="display:inline-flex;align-items:center;gap:4px;"><i style="width:9px;height:9px;border-radius:50%;background:var(--card);border:2px solid var(--accent);"></i> עכשיו</span>
    </div>
    <div style="font-size:10px;color:var(--muted);text-align:center;margin-top:4px;">↔ ציר אופקי = זמן · ↕ ציר אנכי = אחוז סוללה (0–100)</div>
  </div>
  <div class="btns">
    <button class="btn warn" onclick="act('kill')">\(ic("bolt","currentColor",15)) עצור מעמיס</button>
    <button class="btn ok" onclick="act('sims')">\(ic("phone","currentColor",15)) סגור סימולטורים</button>
    <button class="btn acc" onclick="act('refresh')">\(ic("refresh","currentColor",15)) רענן</button>
    <button class="btn n" onclick="act('clean')">\(ic("clean","currentColor",15)) ניקוי מלא</button>
  </div>
  <div class="foot">\(ic("shield","var(--ok)",14)) ניטור אוטומטי פעיל · מתריע על חום, צניחות וסימולטורים</div>
  <div style="text-align:center;font-size:10px;color:var(--muted);margin-top:6px;">Battery Live · גרסה \(version)</div>
<script>function act(x){try{window.webkit.messageHandlers.act.postMessage(x);}catch(e){}}</script>
</body></html>
"""
    let out = (NSTemporaryDirectory() as NSString).appendingPathComponent("battery_chart.html")
    try? doc.write(toFile: out, atomically: true, encoding: .utf8)
    return out
}

// ════════════════════════════════════════════════════════════
//  האפליקציה
// ════════════════════════════════════════════════════════════
final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler {
    var statusItem: NSStatusItem!
    var timer: Timer?
    var popover: NSPopover!
    var webView: WKWebView!

    var soc = 0, watts = 0, health = 0, cycles = 0, cores = 10, topcpu = 0, booted = 0, toppid = 0
    var charging = false
    var load = "0.0", topname = "-"
    var lastSoc = -1, prevWatts = 0
    var lastAlert: [String: Date] = [:]
    var alertsEnabled = true

    let protectedNames = ["WindowServer","kernel_task","launchd","logind","loginwindow",
        "mds","mds_stores","mdbulkimport","mdworker","mdsync","spotlight","Spotlight",
        "coreaudiod","Dock","Finder","SystemUIServer","WindowManager","Control","controlcenter",
        "ControlCenter","NotificationCenter","BatteryLive","backboardd","cfprefsd","distnoted",
        "bluetoothd","powerd","hidd","opendirectoryd","syslogd","configd"]

    func applicationDidFinishLaunching(_ notification: Notification) {
        alertsEnabled = (UserDefaults.standard.object(forKey: "alertsEnabled") as? Bool) ?? true
        setupLoginItem()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🔋…"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(self, name: "act")
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 440, height: 760), configuration: cfg)
        webView.setValue(false, forKey: "drawsBackground")
        let vc = NSViewController(); vc.view = webView
        popover = NSPopover(); popover.contentViewController = vc
        popover.contentSize = NSSize(width: 440, height: 760); popover.behavior = .transient

        refresh()
        regen(reload: false)
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in self?.refresh() }
        Timer.scheduledTimer(withTimeInterval: 20.0, repeats: true) { [weak self] _ in
            guard let s = self else { return }; s.regen(reload: s.popover.isShown)
        }
        checkForUpdate()
        Timer.scheduledTimer(withTimeInterval: 21600, repeats: true) { [weak self] _ in self?.checkForUpdate() }
    }

    // הפעלה אוטומטית בכניסה — שם האפליקציה בהגדרות (לא שם המפתח)
    func setupLoginItem() {
        if #available(macOS 13.0, *) {
            // מסיר LaunchAgent ישן (בלי bootout כדי לא להרוג את עצמנו), ורושם כפריט כניסה בשם האפליקציה
            let legacy = NSHomeDirectory() + "/Library/LaunchAgents/com.raniophir.batterylive.plist"
            try? FileManager.default.removeItem(atPath: legacy)
            try? SMAppService.mainApp.register()
        } else {
            let dir = NSHomeDirectory() + "/Library/LaunchAgents"
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let plist = dir + "/com.raniophir.batterylive.plist"
            if !FileManager.default.fileExists(atPath: plist) {
                let c = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.raniophir.batterylive</string>
  <key>ProgramArguments</key><array><string>/Applications/BatteryLive.app/Contents/MacOS/BatteryLive</string></array>
  <key>RunAtLoad</key><true/><key>ProcessType</key><string>Interactive</string>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
</dict></plist>
"""
                try? c.write(toFile: plist, atomically: true, encoding: .utf8)
                _ = runCmd("/bin/launchctl", ["bootstrap", "gui/\(getuid())", plist])
            }
        }
    }

    // ── עדכון אוטומטי מ-GitHub ──
    let updateManifestURL = "https://raw.githubusercontent.com/raniop/BatteryLive/main/latest.json"
    var availableUpdate: (version: String, url: String)?
    func currentVersion() -> String { (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0" }
    func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
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
                  let ver = obj["version"] as? String, let purl = obj["url"] as? String else {
                if manual { DispatchQueue.main.async { s.notify("לא ניתן לבדוק עדכונים כרגע") } }; return
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
            DispatchQueue.main.async { NSWorkspace.shared.open(dest) }
        }.resume()
    }

    // ── גרף (native) ──
    var chartFile = ""
    func genChart() -> String { buildChartHTML() }
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

    // ── מדדים למנו-בר ולניטור (native) ──
    func readStats() {
        let b = batteryData()
        soc = b.soc; watts = b.watts; charging = b.charging; health = b.health; cycles = b.cycles
        let (l, c) = loadAndCores(); load = l; cores = c
        let tp = topProc(); topname = tp.name; topcpu = tp.cpu; toppid = tp.pid
        booted = bootedSimIDs().count
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

    // אייקון סוללה דינמי בגודל של אפל (~25.5x14)
    func batteryImage(soc: Int, charging: Bool) -> NSImage {
        let w: CGFloat = 23.5, h: CGFloat = 14, cap: CGFloat = 2.0
        let over: CGFloat = charging ? 3.0 : 0.0
        let cw = w + cap + 1, chh = h + over * 2, oy = over
        let img = NSImage(size: NSSize(width: cw, height: chh))
        img.lockFocus()
        let body = NSRect(x: 0.5, y: oy + 0.5, width: w - 1, height: h - 1)
        let path = NSBezierPath(roundedRect: body, xRadius: 3, yRadius: 3); path.lineWidth = 1
        var template = false
        let color: NSColor
        if charging { color = .systemGreen } else if soc <= 20 { color = .systemRed } else { color = .black; template = true }
        color.setStroke(); path.stroke()
        let nub = NSBezierPath(roundedRect: NSRect(x: w, y: oy + h/2 - 2.2, width: cap, height: 4.4), xRadius: 1, yRadius: 1)
        color.setFill(); nub.fill()
        let inset: CGFloat = 2
        let fw = ((w - 1) - inset * 2) * CGFloat(max(0, min(100, soc))) / 100.0
        if fw > 0.5 {
            color.setFill()
            NSBezierPath(roundedRect: NSRect(x: 0.5 + inset, y: oy + 0.5 + inset, width: fw, height: (h - 1) - inset * 2), xRadius: 1.2, yRadius: 1.2).fill()
        }
        if charging {
            let cx = w/2 + 0.5, cy = chh/2, s = (chh - 1) / 2
            let bz = NSBezierPath()
            bz.move(to: NSPoint(x: cx + 2.4, y: cy + s))
            bz.line(to: NSPoint(x: cx - 3.8, y: cy - 0.5))
            bz.line(to: NSPoint(x: cx - 0.4, y: cy - 0.5))
            bz.line(to: NSPoint(x: cx - 2.4, y: cy - s))
            bz.line(to: NSPoint(x: cx + 4.0, y: cy + 0.9))
            bz.line(to: NSPoint(x: cx + 0.6, y: cy + 0.9))
            bz.close(); NSColor.white.setFill(); bz.fill()
        }
        img.unlockFocus(); img.isTemplate = template
        return img
    }

    // ── ניטור אוטומטי ──
    func autoMonitor() {
        if !charging && watts >= 30 && watts - prevWatts >= 12 { handleSpike("קפיצה פתאומית בצריכה ⚡️", "עלה ל-\(watts)W") }
        else if !charging && watts >= 30 { handleSpike("המחשב מתחמם 🔥", "צריכה גבוהה \(watts)W") }
        prevWatts = watts
        if lastSoc >= 0 && !charging && (lastSoc - soc) >= 12 {
            fire("crash", "ירידה חדה בסוללה ⚠️", "צנח מ-\(lastSoc)% ל-\(soc)% בבת אחת. סימן לחוסר כיול — כדאי לאתחל ולהטעין ל-100%.")
        }
        if !charging && soc <= 10 && soc > 0 { fire("low", "סוללה נמוכה 🪫", "נשארו \(soc)% — כדאי לחבר מטען.") }
    }
    func handleSpike(_ title: String, _ prefix: String) {
        if booted > 1 {
            let closed = closeExtraSims()
            if closed > 0 { fire("heat", title, "\(prefix). זיהיתי \(closed) סימולטורים מיותרים וסגרתי אותם אוטומטית 🔥"); refresh(); return }
        }
        let isProtected = protectedNames.contains { topname.lowercased().contains($0.lowercased()) }
        if isProtected { fire("heat", title, "\(prefix). הגורם: \(topname) (רכיב מערכת). נסה לסגור סימולטורים/אפליקציות כבדות מהווידג'ט.") }
        else { fire("heat", title, "\(prefix). הגורם: \(topname) (\(topcpu)%). פתח את הווידג'ט → \"עצור מעמיס\" כדי לעצור.") }
    }
    func fire(_ key: String, _ title: String, _ text: String) {
        guard alertsEnabled else { return }
        let now = Date()
        if let last = lastAlert[key], now.timeIntervalSince(last) < 300 { return }
        lastAlert[key] = now
        let note = NSUserNotification(); note.title = title; note.informativeText = text
        note.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(note)
    }

    // ── אינטראקציה ──
    @objc func statusClicked() {
        let ev = NSApp.currentEvent
        if ev?.type == .rightMouseUp || (ev?.modifierFlags.contains(.control) ?? false) { showMenu() } else { togglePopover() }
    }
    @objc func togglePopover() {
        if popover.isShown { popover.performClose(nil); return }
        var f = chartFile
        if f.isEmpty || !FileManager.default.fileExists(atPath: f) { f = genChart(); if !f.isEmpty { chartFile = f } }
        if !f.isEmpty {
            let url = URL(fileURLWithPath: f)
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        if let btn = statusItem.button {
            popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
        regen(reload: true)
    }
    func reloadChart() {
        guard !chartFile.isEmpty else { return }
        let url = URL(fileURLWithPath: chartFile)
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let cmd = message.body as? String else { return }
        switch cmd {
        case "kill": killTop()
        case "sims": closeSims(); refresh(); regen(reload: true)
        case "refresh": refresh(); regen(reload: true)
        case "clean": doClean()
        default: break
        }
    }

    @objc func doClean() {
        readStats()
        let closed = closeExtraSims()
        usleep(400_000); readStats()
        let simTxt = closed > 0 ? "נסגרו \(closed) סימולטורים מיותרים" : (booted > 0 ? "סימולטור אחד נשאר פתוח" : "אין סימולטורים מיותרים")
        let a = NSAlert()
        a.messageText = "🔋 ניקוי הושלם"
        a.informativeText = "בריאות סוללה: \(health)%  (\(cycles) מחזורים)\n\(simTxt)\nצריכת חשמל כרגע: \(watts)W\n\nטיפ: אתחל את המחשב פעם בשבוע לכיול הסוללה."
        a.addButton(withTitle: "סיימתי")
        NSApp.activate(ignoringOtherApps: true); a.runModal()
        refresh(); regen(reload: true)
    }

    func showMenu() {
        let m = NSMenu()
        if let up = availableUpdate {
            let it = NSMenuItem(title: "⬆︎ עדכן לגרסה \(up.version)", action: #selector(installUpdate), keyEquivalent: "")
            it.target = self
            it.attributedTitle = rtl("⬆︎ עדכן לגרסה \(up.version)", bold: true, color: .systemGreen)
            m.addItem(it); m.addItem(.separator())
        }
        m.addItem(actionItem("📊 הצג גרף סוללה", #selector(togglePopover)))
        m.addItem(actionItem("⚡︎ עצור את מה שהכי מעמיס (\(topname))", #selector(killTop)))
        m.addItem(actionItem("סגור סימולטורים מיותרים", #selector(closeSims)))
        m.addItem(actionItem("ניקוי מלא", #selector(doClean)))
        m.addItem(actionItem("רענן עכשיו", #selector(manualRefresh)))
        m.addItem(actionItem("בדוק עדכונים", #selector(checkForUpdateManual)))
        m.addItem(actionItem(alertsEnabled ? "🔕 השתק התראות" : "🔔 הפעל התראות", #selector(toggleAlerts)))
        m.addItem(.separator())
        m.addItem(actionItem("יציאה", #selector(quit)))
        statusItem.menu = m
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }
    func rtl(_ t: String, size: CGFloat = 13, bold: Bool = false, color: NSColor = .labelColor) -> NSAttributedString {
        let ps = NSMutableParagraphStyle(); ps.alignment = .right; ps.baseWritingDirection = .rightToLeft
        let font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        return NSAttributedString(string: t, attributes: [.paragraphStyle: ps, .font: font, .foregroundColor: color])
    }
    func actionItem(_ t: String, _ sel: Selector) -> NSMenuItem {
        let it = NSMenuItem(title: t, action: sel, keyEquivalent: ""); it.target = self; it.attributedTitle = rtl(t); return it
    }

    func notify(_ text: String) {
        let note = NSUserNotification(); note.title = "Battery Live"; note.informativeText = text
        NSUserNotificationCenter.default.deliver(note)
    }
    @objc func killTop() {
        readStats()
        let name = topname, pid = toppid
        if protectedNames.contains(where: { name.lowercased().contains($0.lowercased()) }) {
            let a = NSAlert()
            a.messageText = "אי אפשר לעצור את \(name)"
            a.informativeText = "זהו רכיב חיוני של macOS. עצירה עלולה לנתק את המסך או פשוט לא תעבוד (המערכת תפעיל אותו מחדש מיד).\n\nהכפתור מיועד לאפליקציות רגילות (Xcode, סימולטורים, אפליקציות תקועות)."
            a.alertStyle = .warning; a.addButton(withTitle: "הבנתי")
            NSApp.activate(ignoringOtherApps: true); a.runModal(); return
        }
        let c = NSAlert()
        c.messageText = "לעצור את \(name)?"
        c.informativeText = "התהליך צורך \(topcpu)% מהמעבד. עצירה תסגור אותו מיד (עבודה שלא נשמרה עלולה ללכת לאיבוד)."
        c.alertStyle = .warning; c.addButton(withTitle: "עצור"); c.addButton(withTitle: "ביטול")
        NSApp.activate(ignoringOtherApps: true)
        guard c.runModal() == .alertFirstButtonReturn else { return }
        killPid(pid); notify("עצרתי את \(name) ✓"); refresh(); regen(reload: true)
    }
    func killPid(_ pid: Int) {
        guard pid > 0 else { return }
        _ = runCmd("/bin/kill", ["-TERM", "\(pid)"])
    }
    @objc func closeSims() {
        let n = closeExtraSims()
        notify(n > 0 ? "נסגרו \(n) סימולטורים מיותרים 🔥" : "אין סימולטורים מיותרים לסגור ✓")
        refresh()
    }
    @objc func manualRefresh() { refresh() }
    @objc func toggleAlerts() {
        alertsEnabled.toggle()
        UserDefaults.standard.set(alertsEnabled, forKey: "alertsEnabled")
        notify(alertsEnabled ? "התראות הופעלו 🔔" : "התראות הושתקו 🔕")
    }
    @objc func quit() { NSApplication.shared.terminate(nil) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

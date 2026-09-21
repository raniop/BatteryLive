#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""גרף סוללה + מידע חי + אפליקציות פעילות — HTML קומפקטי, RTL, אייקונים מוטמעים (אופליין)."""
import subprocess, re, datetime, tempfile, os, sys

def run(cmd):
    try:
        return subprocess.check_output(cmd, text=True, errors="ignore")
    except Exception:
        return ""

# ── אייקונים מוטמעים (SVG, בסגנון Tabler) ──
ICONS = {
 "battery": ('<rect x="3" y="8" width="15" height="8" rx="2"/><path d="M20 11v2"/>', False),
 "bolt": ('<path d="M13 3L5 13h6l-1 8 8-10h-6z"/>', True),
 "cpu": ('<rect x="7" y="7" width="10" height="10" rx="1"/><path d="M9 3v2M12 3v2M15 3v2M9 19v2M12 19v2M15 19v2M3 9h2M3 12h2M3 15h2M19 9h2M19 12h2M19 15h2"/>', False),
 "refresh": ('<path d="M20 11a8 8 0 1 0-2.3 5.6"/><path d="M20 5v6h-6"/>', False),
 "file": ('<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5M9 13h6M9 17h6"/>', False),
 "shield": ('<path d="M12 3l7 3v6c0 5-3.5 8-7 9-3.5-1-7-4-7-9V6z"/><path d="M9 12l2 2 4-4"/>', False),
 "phone": ('<rect x="7" y="3" width="10" height="18" rx="2"/><path d="M11 18h2"/>', False),
 "message": ('<path d="M8 19l-4 3V6a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H8z"/>', False),
 "code": ('<path d="M8 8l-4 4 4 4M16 8l4 4-4 4"/>', False),
 "window": ('<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M3 9h18"/>', False),
 "world": ('<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c3 3 3 15 0 18M12 3c-3 3-3 15 0 18"/>', False),
 "search": ('<circle cx="10.5" cy="10.5" r="6"/><path d="M20 20l-5-5"/>', False),
 "volume": ('<path d="M6 9v6h4l5 4V5l-5 4z"/>', False),
 "clean": ('<path d="M12 3l1.4 4.1L17.5 8l-4.1 1.4L12 13l-1.4-3.6L6.5 8l4.1-0.9z"/><path d="M6 20l3-3M18 20l-3-3"/>', False),
 "heart": ('<path d="M12 20l-7.5-7.3a4.3 4.3 0 0 1 6.1-6L12 7.3l1.4-0.6a4.3 4.3 0 0 1 6.1 6z"/>', False),
 "down": ('<path d="M3 7l6 6 4-4 8 8"/><path d="M14 17h7v-7"/>', False),
 "gauge": ('<path d="M12 14l4-4"/><circle cx="12" cy="13" r="8"/><path d="M12 5v1M20 13h-1M5 13H4"/>', False),
 "clock": ('<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>', False),
}
def ic(name, color="currentColor", size=16):
    inner, filled = ICONS.get(name, ICONS["cpu"])
    if filled:
        s = f'fill="{color}" stroke="none"'
    else:
        s = f'fill="none" stroke="{color}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"'
    return f'<svg width="{size}" height="{size}" viewBox="0 0 24 24" {s} style="flex:none;vertical-align:middle;">{inner}</svg>'

# ── מצב סוללה נוכחי ──
health = cycles_now = soc = watts = 0
charging = False
ior = run(["ioreg", "-rn", "AppleSmartBattery"])
def _g(k, s=ior):
    m = re.search(r'"%s"\s*=\s*(\d+)' % k, s); return int(m.group(1)) if m else 0
try:
    design = int(re.search(r'"DesignCapacity"=(\d+)', ior).group(1))
    fullc  = int(re.search(r'"FullChargeCapacity"=(\d+)', ior).group(1))
    cycles_now = _g("CycleCount")
    health = round(fullc / design * 100) if design else 0
    volt = _g("Voltage"); amp = _g("Amperage")
    if amp > 2**63: amp -= 2**64
    watts = round(abs(amp) * volt / 1_000_000)
except Exception:
    pass
batt = run(["pmset", "-g", "batt"])
m = re.search(r'(\d+)%', batt)
if m: soc = int(m.group(1))
charging = ("AC Power" in batt)

# ── עומס מעבד ──
cores = int(run(["sysctl", "-n", "hw.ncpu"]).strip() or "10")
la = run(["sysctl", "-n", "vm.loadavg"])
mla = re.search(r'([\d.]+)', la)
load1 = mla.group(1) if mla else "0"

# ── אפליקציות פעילות ──
def group_name(comm):
    b = os.path.basename(comm.strip()); low = comm.lower()
    if "claude" in low: return ("Claude", "message")
    if "swift" in low or "xcode" in low or "swbbuild" in low or "sourcekit" in low: return ("Xcode", "code")
    if any(k in low for k in ["simulator","backboardd","springboard","simmetal","coresimulator"]): return ("Simulator", "phone")
    if b == "WindowServer": return ("WindowServer", "window")
    if "chrome" in low or "safari" in low or "firefox" in low: return ("דפדפן", "world")
    if "whatsapp" in low: return ("WhatsApp", "message")
    if "spotlight" in low or "mds" in low or "metadata" in low: return ("Spotlight", "search")
    if "coreaudio" in low: return ("שמע", "volume")
    if b in ("kernel_task","launchd"): return (None, None)
    return (b, "cpu")

apps = {}
for line in run(["ps", "-Ao", "pcpu,comm", "-r"]).splitlines()[1:]:
    parts = line.strip().split(None, 1)
    if len(parts) != 2: continue
    try: cpu = float(parts[0])
    except: continue
    name, icon = group_name(parts[1])
    if not name: continue
    if name not in apps: apps[name] = [0.0, icon]
    apps[name][0] += cpu
top_apps = sorted(apps.items(), key=lambda kv: kv[1][0], reverse=True)[:5]
max_cpu = max((v[0] for _, v in top_apps), default=1) or 1

# ── היסטוריה לגרף ──
log = run(["pmset", "-g", "log"])
pat = re.compile(r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}).*?Using (AC|Batt)\s*\(Charge:?\s*(\d+)", re.M)
rows = []
for mm in pat.finditer(log):
    ts = datetime.datetime.strptime(mm.group(1), "%Y-%m-%d %H:%M:%S")
    rows.append((ts, mm.group(2), int(mm.group(3))))
if rows:
    cutoff = rows[-1][0] - datetime.timedelta(days=4)
    rows = [r for r in rows if r[0] >= cutoff]
dedup = []
for r in rows:
    if not dedup or dedup[-1][2] != r[2] or dedup[-1][1] != r[1]:
        dedup.append(r)
rows = dedup

# הוספת המצב הנוכחי האמיתי כנקודה אחרונה (הלוג לפעמים מפגר)
cur_source = "AC" if charging else "Batt"
if soc:
    rows.append((datetime.datetime.now(), cur_source, soc))

# פורמט זמן טבעי בעברית
def fmt_min(mins):
    mins = max(0, int(mins)); h, m = divmod(mins, 60)
    if h == 0:
        return "פחות מדקה" if m == 0 else f"{m} דקות"
    hw = "שעה" if h == 1 else f"{h} שעות"
    return hw if m == 0 else f"{hw} ו-{m} דקות"

# זמן מאז שהסוללה הייתה 100%
last_full = None
for (ts, s, c) in rows:
    if c >= 100:
        last_full = ts
if last_full:
    since_full_txt = fmt_min((datetime.datetime.now() - last_full).total_seconds() / 60)
    drop_txt = f"ירדת מ-100% ל-{soc}%"
else:
    since_full_txt = None

# הערכת זמן שנותר (בטעינה=עד מלא, בפריקה=עד ריקון)
rem_txt = None
mrem = re.search(r'(\d+):(\d\d)\s+remaining', batt)
if mrem:
    rem_txt = fmt_min(int(mrem.group(1)) * 60 + int(mrem.group(2)))
else:
    # גיבוי מ-ioreg כשאין הערכה ב-pmset
    key = "AvgTimeToFull" if charging else "AvgTimeToEmpty"
    v = _g(key)
    if 0 < v < 1440:
        rem_txt = fmt_min(v)

# חיתוך לסשן הנוכחי בלבד — מאז המעבר האחרון (ניתוק/חיבור לחשמל)
session_since = None
if len(rows) >= 2:
    start_i = 0
    for i in range(len(rows)-1, -1, -1):
        if rows[i][1] != cur_source:
            start_i = i          # כולל את נקודת המעבר עצמה
            session_since = rows[i][0]
            break
    if session_since is not None:
        rows = rows[start_i:]

W, H = 380, 150
ML, MR, MT, MB = 30, 26, 12, 30
PW, PH = W-ML-MR, H-MT-MB
def build_svg():
    if len(rows) < 2:
        return '<text x="190" y="70" text-anchor="middle" fill="#888" font-size="13">אוסף נתונים...</text>'
    t0 = rows[0][0].timestamp(); t1 = rows[-1][0].timestamp(); span = max(1, t1-t0)
    def X(ts): return ML + (ts.timestamp()-t0)/span*PW
    def Y(c):  return MT + (100-c)/100*PH
    p = []
    for pct in (0,50,100):
        y = Y(pct)
        p.append(f'<line x1="{ML}" y1="{y:.1f}" x2="{ML+PW}" y2="{y:.1f}" stroke="var(--grid)" stroke-width="1"/>')
        p.append(f'<text x="{ML-6}" y="{y+3:.1f}" text-anchor="end" fill="var(--muted)" font-size="9">{pct}</text>')
    nticks = 5
    for k in range(nticks):
        frac = k/(nticks-1)
        tt = datetime.datetime.fromtimestamp(t0 + frac*span)
        x = ML + frac*PW
        anchor = "start" if k==0 else ("end" if k==nticks-1 else "middle")
        p.append(f'<line x1="{x:.1f}" y1="{MT+PH:.1f}" x2="{x:.1f}" y2="{MT+PH+3:.1f}" stroke="var(--grid)" stroke-width="1"/>')
        p.append(f'<text x="{x:.1f}" y="{MT+PH+13:.1f}" text-anchor="{anchor}" fill="var(--muted)" font-size="9">{tt.strftime("%H:%M")}</text>')
        p.append(f'<text x="{x:.1f}" y="{MT+PH+23:.1f}" text-anchor="{anchor}" fill="var(--muted)" font-size="8">{tt.strftime("%d/%m")}</text>')
    for i in range(1,len(rows)):
        (ta,_,ca)=rows[i-1]; (tb,_,cb)=rows[i]
        col = "#34c759" if cb>=ca else "#ff9f0a"
        p.append(f'<line x1="{X(ta):.1f}" y1="{Y(ca):.1f}" x2="{X(tb):.1f}" y2="{Y(cb):.1f}" stroke="{col}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>')
    low = min(rows, key=lambda r:r[2])
    p.append(f'<circle cx="{X(low[0]):.1f}" cy="{Y(low[2]):.1f}" r="3.5" fill="#ff9f0a"/>')
    p.append(f'<text x="{X(low[0]):.1f}" y="{Y(low[2])+15:.1f}" text-anchor="middle" fill="#ff9f0a" font-size="9" font-weight="bold">{low[2]}%</text>')
    last=rows[-1]
    p.append(f'<circle cx="{X(last[0]):.1f}" cy="{Y(last[2]):.1f}" r="4.5" fill="var(--card)" stroke="var(--accent)" stroke-width="2.5"/>')
    return "\n".join(p)

svg_inner = build_svg()
now = datetime.datetime.now().strftime("%H:%M")
period_txt = ("מאז החיבור לחשמל" if charging else "מאז הניתוק מהחשמל")
if session_since:
    period_txt += " · " + session_since.strftime("%H:%M")
lowest_pct = min((r[2] for r in rows), default=0)

rem_html = ""
if rem_txt:
    lbl = "עד מלא" if charging else "נשאר בערך"
    rem_html = (f'<span style="margin-inline-start:auto;display:inline-flex;align-items:center;gap:5px;'
      f'color:var(--accent);font-weight:600;">{ic("clock","var(--accent)",15)} {lbl} {rem_txt}</span>')

if charging:
    since_html = (f'<div class="since">{ic("bolt","var(--ok)",17)}'
      f'<span>המחשב <b style="color:var(--ok);">בטעינה</b> · {soc}%</span>{rem_html}</div>')
elif since_full_txt:
    since_html = (f'<div class="since">{ic("battery","var(--accent)",17)}'
      f'<span>עובד <b style="color:var(--text);font-size:15px;">{since_full_txt}</b> מאז 100%</span>{rem_html}</div>')
else:
    since_html = (f'<div class="since">{ic("battery","var(--accent)",17)}<span>על סוללה · {soc}%</span>{rem_html}</div>') if rem_html else ""
health_color = "var(--ok)" if health>=80 else "var(--warn)"

rank_colors = ["var(--danger)","var(--warn)","var(--accent)","var(--muted)","var(--muted)"]
app_rows = ""
for i,(name,(cpu,icon)) in enumerate(top_apps):
    barw = max(4, round(cpu/max_cpu*100)); col = rank_colors[min(i,4)]
    border = "border-bottom:0.5px solid var(--grid);" if i < len(top_apps)-1 else ""
    app_rows += f'''<div style="display:flex;align-items:center;gap:8px;padding:6px 0;{border}">
      {ic(icon, col, 15)}
      <span style="font-size:13px;color:var(--text);flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">{name}</span>
      <div style="width:64px;height:5px;background:var(--grid);border-radius:3px;overflow:hidden;"><div style="width:{barw}%;height:100%;background:{col};"></div></div>
      <span style="font-size:12px;font-weight:500;color:var(--muted);width:34px;text-align:left;">{round(cpu)}%</span>
    </div>'''

# דירוג צריכת החשמל
if charging:
    watt_val, watt_lbl, watt_col = "בטעינה", "מחובר לחשמל", "var(--ok)"
else:
    watt_val = f"{watts}W"
    if watts < 10:   watt_lbl, watt_col = "חסכוני 👍", "var(--ok)"
    elif watts < 20: watt_lbl, watt_col = "שימוש רגיל", "var(--text)"
    elif watts < 35: watt_lbl, watt_col = "גבוה — נרקן מהר", "var(--warn)"
    else:            watt_lbl, watt_col = "עומס מלא 🔥", "var(--danger)"
doc = f"""<!DOCTYPE html>
<html lang="he" dir="rtl">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>גרף סוללה</title>
<style>
  :root {{ --bg:#10161f; --card:#1a2330; --sub:#141c26; --text:#eef2f6; --muted:#7c8798;
    --grid:#26303d; --accent:#0a84ff; --ok:#34c759; --warn:#ff9f0a; --danger:#ff453a; }}
  * {{ box-sizing:border-box; }}
  body {{ margin:0; background:var(--bg); color:var(--text);
    font-family:-apple-system,'SF Pro Display',Arial,sans-serif; padding:12px; }}
  .row4 {{ display:grid; grid-template-columns:repeat(4,1fr); gap:6px; margin-bottom:10px; }}
  .row2 {{ display:grid; grid-template-columns:1fr 1fr; gap:6px; margin-bottom:12px; }}
  .stat {{ background:var(--sub); border-radius:8px; padding:7px 4px; text-align:center; }}
  .stat .v {{ font-size:16px; font-weight:700; margin-top:3px; }}
  .stat .l {{ font-size:10px; color:var(--muted); display:flex; align-items:center; justify-content:center; gap:3px; }}
  .live {{ background:var(--sub); border-radius:8px; padding:7px 8px; display:flex; align-items:center; gap:8px; }}
  .live .v {{ font-size:14px; font-weight:700; }}
  .live .l {{ font-size:11px; color:var(--muted); }}
  .since {{ display:flex; align-items:center; gap:8px; background:rgba(10,132,255,.12);
    border:0.5px solid rgba(10,132,255,.3); border-radius:8px; padding:9px 11px; margin-bottom:12px;
    font-size:13px; color:var(--text); }}
  .sec {{ font-size:11px; color:var(--muted); margin:0 0 5px; }}
  .box {{ background:var(--sub); border-radius:8px; padding:4px 10px; margin-bottom:12px; }}
  .card {{ background:var(--sub); border-radius:8px; padding:8px; margin-bottom:12px; }}
  .btn {{ border:none; border-radius:8px; padding:8px; font-size:12px; font-weight:600; cursor:pointer;
    font-family:inherit; display:flex; align-items:center; justify-content:center; gap:5px; }}
  .btns {{ display:grid; grid-template-columns:1fr 1fr; gap:6px; margin-bottom:10px; }}
  .btn.warn {{ background:rgba(255,159,10,.18); color:var(--warn); }}
  .btn.ok {{ background:rgba(52,199,89,.18); color:var(--ok); }}
  .btn.acc {{ background:rgba(10,132,255,.18); color:var(--accent); }}
  .btn.n {{ background:var(--card); color:var(--muted); border:0.5px solid var(--grid); }}
  .btn:active {{ transform:scale(.96); }}
  .foot {{ display:flex; align-items:center; gap:6px; justify-content:center; font-size:11px;
    color:var(--muted); border-top:0.5px solid var(--grid); padding-top:8px; }}
  svg.g {{ width:100%; height:auto; display:block; }}
</style></head>
<body>
  <div style="display:flex;align-items:center;gap:8px;margin-bottom:12px;">
    <span style="color:var(--accent);">{ic("battery","var(--accent)",20)}</span>
    <div style="flex:1;">
      <div style="font-size:15px;font-weight:600;">גרף הסוללה שלך</div>
      <div style="font-size:11px;color:var(--muted);">עודכן {now} · {period_txt}</div>
    </div>
  </div>

  <div class="row4">
    <div class="stat"><div class="l">{ic("battery","#0a84ff",14)} נוכחי</div><div class="v">{soc}%</div></div>
    <div class="stat"><div class="l">{ic("heart","#ff6b81",14)} בריאות</div><div class="v" style="color:{health_color}">{health}%</div></div>
    <div class="stat"><div class="l">{ic("refresh","#a78bfa",14)} מחזורים</div><div class="v">{cycles_now}</div></div>
    <div class="stat"><div class="l">{ic("down","#ff9f0a",14)} ירד עד</div><div class="v" style="color:var(--danger)">{lowest_pct}%</div></div>
  </div>

  <div class="row2">
    <div class="live">{ic("bolt",watt_col,16)}<div><div class="v" style="color:{watt_col}">{watt_val}</div><div class="l">{watt_lbl}</div></div></div>
    <div class="live">{ic("cpu","var(--accent)",16)}<div><div class="v">{load1} / {cores}</div><div class="l">עומס מעבד</div></div></div>
  </div>

  {since_html}

  <div class="sec" style="display:flex;justify-content:space-between;"><span>אפליקציות פעילות</span><span>צריכת מעבד</span></div>
  <div class="box">{app_rows}</div>

  <div class="sec">אחוז הסוללה · {period_txt}</div>
  <div class="card"><svg class="g" viewBox="0 0 {W} {H}" xmlns="http://www.w3.org/2000/svg">{svg_inner}</svg>
    <div style="display:flex;gap:10px;justify-content:center;flex-wrap:wrap;font-size:10px;color:var(--muted);margin-top:6px;">
      <span style="display:inline-flex;align-items:center;gap:4px;"><i style="width:9px;height:9px;border-radius:50%;background:#34c759;"></i> עולה (בטעינה)</span>
      <span style="display:inline-flex;align-items:center;gap:4px;"><i style="width:9px;height:9px;border-radius:50%;background:#ff9f0a;"></i> יורדת (פריקה)</span>
      <span style="display:inline-flex;align-items:center;gap:4px;"><i style="width:9px;height:9px;border-radius:50%;background:var(--card);border:2px solid var(--accent);"></i> עכשיו</span>
    </div>
    <div style="font-size:10px;color:var(--muted);text-align:center;margin-top:4px;">↔ ציר אופקי = זמן · ↕ ציר אנכי = אחוז סוללה (0–100)</div>
  </div>

  <div class="btns">
    <button class="btn warn" onclick="act('kill')">{ic("bolt","currentColor",15)} עצור מעמיס</button>
    <button class="btn ok" onclick="act('sims')">{ic("phone","currentColor",15)} סגור סימולטורים</button>
    <button class="btn acc" onclick="act('refresh')">{ic("refresh","currentColor",15)} רענן</button>
    <button class="btn n" onclick="act('clean')">{ic("clean","currentColor",15)} ניקוי מלא</button>
  </div>

  <div class="foot">{ic("shield","var(--ok)",14)} ניטור אוטומטי פעיל · מתריע על חום, צניחות וסימולטורים</div>
<script>function act(x){{try{{window.webkit.messageHandlers.act.postMessage(x);}}catch(e){{}}}}</script>
</body></html>"""

out = os.path.join(tempfile.gettempdir(), "battery_chart.html")
with open(out, "w", encoding="utf-8") as f:
    f.write(doc)
if "--noopen" not in sys.argv:
    import webbrowser; webbrowser.open("file://" + out)
print(out)

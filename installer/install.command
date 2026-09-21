#!/bin/zsh
# ═══════════════════════════════════════════════════
#  התקנת Battery Live 🔋 — לחיצה כפולה מתקינה הכל
# ═══════════════════════════════════════════════════
DIR="$(cd "$(dirname "$0")" && pwd)"
DEST="/Applications/BatteryLive.app"
UID_NUM=$(id -u)

print "\n🔋 \033[1mמתקין את Battery Live...\033[0m\n"

# עצירת מופע קיים (אם יש)
launchctl bootout gui/$UID_NUM/com.raniophir.batterylive 2>/dev/null
killall BatteryLive 2>/dev/null

# העתקה ל-Applications
rm -rf "$DEST"
if ! cp -R "$DIR/BatteryLive.app" /Applications/ 2>/dev/null; then
  print "\033[31m✗ לא ניתן להעתיק ל-Applications. גרור ידנית את BatteryLive.app לתיקיית Applications ונסה שוב.\033[0m"
  read "?הקש Enter לסגירה."; exit 1
fi

# הסרת 'הסגר' של macOS כדי שירוץ בלי אזהרות
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null

# יצירת הפעלה אוטומטית בכל הדלקה
mkdir -p "$HOME/Library/LaunchAgents"
PLIST="$HOME/Library/LaunchAgents/com.raniophir.batterylive.plist"
cat > "$PLIST" <<'PL'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.raniophir.batterylive</string>
  <key>ProgramArguments</key><array><string>/Applications/BatteryLive.app/Contents/MacOS/BatteryLive</string></array>
  <key>RunAtLoad</key><true/>
  <key>ProcessType</key><string>Interactive</string>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
</dict>
</plist>
PL

launchctl bootstrap gui/$UID_NUM "$PLIST" 2>/dev/null
launchctl kickstart -k gui/$UID_NUM/com.raniophir.batterylive 2>/dev/null

sleep 2
if pgrep -f "BatteryLive/Contents/MacOS" >/dev/null; then
  print "\033[32m✓ הותקן והופעל בהצלחה!\033[0m"
  print "  חפש את האייקון 🔋 בשורת התפריטים למעלה (ליד השעון)."
  print "  יעלה אוטומטית בכל הדלקה של המחשב."
else
  print "\033[33m⚠ הותקן, אך לא הופעל אוטומטית. פתח ידנית את BatteryLive מתיקיית Applications.\033[0m"
fi
print "\nהקש Enter לסגירה."
read

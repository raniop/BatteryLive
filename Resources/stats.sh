#!/bin/zsh
# מוציא שורת CSV עם כל המדדים, מופרד ב-|
raw=$(ioreg -rn AppleSmartBattery 2>/dev/null)
design=$(echo "$raw" | grep -oE '"DesignCapacity"=[0-9]+' | grep -oE '[0-9]+')
full=$(echo "$raw" | grep -oE '"FullChargeCapacity"=[0-9]+' | grep -oE '[0-9]+')
cycles=$(echo "$raw" | grep '"CycleCount"' | grep -oE '[0-9]+' | head -1)
volt=$(echo "$raw" | grep '"Voltage"' | grep -oE '[0-9]+' | head -1)
amp_raw=$(echo "$raw" | grep '"Amperage"' | grep -oE '[0-9]+' | head -1)
batt=$(pmset -g batt)
soc=$(echo "$batt" | grep -oE '[0-9]+%' | head -1 | tr -d '%')
if echo "$batt" | grep -q "AC Power"; then charging=1; else charging=0; fi
watts=$(python3 -c "v=$amp_raw; a=(v-2**64 if v>2**63 else v); print(round(abs(a)*$volt/1000000))" 2>/dev/null)
health=$(python3 -c "print(round($full/$design*100))" 2>/dev/null)
cores=$(sysctl -n hw.ncpu)
load=$(sysctl -n vm.loadavg | awk '{print $2}')
top=$(ps -Ao pid,pcpu,comm -r | sed -n 2p)
toppid=$(echo "$top" | awk '{print $1}')
topcpu=$(echo "$top" | awk '{printf "%d", $2}')
topname=$(basename "$(echo "$top" | sed -E 's/^[[:space:]]*[0-9]+[[:space:]]+[0-9.]+[[:space:]]+//')")
booted=$(xcrun simctl list devices booted 2>/dev/null | grep -c Booted)
echo "${soc}|${watts}|${charging}|${health}|${cycles}|${load}|${cores}|${topcpu}|${topname}|${booted}|${toppid}"

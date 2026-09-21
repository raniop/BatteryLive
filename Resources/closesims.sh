#!/bin/zsh
# סוגר סימולטורים עודפים, משאיר אחד פתוח
booted_ids=(${(f)"$(xcrun simctl list devices booted 2>/dev/null | grep -oE '[0-9A-F]{8}-[0-9A-F-]{27}')"})
booted=${#booted_ids[@]}
closed=0
if (( booted > 1 )); then
  for id in ${booted_ids[@]:1}; do
    xcrun simctl shutdown "$id" 2>/dev/null && ((closed++))
  done
fi
echo "$closed"

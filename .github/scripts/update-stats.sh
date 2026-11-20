#!/usr/bin/env bash
# Zahlen für den Hero der Website: GitHub-Sterne und Installer-Downloads.
# Gleiche Rechnung wie components/antik/github-stats.ts in der Landingpage.
set -euo pipefail
REPOS=(Panto92/Opencognit OpenCognitOS/opencognit-releases)
# Downloads früherer, gelöschter Releases (Stand 19.11.2026: insgesamt 529, davon zählt GitHub noch 290)
EARLIER_DOWNLOADS=239
stars=0
downloads=$EARLIER_DOWNLOADS
for repo in "${REPOS[@]}"; do
  stars=$(( stars + $(gh api "repos/$repo" --jq '.stargazers_count') ))
  n=$(gh api --paginate "repos/$repo/releases?per_page=100" \
    --jq '[.[].assets[] | select(.name | test("\\.(AppImage|deb|exe)$")) | .download_count] | add // 0' \
    | awk '{ s += $1 } END { print s + 0 }')
  downloads=$(( downloads + n ))
done
printf '{"stars":%d,"downloads":%d}\n' "$stars" "$downloads"

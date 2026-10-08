#!/bin/bash
# Publishes public/endpoints.json to both hosts the apps read from, so they never drift apart:
#   1. GitHub (raw file on main): the master copy and the apps' backup source
#   2. Cloudflare Pages (apptor-config.pages.dev): the apps' first source
# Usage: ./publish.sh "Move Velqo to the old backend"
set -euo pipefail
cd "$(dirname "$0")"

message="${1:?Usage: ./publish.sh \"what changed\"}"

node validate.mjs --live

git add public/endpoints.json
if ! git diff --cached --quiet; then
  git commit -q -m "$message"
fi
git push -q origin main

source ~/.agents/.env
CLOUDFLARE_API_TOKEN="$CLOUDFLARE_API_TOKEN" CLOUDFLARE_ACCOUNT_ID=9c08258ca5aab126753fdaa4a6a226ee \
  npx -y wrangler@3 pages deploy public --project-name apptor-config --branch main --commit-dirty=true

# Both copies must now match the local file (GitHub's raw cache can lag up to 5 minutes).
local_copy=$(node -e 'console.log(JSON.stringify(require("./public/endpoints.json")))')
for source in \
  "https://apptor-config.pages.dev/endpoints.json" \
  "https://raw.githubusercontent.com/Amian/app-config/main/public/endpoints.json?nocache=$(date +%s)"; do
  remote=$(curl -fsS "$source" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log(JSON.stringify(JSON.parse(s)))}catch{console.log("not-json")}})' || echo "unreachable")
  if [ "$remote" = "$local_copy" ]; then echo "✓ live: ${source%%\?*}"; else echo "… not updated yet (cache): ${source%%\?*}"; fi
done

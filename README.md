# app-config

The backend addresses every Apptor app uses, in one public file, so a backend can move (to another
Render account, to Cloudflare, to a new domain) without an app update.

- **The file:** [`public/endpoints.json`](public/endpoints.json). Apps are keyed by their iOS bundle ID
  (also used on Android). Each maps service names (`api`, `market`, `assets` …) to a base address.
  `default` holds shared services every app gets (`support`); an app's own entry wins.
- **Served from two places:** `https://apptor-config.pages.dev/endpoints.json` (Cloudflare Pages,
  first) and `https://raw.githubusercontent.com/Amian/app-config/main/public/endpoints.json` (backup).
  Neither needs our own domain.
- **App side:** copy [`clients/Endpoints.swift`](clients/Endpoints.swift) or
  [`clients/endpoints.dart`](clients/endpoints.dart) into the app unchanged; usage is at the top of
  each. Launch never waits for the network; a file that fails any check is ignored.

Nothing here is secret: the same addresses are visible to anyone watching an app's traffic.
Whoever can edit this file decides where apps send requests, so the GitHub and Cloudflare
accounts behind it must have 2FA.

## Moving an app

1. Edit its line in `public/endpoints.json`.
2. `./publish.sh "Move Velqo to the old backend"` (validates, checks every address answers,
   pushes to GitHub, deploys Pages, confirms both copies).
3. Apps with the loader switch on their next launch, or straight away after a failed request.
   Installs from before the loader keep their built-in address, so keep the old backend running
   until the traffic counter (`/Users/anum/Development/AppTraffic`) shows they have gone.

## Rules for the file

- `version` stays `1`. Apps ignore any other version, so a breaking format change ships as a new
  file name with a new loader.
- Every address is `https`, a base address only (no path, no trailing slash).
- `node validate.mjs` checks the shape; `--live` also checks every address answers.

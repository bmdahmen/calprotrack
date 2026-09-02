# CalProTrack Watch App — scaffold

A minimal watchOS app: one page showing today's calories/protein, one page
to log a meal. Talks directly to the same Cloudflare Worker the web app
uses (`https://calorie.bmdahmen.workers.dev`) — no iPhone relay needed,
watchOS apps have their own network access.

## Set up the Xcode project

1. Xcode → File → New → Project → **watchOS → App**.
2. Product Name: `CalProTrackWatch`. Interface: **SwiftUI**. Language: **Swift**.
   Leave "Include Notification Scene" unchecked. This creates a Watch App
   target plus a minimal iOS companion target — the companion isn't used by
   this scaffold, just leave its default ContentView as-is.
3. Delete the placeholder `ContentView.swift` Xcode generated inside the
   Watch App group (keep the iOS one alone).
4. Drag this repo's `watch-app/Shared/` and `watch-app/WatchApp/` folders
   into the Watch App target in Xcode (File → Add Files, or drag from
   Finder) — when prompted, make sure **only the Watch App target** is
   checked for target membership (not the iOS companion).
5. Signing & Capabilities tab on the Watch App target → Team → your Apple
   ID (Personal Team is fine, no paid account needed). Do the same for the
   iOS companion target — both need a team selected to build.
6. Build & run onto your paired Watch (select it as the run destination;
   Xcode will prompt to also install the companion iOS app on your phone,
   which is normal/required, you just won't open it for anything).

No entitlements, no Info.plist changes, no third-party packages needed —
everything's plain SwiftUI + URLSession, all HTTPS so no App Transport
Security exceptions either.

## First run

1. On your phone/computer, open the CalProTrack web app, log in, open
   Safari dev tools (or any browser), and run:
   ```js
   localStorage.getItem('bl_session')
   ```
2. On the Watch, open the **Today** page → tap the gear icon → paste that
   token into **Settings** → Save. Good for ~90 days (the Worker's session
   TTL); repeat this step when it expires.
3. Swipe to **Log Meal** to add an entry, or pull-to-refresh **Today** to
   see current totals.

## Known gap (backend, not this app)

While wiring this up I found that `worker.js`'s `/meals/save` handler
never persists `weight_g` — it only inserts `id, date, desc, cal, pro,
time`. So weight silently doesn't survive a reload for any meal (web or
watch). Didn't touch it as part of this scaffold since it's a separate
fix — worth doing as its own change if you want weight data to actually
stick.

## Natural next steps (not built yet)

- Route Log Meal through the same AI weight/calorie/protein auto-calc the
  web app's "Add Food" uses, instead of manual entry only.
- A complication showing today's calories on the watch face.
- HealthKit read access for calories *burned* (the earlier discussion) —
  separate feature, would need the HealthKit entitlement added in
  Signing & Capabilities plus a usage-description string in the Watch
  target's Info settings.
- Store the token via an iOS-side Settings screen instead of typing it on
  the Watch, if App Groups turn out to work fine on the free tier (worth
  testing before committing to that vs. this simpler approach).

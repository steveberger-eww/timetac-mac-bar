# TimeTacBar

A small macOS menu bar app for [TimeTac](https://www.timetac.com/): clock in, take a break, switch
task and clock out without opening the web app. The status item shows what you're doing and how
long you've been doing it.

```
●  2:14      working, 2h14m elapsed
⏸  0:12      on a break
○            clocked out
```

Requires macOS 14 or later.

---

## Contents

- [How signing in works](#how-signing-in-works)
- [Getting API credentials](#getting-api-credentials)
- [Quick start](#quick-start)
- [Configuration](#configuration)
- [Make targets](#make-targets)
- [Giving it to a colleague](#giving-it-to-a-colleague)
- [Signing and notarisation](#signing-and-notarisation)
- [Trying it without a TimeTac account](#trying-it-without-a-timetac-account)
- [Troubleshooting](#troubleshooting)
- [How the session is kept](#how-the-session-is-kept)
- [Notes on the TimeTac API](#notes-on-the-timetac-api)
- [Development](#development)

---

## How signing in works

Setup comes in two halves, and keeping them apart is the whole point:

| | What it is | Who sets it | How often |
|---|---|---|---|
| **Company setup** | Account name, server, OAuth client ID + secret | Once, by whoever builds the app | Once |
| **Sign in** | Username and password | Each person, for themselves | Once, then remembered |

TimeTac issues **one client ID/secret pair per company account**, not per person — the same pair
works for you and every colleague. That's why it isn't on the login screen. Bake it into the build
(see [Configuration](#configuration)) and everyone else sees exactly what the web asks for: a
username and a password.

The web never asks for a client ID/secret either, because TimeTac's own web app ships one inside its
JavaScript bundle. This does the same thing.

## Getting API credentials

1. **Enable API access** for the company account, if it isn't already. Email
   **support@timetac.com** — it's free and usually takes under two business days.
2. **Create the pair** yourself in TimeTac: **Settings → API Credentials → Create**.

You give the credentials a name and an **expiry date**. Note it down. Once it lapses, sign-in fails
with *"client ID or client secret wasn't accepted"* with nothing else having changed.

## Quick start

```sh
cp .env.example .env     # fill in account + client ID/secret
make run                 # build, bundle, launch
```

Then click the menu bar icon → **Sign in**, and enter your normal TimeTac username and password.

To launch at login, drag `TimeTacBar.app` to `/Applications` and add it under
System Settings → General → Login Items.

## Configuration

Everything local lives in `.env`, which is gitignored because it holds the client secret. Start from
`.env.example`:

```make
TIMETAC_ACCOUNT       = yourcompany
TIMETAC_HOST          = api.timetac.com     # or api-sandbox.timetac.com
TIMETAC_CLIENT_ID     = CLIENT__API_USER_XXXXX
TIMETAC_CLIENT_SECRET = ...

CODESIGN_IDENTITY     = Apple Development: you@example.com (TEAMID)
NOTARY_PROFILE        = TimeTacBar          # only for `make notarize`
```

`make bundle` writes the four `TIMETAC_*` values into the app's `Info.plist`. That puts the client
secret inside the app — which is exactly what TimeTac's web app does with its own, and it is useless
without somebody's real login.

Skip the file entirely and the app asks for the same values on first run, under **Company setup**.
Values entered there go to the Keychain instead; a baked-in secret never touches the Keychain, so
rotating an expired one is a rebuild and nothing else.

## Make targets

| Target | What it does |
|---|---|
| `make build` | `swift build` only — no bundle |
| `make bundle` | Assemble and sign `TimeTacBar.app` (the default target) |
| `make run` | Build, bundle, launch |
| `make run-mock` | Launch against an in-memory fake — no credentials, no network |
| `make test` | 47 tests |
| `make probe` | Read-only connectivity check against the live account |
| `make artwork` | Redraw the app icon and disk image backdrop |
| `make dmg` | Drag-to-Applications disk image |
| `make share` | Zip the bundle instead |
| `make notarize` | Send the disk image to Apple and staple the ticket |
| `make release` | `test` → `dmg` → `notarize` → `verify` |
| `make verify` | What Gatekeeper makes of the current build |
| `make identities` | List available signing certificates |
| `make clean` | Remove build output and release artefacts |

## Giving it to a colleague

Fill in `.env` first, so the company setup is baked in and they never see the setup screen. Then:

```sh
make dmg      # TimeTacBar.dmg — drag-to-Applications window
make share    # TimeTacBar.zip — same app, less ceremony
```

`make dmg` builds the app, draws the icon and backdrop, then mounts the image and has Finder lay the
window out: app on the left, Applications folder on the right, arrow between. The layout lives in a
`.DS_Store`, and only Finder can write one — so the first run may ask for permission to control
Finder (System Settings → Privacy & Security → Automation). Refuse it and you still get a working
image, just with the default icon arrangement.

Their credentials go into their own Keychain. Nothing is shared but the app.

## Signing and notarisation

**This is what decides whether a colleague can just double-click.**

macOS quarantines anything arriving by browser, email, Slack or AirDrop. A quarantined app that
isn't notarised gets blocked, and [since macOS 15 the old Control-click → Open trick no longer
works](https://developer.apple.com/news/?id=saqachfa) — the recipient has to go to
**System Settings → Privacy & Security**, find the blocked app and click **Open Anyway**.

To avoid that entirely you need a **Developer ID Application** certificate (Apple Developer Program,
paid) and notarisation. An *Apple Development* certificate is not enough — it's for running on your
own machines, and Gatekeeper rejects it for distribution.

Once you have one:

```sh
# One-off: store an app-specific password for notarytool
xcrun notarytool store-credentials TimeTacBar \
  --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
```

Put `CODESIGN_IDENTITY = Developer ID Application: You (TEAMID)` and `NOTARY_PROFILE = TimeTacBar`
in `.env`, then:

```sh
make release
```

That runs the tests, signs the app with a hardened runtime and secure timestamp, builds and signs
the disk image, submits it to Apple, staples the ticket, and prints the Gatekeeper verdict. A
stapled image opens on a double-click on any Mac, offline included.

**Without a Developer ID**, the options are:

- Tell them: System Settings → Privacy & Security → **Open Anyway**. Once per app.
- Or have them strip the quarantine flag: `xattr -dr com.apple.quarantine /Applications/TimeTacBar.app`
- Or hand it over by a route that never sets the flag — a USB stick, a network share, or letting
  them clone this repo and run `make run`.

Either way, set `CODESIGN_IDENTITY` in `.env` to a real certificate. An ad-hoc signature is
regenerated on every build, and the Keychain binds each stored item to the identity that wrote it —
so ad-hoc builds re-prompt for Keychain access constantly, and a refused prompt looks exactly like
the app losing its setup.

## Trying it without a TimeTac account

The whole app runs against an in-memory fake, so you can look around before API access is granted:

```sh
make run-mock
```

## Troubleshooting

**Start with `make probe`.** It signs in, resolves your user and reports your status, path style and
task counts, and it performs **no writes** — it cannot touch your timesheet.

```sh
make probe
```

Credentials come from `.env`, then the saved configuration, then the Keychain. You can also pass
them inline:

```sh
TIMETAC_ACCOUNT=yourcompany TIMETAC_CLIENT_ID=... TIMETAC_CLIENT_SECRET=... \
TIMETAC_USERNAME=... TIMETAC_PASSWORD=... make probe
```

| Symptom | Cause |
|---|---|
| *"macOS wouldn't release the saved client secret"* | The app was rebuilt with a different signature. Set `CODESIGN_IDENTITY` in `.env`, or re-enter the secret under Company setup — that rewrites the Keychain item under the current identity |
| *"client ID or client secret wasn't accepted"* | The credentials expired, or belong to a different account |
| *"No TimeTac account by that name"* | Wrong account name. It's the segment after the slash in `https://go.timetac.com/yourcompany` |
| *"Take a break" does nothing* | The account has no task flagged `is_nonworking`. See below |

## How the session is kept

Sign-in uses the OAuth password grant, which returns an access token and a refresh token. The
refresh token and — with **Stay signed in** — your password go into the macOS Keychain, along with
the client secret if you typed it in rather than baking it into the build. Nothing secret is written
to disk anywhere else.

On launch, and whenever a request comes back unauthorised, the app refreshes the access token. If
the refresh token has expired or been revoked it falls back to the stored password and signs in
again. That fallback is what stops TimeTac logging you out every day. Turn **Stay signed in** off
and only the refresh token is kept, so you'll re-enter your password when it eventually expires.

Signing out clears the refresh token and password but leaves the company setup alone, so the next
sign-in is still just a username and a password.

## Notes on the TimeTac API

Built against TimeTac's OpenAPI v4 spec (`https://docs.timetac.com/swagger_files/v4.yaml`).

- Base URL is `https://api.timetac.com/{account}`; the sandbox is `api-sandbox.timetac.com`.
- Resource paths are `{base}/V4/{resource}/{action}/` — the `V4` segment is uppercase.
- Failed calls come back as **HTTP 200 with `Success: false`**, so the status code alone is not a
  success check. `TimeTacClient` always inspects the envelope.
- Filtering is `?field=value` for equality; anything else needs a companion `_op__field=gteq` item.
- **There is no pause endpoint.** A break is an ordinary time tracking on a task flagged
  `is_nonworking`, which is what *Take a break* starts. If the account has no such task, the app
  says so rather than failing silently.
- Every grant type needs `client_id` **and** `client_secret`; there is no public or PKCE client
  documented, so a browser-based login isn't currently an option. TimeTac's JS client library does
  carry an `authorization_code` variant with `code_verifier` and an optional secret, so the server
  may support it for clients they issue a redirect URI to — worth asking support about if you'd
  rather not handle passwords at all. It would also cover colleagues who sign in via SSO, for whom
  the password grant can't work.
- Two things can't be settled from the spec and are resolved at runtime: the endpoint for *who am I*
  (`users/me`, with a fallback to matching on username) and whether the account wants `V4/` or
  `userapi/v4/` paths. Whichever works is remembered.

## Development

```
Sources/TimeTacKit    All logic. No SwiftUI — unit tested end to end.
  API/                Endpoints, envelope decoding, the live and mock clients
  Auth/               Keychain wrapper and the OAuth token store
  Model/              AppState (the observable store) and presence mapping
  Support/            Configuration, baked-in defaults, diagnostics, formatters
Sources/TimeTacBar    App shell and SwiftUI views
Scripts/              Artwork generator and the disk image builder
Tests/                47 tests
```

```sh
make test
```

Tests drive `AppState` against `MockClient`, so clock-in, break, task switching and clock-out are
covered without a network. The icon and disk image backdrop are drawn by `Scripts/Artwork.swift`
into `.build/artwork`, so there are no binaries in the repo — `make artwork` redraws them.

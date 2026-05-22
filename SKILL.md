---
name: worship-setlist-to-spotify
description: "Build or refresh a rolling Spotify practice playlist from the upcoming Planning Center worship setlist. Use when the user mentions a worship setlist, Planning Center plan, church practice playlist, or wants to sync this week's songs to Spotify. Triggers on: 'worship playlist', 'setlist', 'planning center', 'PCO setlist', 'practice playlist', 'church songs to spotify', 'sunday setlist', 'set up worship skill', 'install worship skill', 'first-time setup'."
---

# Worship Setlist → Spotify Practice Playlist

Sync the upcoming worship setlist from Planning Center into a single rolling Spotify practice playlist. Artist version matters. Old tracks get replaced (add-then-prune), never appended.

## When to Apply

User asks to build, update, or refresh their worship practice playlist for the upcoming service. Input may be a PCO plan URL, a pasted song list, a screenshot of the schedule, or just "build this week's playlist."

## Setup Mode (first run / explicit setup)

Enter Setup Mode when ANY of:
- `~/.config/worship-skill/config.json` does not exist
- User says "set up", "install", "first time", "configure worship skill", or passes `--setup`

Setup Mode replaces reactive pre-flight: do the full prereq check upfront and print the complete ordered manual-step list **before** the user clicks anything, so they see total scope.

### Step 1 — Deterministic prereq check

Run the bundled `scripts/setup.sh` from the repo if the user cloned it, OR shell out directly:

```bash
node -v && npm -v && git --version
```

Require Node 18+. If any tool is missing, halt with install hints (macOS: `brew install node git`; Linux: use distro package manager). Do not continue until all three are present.

### Step 2 — Print the full plan upfront (verbatim)

```
Worship Setlist → Spotify setup will require these steps in order:

  1. Clone + build the Spotify MCP server
       git clone https://github.com/marcelmarais/spotify-mcp-server
       cd spotify-mcp-server && npm install && npm run build

  2. Create a Spotify developer app
       → developer.spotify.com/dashboard → Create app
       → Redirect URI: http://127.0.0.1:8888/callback
       → Copy client ID + secret into spotify-mcp-server/spotify-config.json
       → Run `npm run auth` in that repo (browser flow)

  3. Register the built Spotify MCP server with Claude Code
       → Add it to your Claude MCP config (claude mcp add ...)

  4. Create a Planning Center Personal Access Token
       → api.planningcenteronline.com/oauth/applications → Personal Access Tokens

  5. Pick (or create) the rolling Spotify playlist to overwrite weekly

  6. Pick the PCO service type (e.g. "Praise Team", "Sunday AM")

Steps 1–4 are browser/terminal work outside Claude. Steps 5–6 happen here.
```

### Step 3 — Walk through interactively, persisting as you go

Work down the list. For each step:
- Wait for the user to confirm completion before moving on.
- The instant a credential/ID is obtained, write it to `~/.config/worship-skill/config.json` (don't batch — partial progress should survive a crash).
- After PCO PAT is saved, fetch `GET /services/v2/service_types` and present the list — let the user pick by number; save both `pco_service_type_id` and `pco_service_type_name`.
- After playlist ID is provided, verify it's writable by calling `getPlaylist` and confirming `owner.id` matches the authenticated user. Reject public/non-owned playlists with a clear message.

### Step 4 — Dry-run verification

Before declaring setup complete:
1. Fetch the next plan (no mutations).
2. List the parsed song titles.
3. Confirm with the user that the service type is wired correctly.

Only then mark setup done. Tell the user to re-invoke the skill to actually sync.

## Pre-Flight (every run, in order — stop on first miss)

| Check | How to verify | If missing |
|-------|--------------|------------|
| Config file | `~/.config/worship-skill/config.json` exists | Create with `{}`; populate the rest of the checks |
| Spotify MCP available | `searchSpotify` tool listed | Walk user through `git clone https://github.com/marcelmarais/spotify-mcp-server`, `npm install && npm run build`, add to Claude MCP config |
| Spotify auth | Probe with `getMyPlaylists` (read-only, cheap). If 401, re-auth | developer.spotify.com → create app → put client ID/secret + redirect URI `http://127.0.0.1:8888/callback` into the MCP repo's `spotify-config.json` → run `npm run auth` (browser flow) |
| PCO PAT | Probe `GET /services/v2/me` with HTTP Basic `app_id:secret` | api.planningcenteronline.com/oauth/applications → Personal Access Tokens → create → save into config |
| Rolling playlist ID | `config.json` has `spotify_playlist_id` | Ask user for the playlist URL/ID once; save it |
| Service type ID + name | `config.json` has `pco_service_type_id` AND `pco_service_type_name` | Hit `GET /services/v2/service_types`; ask user which one (e.g. "Sunday AM"); save both |

After pre-flight passes, ALWAYS print: `Pulling from '<pco_service_type_name>' — change?` so a stale cache (church added a new service type) is caught immediately.

Never probe auth with a write call. A 401 on `removeTracksFromPlaylist` leaves a half-modified playlist.

## Workflow

### 1. Get the setlist

Source priority:
1. **PCO API** if PAT configured (default path)
2. **Pasted text** if user provided a list
3. **Screenshot** — extract via vision

PCO call shape (HTTP Basic auth: `app_id:secret`):
```
GET /services/v2/service_types/{stid}/plans?filter=future&order=sort_date&per_page=1
GET /services/v2/service_types/{stid}/plans/{plan_id}/items?include=song,arrangement
```

**Filter `item_type == "song"` client-side.** PCO does not filter server-side. Drop Welcome, Communion, Announcements, prayer items. Show the parsed song list to the user — confirm count matches expectation. If the plan returns zero song items, ask whether the right service type is cached.

### 2. Resolve songs → Spotify tracks (single batch approval)

Goal: ONE batch approval at the end, not N per-song asks.

For each song:
1. Check `config.json` → `artist_preferences[title]`. If cached, use as the artist filter.
2. Else use the PCO `Arrangement.name` as a hint if present (often "Bethel - Goodness of God"-style free text — propose, don't blindly trust).
3. Else fall back to title alone. Only ask the user inline if the title is famously ambiguous ("How Great Is Our God" — Tomlin vs Hillsong).
4. Call `searchSpotify` with `q=track:"<title>" artist:"<artist hint>"`. Prefer studio over live. Hold top pick + 2 alternates.

Never use PCO `Song.author` as the Spotify artist filter — that field is the songwriter, not the recording artist your church covers.

If `searchSpotify` returns **zero results** for a song: surface to user with options (a) retry with alternate artist, (b) skip song, (c) paste manual track URI. Never silently drop.

On 429 (rate limit): honor `Retry-After`. If the wait exceeds 10s, surface to user.

Present the full candidate table — Title / Artist / Spotify URL — with the 2 alternates inline for low-confidence picks. Require explicit approval before Step 3. On approval, persist any newly chosen artists to `artist_preferences`.

### 3. Replace playlist contents (add-then-prune)

Order matters. Add new tracks first, then remove old. The playlist transiently holds both but is never empty — reverse order can wipe the playlist if the add call fails mid-flow.

1. Fetch current track URIs from `spotify_playlist_id`.
2. `addTracksToPlaylist` with approved URIs. **Chunk ≤100 URIs per call.**
3. Verify add: re-fetch and confirm new URIs are present.
4. `removeTracksFromPlaylist` for the old URIs. **Chunk ≤100 per call.**
5. Verify final state: track count == approved list length. Report diff (added / removed).

If step 4 fails partway: stop, report exactly which old URIs still need removal. Duplicates are recoverable; an empty playlist 20 minutes before practice is not.

## Anti-Patterns

| Don't | Why |
|-------|-----|
| Create a new dated playlist ("Worship 5/25") | One rolling playlist by design — duplicates clutter the library |
| Add the first search result without confirming | Wrong artist/version is the #1 failure mode for worship covers |
| Treat every PCO plan item as a song | Welcome/Communion/Announcement are plan items too |
| Use the PCO Song `author` field as the Spotify artist | `author` is the songwriter, not the recording artist |
| Remove old tracks before adding new ones | If add fails, the playlist is empty before practice |
| Probe Spotify auth with a write call | A 401 on a destructive call leaves a half-modified playlist |
| Grab "the next plan" globally | Always scope by cached `service_type_id`; confirm the name each run |
| Skip pre-flight on "just refresh it" requests | Tokens expire; assumptions rot; pre-flight is cheap |

## The Bottom Line

One rolling playlist. Artist/version chosen by the user, cached for next time. Add-then-prune (sequenced for safety, not atomic). Chunk to ≤100 URIs per call. Filter PCO items to songs only. Pre-flight every run; confirm service-type by name.

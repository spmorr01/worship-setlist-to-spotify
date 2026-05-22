# Worship Setlist → Spotify

A [Claude Code](https://claude.com/claude-code) skill that syncs the upcoming worship setlist from [Planning Center Online](https://planningcenteronline.com) into a single rolling Spotify practice playlist.

Built for worship team members who get the week's plan via PCO and want to practice along to the actual recorded versions — without manually building a new playlist every week.

## What it does

- Pulls the next service plan from your PCO "Praise Team" (or whichever) service type.
- Filters PCO plan items to songs only — ignores Welcome, Communion, Sermon, etc.
- Resolves each song to a specific Spotify track, preferring studio over live and asking you to confirm artist/version when ambiguous.
- Replaces the contents of one rolling Spotify playlist using an add-then-prune sequence (the playlist is never empty mid-sync).
- Caches your artist choices so next week skips the "which version?" question for repeat songs.

## Requirements

- macOS or Linux
- Node.js 18+, npm, git
- [Claude Code](https://claude.com/claude-code) (CLI or any client that supports skills + MCP)
- A Spotify account + a [Spotify developer app](https://developer.spotify.com/dashboard) (free)
- A Planning Center account with access to the service type you want to track
- A PCO [Personal Access Token](https://api.planningcenteronline.com/oauth/applications)

## Installation

```bash
git clone https://github.com/<you>/worship-setlist-to-spotify ~/Projects/worship-setlist-to-spotify
cd ~/Projects/worship-setlist-to-spotify
./scripts/setup.sh
```

`setup.sh` checks Node/npm/git, creates `~/.config/worship-skill/config.json` from the template, and symlinks `SKILL.md` into `~/.claude/skills/worship-setlist-to-spotify/` so Claude Code picks it up.

The script stops there and prints the remaining manual steps:

1. Clone + build the [Spotify MCP server](https://github.com/marcelmarais/spotify-mcp-server).
2. Create a Spotify developer app and run that repo's `npm run auth`.
3. Register the built MCP server with Claude Code (`claude mcp add ...`).
4. Create a PCO Personal Access Token.

Once those are done, open Claude Code and say "set up worship skill" (or just "build this week's playlist"). The skill detects partial config and runs the rest of setup interactively: PCO PAT → service type pick → playlist pick → dry-run.

## Usage

After setup, any of these invocations work:

- "Build this week's worship playlist"
- "Sync the setlist"
- "Refresh my church practice playlist"
- Pasting a PCO plan URL, song list, or screenshot

The skill will:

1. Fetch the next plan from your cached service type.
2. Show you the song list + the Spotify track it picked for each (with 2 alternates inline when low-confidence).
3. Wait for your approval as a batch — not one song at a time.
4. Add new tracks, verify, then remove the old ones.

## Configuration

User config lives at `~/.config/worship-skill/config.json`. It is **never committed** — `.gitignore` excludes it. Schema:

| Key | What it is |
|-----|-----------|
| `pco_app_id` | Your PCO Personal Access Token's App ID (the first half before the colon) |
| `pco_secret` | The PAT secret (second half) |
| `pco_service_type_id` | Numeric ID of the service type to track (e.g. "Praise Team") |
| `pco_service_type_name` | Human-readable name — printed on every run for safety |
| `spotify_playlist_id` | The rolling playlist's Spotify ID (from the share URL) |
| `artist_preferences` | `{ "Song Title": "Artist Name" }` map, auto-populated as you confirm picks |

If you switch churches or change service types, just edit the two `pco_service_type_*` fields and the next run will follow.

## Design choices

- **One rolling playlist, not a new one per week.** Keeps your library clean.
- **Add-then-prune, never the reverse.** The playlist is transiently larger but never empty — if the add call fails for any reason, your old playlist is still intact.
- **Artist picks require confirmation.** Wrong-version is the #1 failure mode for worship covers (Tomlin vs Hillsong "How Great Is Our God", etc.). One batch approval, then the choices are cached.
- **PCO `Song.author` is ignored as a Spotify artist filter.** That field is the songwriter, not the recording artist your church covers — using it surfaces obscure covers instead of the canonical version.

See [SKILL.md](./SKILL.md) for the full agent-facing spec — anti-patterns, error-recovery rules, and pre-flight checklist.

## Contributing

Issues and PRs welcome. The skill itself is a single markdown file; changes there should be tested by invoking the skill in a real Claude Code session against a throwaway playlist.

## License

MIT — see [LICENSE](./LICENSE).

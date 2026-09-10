# Anno

A music guessing game with QR cards. Scan a card, the app looks up the year
behind it, draws a song from that year out of the chosen category and hands it
to Spotify. The group guesses the year, a button reveals it, and points are
given with a tap on a player tile.

## Running it

```sh
flutter run -d chrome   # browser, the target platform
flutter run             # Android/iOS device or emulator
flutter test            # game logic, year database, catalogs, dialogs
flutter analyze
flutter build web        # output in build/web

# with the in-app player, see "Playing in the tab"
flutter run -d chrome --web-hostname=127.0.0.1 --web-port=8080 \
  --dart-define=SPOTIFY_CLIENT_ID=<client id>
```

There are two ways a song reaches the room. By default the app hands Spotify a
link and gets out of the way - no login, no SDK, no developer dashboard, and
whether the song starts right away or the track page just opens is up to
Spotify. On the web it can instead play the song **inside the game tab**, which
needs Spotify Premium and a login; see [Playing in the tab](#playing-in-the-tab).
The link is always the fallback: everything works without the second way.

## On the web

The browser is the main target, and three things work differently there.

**Camera.** `getUserMedia` only runs on `https://` or on `localhost`. On plain
HTTP the scanner stays black - the code can still be typed in by hand. The
barcode reader itself uses the browser's own `BarcodeDetector` where it exists
(Chrome, Edge, Android) and otherwise pulls zxing from `unpkg.com` at runtime,
so the first scan on Firefox or Safari needs a network connection.

**Opening Spotify.** Custom schemes are out: `url_launcher` only knows http(s)
in the browser, so the web build always uses `https://open.spotify.com/track/…`
and opens it in a new tab, which keeps the game tab and its scores alive.

**Popup blocking.** Browsers only open a tab for a short window after a user
gesture, and the scan that starts a round is not one of them - Chrome and
Firefox usually still allow it, Safari often does not. A blocked popup is
invisible to the app (`window.open` reports nothing back through `noopener`), so
the round screen carries an "Open in Spotify" button; the tap on it counts as
the gesture the browser wants. The in-app player sidesteps this entirely, since
no tab is opened at all.

Coming back to the tab reveals the year as it does on a phone: Flutter's web
engine turns `focus` and `visibilitychange` into the lifecycle events the game
listens to. If the new tab opens in the background without taking focus, no such
event arrives - "Reveal now" is there for that.

## Playing in the tab

On the web the app can be the player itself instead of sending the song to
Spotify. Spotify's Web Playback SDK turns the game tab into a Spotify Connect
device: the song comes out of the page, nobody switches away, nothing has to be
switched back, and the popup blocker is out of the picture. The reveal then
waits for the "Reveal now" button, which is what that button was already there
for.

It costs three things, and all three are why it is off by default:

- **Spotify Premium.** The SDK refuses free accounts. The app catches that as
  `account_error` and says so on the setup screen.
- **A login.** Authorization Code with PKCE, so no client secret is involved -
  a browser cannot keep one. The refresh token lives in `localStorage`.
- **A registered app.** Client id from the developer dashboard, compiled in
  with `--dart-define=SPOTIFY_CLIENT_ID=...`. Without it the card on the setup
  screen never appears and nothing changes.

The card asks for the login and reports what went wrong when it fails. Once it
works the card disappears - a permanent "Spotify is connected" panel would say
nothing every game night - and the way back out becomes **Disconnect Spotify**
in the app bar menu.

Set the redirect URI in the dashboard to exactly what the app sends, which is
origin plus path. Two of them are needed: `http://127.0.0.1:8080/` for the dev
command above and `https://anno.jakobhoeflich.com/` for the deployed page. Only
the custom domain, not the `github.io` address - that one only redirects, so a
login never comes back to it. Prefer the loopback IP over `localhost`: Spotify only accepts `https` and
loopback literals, and which spelling counts has changed over the years. In
production the page has to be on `https` anyway, both for the SDK and for the
camera.

One browser caveat on top of the ones above: the SDK plays through the
browser's DRM stack (Widevine), so a build without it - some Linux Chromium
packages, Firefox with DRM switched off - fails at `initialization_error`. The
setup screen shows the reason and the link handover keeps working.

The catalog is not in the way here. An entry without `spotifyTrackId` is looked
up through the Spotify search first and played from that, so a song plays even
before the resolver has run.

## Deploying to GitHub Pages

`.github/workflows/pages.yml` builds the web app on every push to `main` and
publishes it to `https://anno.jakobhoeflich.com/`. The `github.io` address of
the repository stays valid but only 301s there, which is why the build runs
with `--base-href /` and not with a repository path.

The Flutter version there is pinned, and **3.38.6 is the floor**: older web
engines leave the view at the keyboard's size after the on-screen keyboard
closes, so a player who types a name into an Android browser is left with a
dead strip at the bottom of the page (flutter/flutter#175074).

The custom domain needs two halves that are easy to have only one of: the name
in **Settings -> Pages**, and a DNS record `anno` -> `jkbhf.github.io` at the
registrar. `web/CNAME` carries the name into every build so a deploy cannot
quietly drop it. Until the DNS record answers, the domain is set but nothing
resolves.

Two more things are set once and then forgotten:

- **Settings -> Secrets and variables -> Actions -> Variables**, a repository
  variable `SPOTIFY_CLIENT_ID`. A *variable*, not a secret: the client id ends
  up in the compiled bundle either way, so hiding it buys nothing, and a masked
  secret only makes the build log harder to read. Without it the build still
  succeeds and the page simply has no in-app player.
- **The redirect URI** in the Spotify dashboard, see above.

The client *secret* has no business here. It belongs to the resolver script and
lives in the environment; a PKCE login in a browser must never carry one.

## The flow

1. **Setup** - enter player names, pick the score target (5, 10, 15 or free).
   The names of the last group are already in the fields; they are saved when a
   game starts and outlive it, so the next evening begins where the last one
   left off.
2. **Categories** - which decks to play from. Several can be picked; each round
   then draws from one of them at random, and every deck has the same chance
   regardless of how many songs it holds for that year. Categories without songs
   cannot be selected.
3. **Game** - scan a card and the song starts. The screen that follows is the
   scoreboard with a "Reveal the year" button where the song card will be: the
   scores are up while the group guesses, but the year, the title and the
   artist are not. The button swaps the song card in and opens up scoring - a
   tap on a tile gives a point, a long press takes one away. "Next round" leads
   back to the scanner. Once someone reaches the score target, the game ends
   after the current round.

Between the scan and the song there is a three second countdown, and only on
the way that hands the song over to Spotify. That way the music starts in
another app or another tab, while the room is still looking at the phone - the
countdown is what puts everybody on the same beat, and the close button on it
drops the round before a note is played. Playing in the tab skips it: the song
is there as soon as the round screen is, so a countdown would only hold it up.
Which of the two is coming is the one thing the app reads off the session
instead of off the launch - there is no launch yet at that point, and guessing
wrong costs a countdown, not a round.

On Android, coming back from Spotify still reveals the year by itself; the
button is what does it everywhere else.

The running game is saved after every score change. If Android kills the app
while Spotify is in the foreground, it can be resumed from the setup screen.
That save is cleared when a game ends; the roster in `RosterStore` is not,
which is the whole point of keeping the two apart.

No screen of a running game scrolls. The phone is passed around and tapped by
whoever is holding it, so a tile that has to be scrolled into view is a tile in
the wrong place - with eight players the whole body is scaled down together
instead.

## The two data sources

### Year database: which card means which year

The cards carry a link like
`https://play-the-music.com/de/year/182ca01194a98f0b` on the front and the year
on the back. The key is the last path segment of the link, here
`182ca01194a98f0b`.

`assets/qr_years.json` ships with the app:

```json
{
  "version": 1,
  "years": { "182ca01194a98f0b": 2005 }
}
```

It is maintained in the app under **Year database** (the menu on the setup
screen, or the game menu): scan a card, type in the year from its back,
done. Those entries live locally on the device and take precedence over the
bundled file; through the menu they can be exported as JSON to the clipboard and
imported back from it - that is how a set of cards typed in once travels to the
next device or back into `assets/qr_years.json`.

When the scanner hits an unknown code, the app asks for the year right away and
carries on. A QR code that only contains a year works without an entry too.

### Song catalog: which song belongs to a year and category

One JSON file per category under `assets/songs/`, listed in `categoryAssets`
(`lib/data/song_repository.dart`):

```json
{
  "id": "esc",
  "name": "ESC",
  "description": "Eurovision Song Contest - winners and classics",
  "songs": [
    {
      "year": 2005,
      "title": "My Number One",
      "artist": "Helena Paparizou",
      "spotifyTrackId": "3gSnnBf9fulK2fizqxmsXn",
      "country": "Greece",
      "place": 1,
      "tier": 1
    }
  ]
}
```

`country` and `place` are optional and belong to contest entries. Where they
are set, the reveal names the deck, the country and the rank underneath the
song - `ESC · Greece · 1st place`.

`tier` is the draw weight: `1` is the core of a year and is drawn three times as
often, `2` is its long tail. It defaults to `1` when missing, anything but 1 or
2 is refused at startup. `CLAUDE.md` holds the rule for how many entries a
contest year gets, which ones, and which of them are core.

ESC, German Songs, International Hits and Rock & Pop exist; ESC is filled with
427 entries from 1956 to 2026, International Hits with 580 from 1950 to 2026
and German Songs with 544 from 1950 to 2026 - Rock & Pop is still empty. The intent is at least one
song per year from 1950 to 2026, which ESC cannot reach at the bottom because
the contest did not exist before 1956 - for how many entries a year gets
beyond that, see `CLAUDE.md`. When a year holds several, the
app picks one at random and only repeats it within a game once all the others
have had their turn.

`spotifyTrackId` is the last part of `https://open.spotify.com/track/<id>`.
Without it the app opens a Spotify search for title and artist - the song then
has to be tapped there, which is a round without music until somebody does. It
is what a hand-written entry looks like until the resolver below has run over
it, so run it before the file ships.

The year is the truth of the game and deliberately comes from no API: streaming
services report the year of the re-release for remasters.

**For a contest category `year` is the year of the contest, not of the
release.** A Eurovision entry that came out in December 2004 and competed in May
2005 belongs on the 2005 card - that is the year the room is guessing, and the
year the reveal shows. The resolver script below will flag exactly these entries
as a year mismatch against Spotify; for contest decks that warning is expected.

### Filling in track ids

Enter title and artist by hand, the script fetches the ids:

```sh
export SPOTIFY_CLIENT_ID=... SPOTIFY_CLIENT_SECRET=...
dart run tool/resolve_spotify_tracks.dart            # every category
dart run tool/resolve_spotify_tracks.dart assets/songs/esc.json
```

It only fills empty `spotifyTrackId` fields, and it takes a hit only when
artist and title both line up and the pressing is the recording itself - a
karaoke, medley or nightcore version is refused. What it could not find is
listed under "Not on Spotify": those entries get swapped for another song of
the same year, see `CLAUDE.md`. It also reports every song whose Spotify year
differs from the catalog - usually a remaster, which would put the wrong year
on the card.

```sh
dart run tool/resolve_spotify_tracks.dart --recheck   # ids already in the file
```

`--recheck` reads every id back and clears the ones that turned out to be a
different song, so the next plain run can fill them in properly.

Client id and secret come from the
[Spotify Developer Dashboard](https://developer.spotify.com/dashboard); the
client credentials flow is enough for the search, no user login needed. Spotify
answers a burst of requests with a lockout of several hours for the whole app -
the script spaces its requests out and stops on a `429` instead of waiting it
out, so run it once and let it finish rather than restarting it.

## Layout

```
lib/
  models/       Song, SongCategory, GamePlayer
  data/         song catalogs, year database, saved game, last roster
  game/         GameController - the round state
  music/        handover to Spotify: link, or the in-app player on the web
  ui/           setup, category, game, scanner, year database
assets/
  qr_years.json   bundled card -> year mapping
  songs/          one catalog per category
tool/           resolve_spotify_tracks.dart
```

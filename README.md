# Anno

A music guessing game with QR cards. Scan a card, the app looks up the year
behind it, draws a song from that year out of the chosen category and hands it
to Spotify or YouTube Music. The group guesses the year, a button reveals it, and points are
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

**YouTube Music** is the other service, picked under "Play songs in" on the
setup screen and kept per device. It only has the first way: the app opens
`https://music.youtube.com/watch?v=<id>`, which Android and iOS hand to the
YouTube Music app and the browser opens in a tab, and the countdown runs before
every round. There is no player in the tab on purpose, see `CLAUDE.md`.

## On the web

The browser is the main target, and three things work differently there.

**Camera.** `getUserMedia` only runs on `https://` or on `localhost`. On plain
HTTP the scanner stays black - the code can still be typed in by hand. The
barcode reader itself uses the browser's own `BarcodeDetector` where it exists
(Chrome, Edge, Android) and otherwise zxing-wasm, which the page serves itself
from `web/zxing/` - `mobile_scanner` would fetch it from jsDelivr, and the
Content-Security-Policy in `web/index.html` does not let it. The files there are
`dist/iife/reader/index.js` (as `reader.js`) and
`dist/reader/zxing_reader.wasm` of the zxing-wasm version `mobile_scanner`
pins in `lib/src/web/web_library_versions.dart`: 3.1.1 for `mobile_scanner`
7.4.0. `mobile_scanner` is pinned exactly for that reason; upgrading it means
replacing both files with the matching version.

The button in the bottom left corner of the scanner turns the camera around,
where the device has two of them - the back one for a card held up to it, the
front one for a phone lying on the table between people. The side is kept per
device (`CameraFacingStore`), because every scan builds a controller of its
own and a flip that was not kept would last one card.

The camera runs only while a scanner is on screen. `mobile_scanner` 7.4.0
never stops a camera stream in the browser - closed, the scanner left the
camera on and opened one more with every scan - so `CameraStreams`
(`lib/ui/camera_streams/`) notes every stream the page opens and stops it
when the scanner goes. A scanner that is still open stops the camera too while
the tab is hidden or the phone is in another app, and starts it again on the
way back.

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

**On a phone it is Spotify Connect instead.** Spotify does not support the SDK
in a mobile browser, so there the app commands the Spotify app the phone
already has: the same position, the same seek, the same words following the
song, only the sound comes out of the other app. It needs the same login and
the same Premium, and it needs the Spotify app to have been open once - until
then there is no device to play to and the round goes out by link, which opens
it. This is what makes a phone usable as the remote control of a television.

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

**Lyrics.** The playing screen and the reveal both carry a **Lyrics** button.
Spotify's Web API has no lyrics endpoint, so the words come from
[LRCLIB](https://lrclib.net) (no key, CORS open); what Spotify adds is the
timing: in a round played in the tab a synced text follows the player, the
line being sung is lit, and a tap on a line seeks there. A synced text whose
length is more than five seconds off the recording is shown as plain words
rather than laid over the wrong cut. In a link round, or on YouTube Music, the
sheet is the words alone. While the room is still guessing the sheet leaves
title and artist off, and two fingers on the sheet make the words bigger or
smaller. A song LRCLIB has no text for says so where the button was, rather
than offering a sheet with nothing in it. On a wide screen there is no button:
the words are on the stage for the whole round, see below.

## On a projector, or a phone turned over

A screen that is wider than tall and big enough to hold two halves gets a
layout of its own - a laptop on a projector, a tablet on its side, a television.
It switches on by itself (`isWideScreen` in `lib/ui/layout.dart`): landscape,
and at least 500 pixels tall, which every laptop and tablet is and no phone
turned over is. A phone sideways keeps the one column and widens it instead.

- **The stage**, on the right, is for the room: the lyrics, large, from the
  first note to the next card, and the scores as one row along the bottom.
  Nothing is ever laid over the words - the answer appears in the column
  instead. Everything there is a share of the height of the picture, so it fits
  a 1080p wall, a 720p one and a phone's 412 pixels alike; up to eight players
  fit a 720p projector.
- **The column**, on the left, is for whoever runs the game, and it has two
  fixed places, both the same width. The box on top is the next thing to do -
  "Scan a card", then "Reveal the year" while the song runs, then the year it
  produced, with title and artist: that box is where the answer lives, so the
  words on the stage are never covered. Its height is dragged by the grip
  under it. The camera sits at the foot: it is off screen while a round plays,
  and comes up by itself at the start of a new game and at every reveal, so the
  next card can go up while the room is still reading the year. It is laid over
  what is under it rather than pushing it up. The card just played is ignored
  while it does - only a new card starts the next round. In between: during a
  round "Open in Spotify" and the swap, and at the foot the keys. The menu sits
  in the corner of the screen and carries the way out of the game - this layout
  has no app bar.
- **The player** is a band along the bottom, under both halves: pause, ±10
  seconds, back to the start, jump to the middle, and the track across the rest
  of the screen. Only an in-app Spotify round has one - a song handed over by
  link is out of reach, and then the words get the band's height instead.
- **"Sync the words"** in the menu is for casting a screen: the picture arrives
  at the wall later than the sound does out of the laptop, so the words run
  ahead by that much. It is a mode, not a dialog - the song and the words keep
  running while it is on, which is the only way to tell whether the number is
  right. The arrows appear in the column (on a phone, in the round itself) and
  step 100 ms at a time; `Ctrl` with `+`/`D` and `-`/`A` does the same from the
  keyboard, and the number says itself over the screen for a moment after every
  step. Kept on the device.
- **The size of the words**: two fingers on the words - the list holds still
  while they are on it, and the step is damped, so the size is walked up to
  rather than jumped past - or "Bigger words" and "Smaller words" in the menu
  for a screen with no touch. Kept on the device,
  so the same room gets the same size next time. The menu itself is the icon in
  the top right corner of the screen.
- **The split** between the two halves is dragged: the grip in the gap between
  them widens the column or the stage, and the device remembers where it was
  left.
- **Keys**, on a laptop or a desktop: space plays and pauses, enter reveals the
  year, N is "nobody knows it" and Z takes that swap back, left/A and right/D
  step ten seconds, up/W jumps to the middle of the song and down/S back to its
  start, and `Ctrl` with `+`/`D` or `-`/`A` moves the words against the song.
  They are listed at the foot of the column, and only there - the stage
  is for the room, which has no keyboard. Each is listed only while it does
  something: moving the song needs the in-app player, N needs another song in
  that year, Z needs a swap to take back.
- **"Hide the scores"** in the menu gives the words the whole stage, on the
  phone too. There is then nothing to tap, so no points are counted and the
  game runs until you stop it - which is the point of it. The scores are kept
  and come back when they are shown again.

**Play through the tab.** The link path does work on a projector, but it gives
the answer away: Spotify opens in a new tab with title and cover on the wall,
and coming back to the game tab reveals the year. With
[Playing in the tab](#playing-in-the-tab) the song never leaves the page, the
lyrics follow it, and the year waits for the button. For the most room, put the
browser in fullscreen - F11, or "Fullscreen" in the menu, which is also the way
to get a phone's browser bars out of the picture.

## On a television, with the phone as the remote

A Samsung or LG television has a browser, and that browser is a Chromium from
a few years ago on a slow chip - but it has nothing to compute here. It opens
the page, presses **This screen is the television**, and from then on it only
draws what the phone sends it: the landscape layout above, the words, the year,
the scores, the player's band along the bottom. Everything else stays on the
phone, which is also where the music comes from and where every control is.

How an evening goes:

1. On the television, open the page, press the cast button in the app bar and
   then **This screen is the television**. It shows six digits.
   (Fullscreen is offered right there, which is the one moment somebody is
   standing in front of it with a remote, and so is the way back out.)
2. On the phone, the same cast button, then **Type the code**, those six
   digits.
3. Start the game as usual. The phone scans the cards, reveals the year, swaps
   a song nobody knows, moves around in it, hands out the points - and the
   television shows the room all of it.

The phone's own layout changes while it is paired: no words, no year card, no
scoreboard during the song. Those are on the wall, and what is left gets the
whole phone instead of a quarter of a landscape screen - the one action of the
round as a panel, the song's controls under it, the tiles at the reveal.

Two things are worth knowing because they are decisions rather than accidents:

- **The size of the words and how far they run ahead of the song belong to the
  television.** The menu entries on the phone send a step, the television
  applies it, and it says the new number over its own words - which is where
  whoever pressed is looking. A second television brings its own settings.
- **Nothing comes back from the television.** It draws and nothing else, so a
  television that reloads, sleeps or is switched off costs no game: it
  reconnects to the code it had and the phone sends it the whole round again.

It needs a relay, because two browsers cannot find each other on their own.
That is `packages/anno_relay`, 200 lines of `dart:io` with no dependencies,
and it has to be reachable over `wss://` - see its README for the systemd unit
and the proxy in front of it. Build with
`--dart-define=ANNO_RELAY_URL=wss://.../`; without it the app has no second
screen in it and nothing else changes.

**The music.** The phone is where the song plays, which on a phone means
Spotify Connect rather than the in-app player - see
[Playing in the tab](#playing-in-the-tab). The Spotify app has to have been
open once for Spotify to list it as a device; until it is, the first round goes
out by link, which opens the app, and every round after that plays here.

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
- A repository variable `ANNO_RELAY_URL`, the `wss://` address of the relay.
  Without it the build succeeds and the page simply cannot pair with a
  television.

The client *secret* has no business here. It belongs to the resolver script and
lives in the environment; a PKCE login in a browser must never carry one.

## The flow

1. **Setup** - enter player names, pick the score target (5, 10, 15 or free).
   The names of the last group are already in the fields; they are saved when a
   game starts and outlive it, so the next evening begins where the last one
   left off.
2. **Categories** - which decks to play from. Several can be picked; each round
   then draws from one of them at random, as often as the number on its card
   says (1-10, the card shows the share in percent) times the songs it holds
   for that year, counted up to ten: a library with 137 songs for a year gets
   no more than a deck with its ten, a year with two gets a fifth of that. A
   deck without a song for the scanned year sits out and the others share its
   part. Categories without songs cannot be
   selected. K-Pop (2016 on), White Girl Music (2007 on), Anthony
   (1999-2024) and Anthony All (1999-2026) cover only part of the years and can still be played alone -
   the card shows the span, and a card outside it only asks for another card.
   **Play without cards** is the switch at the bottom of that screen, for an
   evening where the box of cards is somewhere else. The device then draws the
   year itself out of a range set with the two slider handles - it opens on the
   span of the chosen decks - and the game is the same from there on: a tap
   draws the year, the song plays, the button reveals it, points are given, and
   the next tap draws the next year. Every year of the range comes up once
   before any comes again; when the range is through it says so and starts
   over. Years no chosen deck has a song for are skipped, and the count under
   the slider says how many that leaves.

3. **Game** - scan a card and the song starts. The screen that follows is the
   scoreboard with a "Reveal the year" button where the song card will be: the
   scores are up while the group guesses, but the year, the title and the
   artist are not. The button swaps the song card in and opens up scoring - a
   tap on a tile gives a point, a long press takes one away. "Next round" leads
   back to the scanner. Once someone reaches the score target, the game ends
   after the current round - and "Back to the last round" on the finish screen
   returns to that reveal, for the point that went to the wrong tile.

   A song nobody in the room knows can be swapped while it plays: "Nobody
   knows it — draw another" picks another song of the same year, and the undo
   beside that button brings the last one back. Played in the tab, a
   bar under the reveal panel moves around in the song - drag it, start over,
   ten seconds either way, or straight to the middle.

   The screen stays on during a game (Screen Wake Lock, where the browser has
   it), and the back button asks before it leaves a running game.

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

A game without cards keeps the years it has drawn with the game rather than on
the device: a resume carries on where the range was, and a new game runs the
whole range again.

The running game is saved after every score change, together with the songs it
has played. If Android kills the app while Spotify is in the foreground, or the
game is left by the back button, it can be resumed from the setup screen and
does not start its years over. That save is cleared when a game ends; the
roster in `RosterStore` is not, which is the whole point of keeping the two
apart.

Across games, `PlayedSongsStore` keeps every song this device has played. A
played song only comes back once every other song of its year in its deck has
been heard; then that year starts over. Resetting the scores for a rematch
keeps that memory too.

No screen of a running game scrolls. The phone is passed around and tapped by
whoever is holding it, so a tile that has to be scrolled into view is a tile in
the wrong place - from five players the tiles go into three columns, and what
still does not fit is scaled down together instead. The one exception is the
lyrics on the stage of the wide layout, which scroll by themselves with the
song.

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

**A new batch of cards should carry a plain number as the code**, not a link -
a scanned card still accepts whatever its QR holds, but the manual "Enter
code" field (for a card the camera will not read) opens a phone's number pad
only, which a link cannot be typed on. Any digit string works, so long as it
is not the year itself - the point is a code a glance at the card cannot
guess, not a particular length or shape.

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

ESC, German Songs, International Hits, K-Pop, White Girl Music, Anthony,
Anthony All and Jakob exist; ESC
is filled with 415 entries from 1956 to 2026, International Hits with 576 from
1950 to 2026, German Songs with 535 from 1950 to 2026, K-Pop with 115 from 2016
to 2026, White Girl Music with 200 from 2007 to 2026 and Anthony with 1265
from 1999 to 2024, Anthony All with 2104 from 1999 to 2026 and Jakob with 732
from 1964 to 2026 - K-Pop, White Girl Music and both Anthony decks only cover part of the century. The intent is at least one
song per year from 1950 to 2026, which ESC cannot reach at the bottom because
the contest did not exist before 1956, and K-Pop and White Girl Music do not
try to because what the room knows of them starts later - for how many entries a year gets
beyond that, see `CLAUDE.md`. When a year holds several, the
app picks one at random and only repeats it within a game once all the others
have had their turn.

`spotifyTrackId` is the last part of `https://open.spotify.com/track/<id>`.
Without it the app opens a Spotify search for title and artist - the song then
has to be tapped there, which is a round without music until somebody does. It
is what a hand-written entry looks like until the resolver below has run over
it, so run it before the file ships.

`youtubeVideoId` is the same for YouTube Music, the `v` of
`https://music.youtube.com/watch?v=<id>`. Without it a YouTube Music round
lands on the search.

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

### Filling in YouTube Music ids

```sh
dart run tool/resolve_youtube_music_tracks.dart            # every category
dart run tool/resolve_youtube_music_tracks.dart assets/songs/esc.json
dart run tool/resolve_youtube_music_tracks.dart --only=1971,Chai
dart run tool/resolve_youtube_music_tracks.dart --curl     # when Google blocks Dart
```

After a few thousand searches Google answers the Dart client with its "Sorry..."
page and every search fails with `403`; `--curl` sends the same requests through
curl, which it lets through.

No credentials: it asks the search behind music.youtube.com for songs only,
the same endpoint the web player uses. The matching is the Spotify resolver's,
plus live, acoustic and sped-up takes refused on top, and every hit is printed
on its own line so a wrong one shows up reading down the run. It only fills
empty `youtubeVideoId` fields. What it cannot find stays without an id - no
swap, the catalog is curated against Spotify.

## Layout

```
lib/
  models/       Song, SongCategory, GamePlayer
  data/         song catalogs, year database, saved game, last roster
  game/         GameController - the round state
  music/        handover to Spotify (link, or the in-app player on the web)
                or to YouTube Music (link)
  ui/           setup, category, game, scanner, year database
assets/
  qr_years.json   bundled card -> year mapping
  songs/          one catalog per category
tool/           resolve_spotify_tracks.dart, resolve_youtube_music_tracks.dart
```

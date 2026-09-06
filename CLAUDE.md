# Anno

Music guessing game with QR cards. `README.md` has the flow, the data formats
and the web specifics; this file holds the decisions that cannot be read off
the code or the data.

## How many songs a contest year gets

`assets/songs/esc.json`. The size of a year is a curation rule, not something
to derive from what is already in the file:

| Contest years | Entries per year |
| --- | --- |
| 1956-1974 | winner + the 2 best known entries |
| 1975-2004 | winner + the 4 best known entries |
| 2005-2026 | winner + the German entry + the 8 best known entries |

The years grow towards the present because that is where the cards are: a
session played on a narrow range (2005-2026 is what actually gets played) puts
every round into ~22 years, so a thin year is heard out within two evenings.
`_played` in `GameController` only prevents repeats *inside* one game - it is
cleared for the next one, so across evenings the draw is plain random and the
pool size is what carries the variety.

**"Best known" is the only filter, the place is not one.** The room has to
guess the *year*; a song nobody recognises turns the round into a coin flip.
A famous last place is a better card than an unknown fourth - Lord of the Lost
2023 (26th) or No Angels 2008 (23rd) are punchlines at the reveal, which shows
`ESC · Germany · 26th place`. The same the other way round: take Volare 1958
(3rd), Verka Serduchka 2007 (2nd), Cha Cha Cha 2023 (2nd) without hesitating.

**The German entry.** From 2005 on it is a fixed slot, on top of the eight -
the room grew up with the Vorentscheid, so it is the most guessable card of the
year. For 1956-2004 there is no quota, but the rule is: **take the German entry
whenever a German would probably know it, even when it did nothing
internationally** - Dschinghis Khan 1979 (4th), Guildo Horn 1998 (7th), Stefan
Raab 2000 (5th) all earn a slot on home recognition alone. It counts against
the 2 resp. 4 "best known" slots and beats a foreign entry of the same
standing. Where nobody would know it - most of the 60s and the 90s - skip it.

The catalog is filled from 1956 to 2026, 427 entries. Every future contest
needs its ten, otherwise that card is a dead round in a game played on the ESC
deck alone.

**Years without a contest still get entries.** 2020 was cancelled: use the
entries that never got to compete (Little Big "Uno", German entry Ben Dolic
"Violent Thing") and leave `place` off, otherwise the card is a dead round when
ESC is the only selected deck. 1969 had four winners - one of them is enough.

## Draw weight: `tier`

Within a year not everything should come up equally often. The core of a year
is drawn more often than its long tail:

- **`tier: 1`** - winner, German entry, and the 4 best known of the rest.
  This is the default when the field is missing.
- **`tier: 2`** - the remaining 4 of the eight. Only 2005-2026 has them; the
  smaller years are core all the way through.

So a 2005+ year is 6 tier 1 + 4 tier 2, and a tier 1 song should be drawn about
3x as often as a tier 2 one - roughly 80% of that year's rounds land on the
core. Keep the JSON at "core or tail" rather than a per-song weight, so a year
can still be filled in by hand.

Implemented: `Song.tier` (default 1, anything but 1 or 2 is a `FormatException`
at startup) and `GameController._pickWeighted`. The weighting sits inside the
"prefer unplayed" pass, so within one game every song of a year is still played
before one repeats - the tier decides the *order*, and with it which songs a
year that is only scanned once or twice ever gets to show. The factor is
`_tierOneWeight` in `lib/game/game_controller.dart`, one number to tune.

## Two ways to play a song, one of them optional

`SpotifyLauncher` has two implementations and the choice is not a preference:

- `UrlSpotifyLauncher` hands Spotify a link. Works everywhere, needs nothing.
- `InAppSpotifyLauncher` plays through `SpotifySession` where there is one and
  **falls back to the first** where there is not.

The fallback is the normal case, not an edge case: it is every Android and iOS
build (`spotify_session_stub.dart`), every build without a client id, every
player without Premium, everybody who has not logged in, and - on a deployed
page - everybody outside the 25 accounts of Spotify's development mode. So a
change to the playing screen or the round flow has to keep working without a
session - the widget tests cover both branches. Never make the in-app player a
requirement, and never let a failure in it end a round without music.

**Branch on what the launch did, never on the session.** A session reports
itself `ready` and still refuses a track - one the account cannot play, one the
market does not carry, a device another Spotify Connect client took over. The
song then went out by link while the session went on claiming to be fine, so
`SpotifySession.isReady` is the wrong question on the playing screen: it would
drop the "Open in Spotify" button, which on the web is the only way back to a
popup the browser swallowed. `SpotifyLaunchResult.inApp` is the answer, carried
into `GameController.playingInApp` and read from there. It also decides whether
a `resumed` reveals the year: coming back from Spotify does, tabbing away from
an in-app round does not.

The one exception is the countdown before the round (`_runCountdown` in
`lib/ui/game_screen.dart`), and it is one because nothing has been launched
yet: the countdown covers the handover to Spotify, so it has to know which of
the two ways is coming *before* the launch that could tell it. `isReady` is all
there is at that point, and being wrong there costs a countdown rather than a
round - the fallback still plays the song by link either way. Anything after
the launch reads `playingInApp`.

`README.md` has the setup under "Playing in the tab".

## What Spotify does not carry is not a card

`spotifyTrackId` is not a nicety, it is what makes the round play. Without it
the link path opens `open.spotify.com/search/...` and the song sits there until
somebody taps it - a dead round on the way most players are on. With it, the
deep link `spotify:track:<id>` starts the song by itself on Android and iOS,
and the web at least lands on the track instead of a result list. So an entry
without an id is only half an entry: run `tool/resolve_spotify_tracks.dart`
over a file before it ships (`README.md`, "Filling in track ids").

**An entry Spotify does not have gets swapped, not hunted down.** When the
resolver ends with a song under "Not on Spotify", the fix is to replace that
entry with another one from the *same year* that fits the curation rule above -
the year keeps its slot, the song loses it. Then run the resolver again for the
new entry. This is the normal case for the older years, where the catalogs
simply stop: Katja Ebstein has three songs on Spotify and "Diese Welt" (1971,
3rd) is not one of them, so 1971 takes another entry of that year instead.

Two things follow from it:

- **The winner slot is not exempt.** A winner nobody can hear is worse for the
  evening than a year without its winner. Swap it like any other entry, and
  where the German entry of a 2005+ year is the one missing, the slot goes to
  the next best known entry of that year rather than staying empty.
- **Never substitute a karaoke, tribute, medley, nightcore or remix pressing.**
  Those are what the search offers when the real recording is absent, and the
  room hearing a sped-up cover is a worse round than a swapped song. The
  resolver refuses them on purpose; do not put one in by hand.

**A "no hit" is only worth as much as the query behind it.** The resolver used
to search `track:$title artist:$artist` unquoted, where Spotify takes only the
first word of each field: that put t.A.T.u., Mia Martini and the 2011 winner on
the miss list and answered Blue's "I Can" with Adele. It now quotes the fields,
checks artist, title and pressing on every candidate, and `--recheck` reads the
ids already in a file back. So before swapping a batch of entries, make sure
the list came from the current resolver - otherwise good songs get thrown out
for a bug.

A new category is filled the same way: pick the songs by the curation rule
first, then let the resolver decide which of them can stay.

`README.md` has the commands under "Filling in track ids".

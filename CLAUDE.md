# Anno

Music guessing game with QR cards. `README.md` has the flow, the data formats
and the web specifics; this file holds the decisions that cannot be read off
the code or the data.

## Work on `main`

Commit straight to `main` and push. No branch, no pull request, no waiting
for a review that nobody is going to give - this is a one person repo, and
a PR here only adds a click between a finished change and the deployed
page. The history up to #4 was branched that way; from here it is not.

That does not loosen what has to be true before a commit: `flutter test`
green, and a data change verified against the file it came from rather
than assumed. Pushing to `main` deploys, so the check happens before the
push instead of in a review after it.

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

## How many songs a hit year gets

`assets/songs/international_hits.json`. A contest year has a participant list
as its natural ceiling; a hit year has none, so the size is set:

| Years | Entries per year |
| --- | --- |
| 1950-1979 | 5 |
| 1980-1999 | 8 |
| 2000-2026 | 10 |

Same reason as the ESC table: the deck grows towards the present because that
is where the cards are, and a thin year is heard out within two evenings.

**Why the deck starts at 1950 and ESC at 1956.** ESC has no choice: the first
contest was 1956, there is nothing before it. A hit year has no such floor -
the US year-end charts run from 1946, the UK singles chart from 1952 - so the
bottom is a decision, and it is 1950 because that is what `README.md` promises
the player. It is the weakest end of the deck and it is meant to be: five a
year, all core, and the further down you go the more the room is placing a
decade rather than a year. Below 1950 that stops being a game.

**The measure is the US/UK year-end charts**, not what a German room happened
to hear. That is what makes the deck "international" rather than a second
German one, and it is the line that keeps a decision arguable later: a song
either was in those charts or it was not. Where two songs are equally big, the
one that dates itself wins - a card the room can place to a year beats a
timeless one it can only place to a decade.

**No dedupe against the other decks.** Waterloo, Volare, Euphoria and Satellite
are world hits *and* ESC entries; they stand in both files. Playing both decks
in one evening can draw the same song twice - that is accepted, because
thinning the hit deck to protect ESC would cost the better card in the deck
that has no other claim to it.

**German-language world hits belong here**, not in `german_songs`: 99
Luftballons, Der Kommissar, Rock Me Amadeus, Da Da Da all charted in the US or
the UK, and that is the only test this deck applies. `german_songs` is the deck
for what was big *only* in German-speaking countries.

**The year is the chart year, not the pressing.** A single that came out in
October and topped the charts in February belongs on the later card - that is
the year the room is guessing. This matters more here than for ESC, where the
contest date settles it. Two consequences:

- The resolver's "Check the year by hand" list is **loud** for this deck and
  mostly noise: the only pressing Spotify carries is often a remaster or a
  best-of, so its year is a re-release date. Never move a catalog year onto
  what the API reports.
- **A song that got big again years later is a bad card**, not a two-year one.
  Running Up That Hill (1985, huge again 2022) and Cruel Summer (2019, huge
  again 2023) are left out for that reason: whichever year is on the card, half
  the room is right and cannot be told so.

The catalog is filled from 1950 to 2026, 580 entries. Every future year needs
its ten, otherwise that card is a dead round in a game played on the hit deck
alone. A running year is filled from the number ones so far - that is the only
chart that exists before the year-end one does, and it puts the songs on the
card that the room has actually been hearing.

## How many songs a German year gets

`assets/songs/german_songs.json`, still empty. The deck is what was big *only*
in German-speaking countries - what crossed over stands in the hit deck
already, 99 Luftballons, Der Kommissar, Rock Me Amadeus, Da Da Da.

| Years | Entries per year |
| --- | --- |
| 1950-1958 | 3 |
| 1959-1979 | 5 |
| 1980-1999 | 8 |
| 2000-2026 | 10 |

**The measure is the German singles chart from 1959 on**, the same way the
US/UK year-end charts decide the hit deck: a song either stood in it or it did
not, and that is what keeps a decision arguable later. **From 1971 to 1989 the
DDR-Hitparade counts beside it.** Two charts for two countries - the eastern
entries take normal slots and push out weaker western ones. Ueber sieben
Bruecken and Am Fenster are better known today than half the western chart of
their year, and a measure that cannot see them is the wrong measure.

**Below 1959 a different measure applies, and it is named rather than hidden:**
there is no German singles chart before 1959, so 1950-1958 is filled from the
sellers and film hits documented in hindsight. Three a year. That is the weak
end of the deck and it is meant to be - the same honesty with which the hit
deck stops at 1950.

**The test is German-language *and* big only here.** The first is what the card
promises when the reveal says `German Songs`; the second is the line against
the hit deck. An English-language German production still gets in when it was
an event here and nothing outside - Modern Talking yes (UK #56, nothing in the
US), Milli Vanilli and Boney M no, those were a US number one and a UK regular
and belong in the hit deck. At equal standing the German-language song takes
the slot. The same rule sorts Rock & Pop on its own: Rammstein was big
internationally and is not this deck, Die Toten Hosen and Die Ärzte never were
and stay.

**No genre quota, the chart decides.** Written out: 1950-1975 is almost pure
Schlager, 1978-1985 tips into the NDW, the 90s split between Wolfgang Petry and
Die Fantastischen Vier, and from 2000 Deutschrap and Helene Fischer carry the
year together. An evening on 1955-1970 is a Schlager evening - that is not a
list gone wrong, that is the country in those years.

**An evergreen is a good card, not a bad one.** Griechischer Wein and Ein Bett
im Kornfeld have been running for fifty years and still have exactly one hit
year. The hit deck's rule - that a song which got big again years later is a
bad card - bites only where there really are **two competing hit years**, never
on one hit with a long tail. Applied wider it would clear out half the deck.

**One song, one card.** Über sieben Brücken exists as Karat 1978 and as
Maffay 1980; taking both means half the room is right and cannot be told so.
Take the recording that was the bigger event and its year - Maffay 1980. Same
for German covers of foreign originals: the year of the German version counts,
because that is the one the room heard.

**Volksmusik excludes itself.** Kastelruther Spatzen and Hansi Hinterseer live
in the album chart and barely in the singles chart, so the measure keeps them
out on its own. Leave it at that rather than forcing them in.

**Ballermann and Après-Ski are cards**, precisely because each hangs on a
single summer - Anton aus Tirol 1999, Layla 2022. The deliberately dated
production does no harm; the room places the summer, not the sound.

**The resolver needs German words before it runs over this deck.** `notTheSong`
in `tool/resolve_spotify_tracks.dart` is English only (`karaoke`, `tribute`,
`made famous by`), and the Schlager corner of Spotify announces the same thing
in German: `neuaufnahme`, `neu aufgenommen`, `im stil von`,
`instrumentalversion` belong in that list, or a best-of playback walks through a
clean artist+title match. The more dangerous pressing gets through anyway -
Schlager singers re-record their own hits every ten years and that pressing
often calls itself nothing at all. It is no reason to drop the entry, the song
is right and only the recording is young, but it makes the "Check the year by
hand" list even louder here than for the hit deck. The rule stands: never move
a catalog year onto what the API reports.

## Draw weight: `tier`

Within a year not everything should come up equally often. The core of a year
is drawn more often than its long tail:

- **`tier: 1`** - in ESC the winner, the German entry, and the 4 best known of
  the rest. This is the default when the field is missing.
- **`tier: 2`** - the remaining 4 of the eight. Only ESC 2005-2026 has them;
  the smaller years are core all the way through.

So a 2005+ ESC year is 6 tier 1 + 4 tier 2, and a tier 1 song should be drawn
about 3x as often as a tier 2 one - roughly 80% of that year's rounds land on
the core. Keep the JSON at "core or tail" rather than a per-song weight, so a
year can still be filled in by hand.

The hit and German decks split the same way, read off the size of the year: a
10 song year is 6 + 4, an 8 song year 5 + 3, a 5 or 3 song year is core all the
way through. Core is the same question there as here - the songs the room names
before the chorus is over.

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

**A "no hit" is only worth as much as the query behind it, and the query has
been wrong twice.** First `track:$title artist:$artist` went out unquoted,
where Spotify takes only the first word of each field: that put t.A.T.u., Mia
Martini and the 2011 winner on the miss list and answered Blue's "I Can" with
Adele. Then every search asked for `limit=20`, which this app answers with
`400 Invalid limit` - the documented maximum of 50 is not what a development
mode app gets, ten is - and the tool booked all 47 failures as "not on
Spotify". Both times the miss list looked like a catalog problem and was a
client one.

Hence: a request that fails is its own bucket ("Could not be looked up"), never
a swap, and a miss list is only worth acting on when it comes out of a run that
had no failures in it. Sanity check it against what you know - a Eurovision
winner or a t.A.T.u. single is not missing from Spotify, and a list saying so
is a bug report, not a curation task.

A new category is filled the same way: pick the songs by the curation rule
first, then let the resolver decide which of them can stay.

`README.md` has the commands under "Filling in track ids".

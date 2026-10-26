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
What a device has played is remembered for good (`PlayedSongsStore`, merged
into `_played` in `GameController`): a song does not come back, not in the
same game and not next week, while its year in its deck still holds one this
device has not played. Only a used up year starts over, and its songs leave the
memory again - that is what keeps a thin year from turning into a dead card,
and why this could replace the old weight (the last 300 songs drawn a quarter
as often) on 2026-10-17. The pool size still sets how many evenings a year
lasts before it repeats.

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

The catalog is filled from 1956 to 2026, 415 entries. Every future contest
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

The catalog is filled from 1950 to 2026, 576 entries. Every future year needs
its ten, otherwise that card is a dead round in a game played on the hit deck
alone. A running year is filled from the number ones so far - that is the only
chart that exists before the year-end one does, and it puts the songs on the
card that the room has actually been hearing.

## How many songs a German year gets

`assets/songs/german_songs.json`. The deck is what was big *only*
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
the slot. That is also what keeps Rammstein out - big internationally, so the
hit deck is its place - while Die Toten Hosen and Die Ärzte never were and
stay.

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

**The chart year beats the quota.** The table above is what a year gets while
it is being filled, not a promise about the file. When a song turns out to
have been a hit in another year than the one it sits on, it moves, and the
year it leaves stays one short rather than pulling in a replacement - a card
invented to keep a count is worse than a thin year, and every year still holds
at least six. That is why 1990-2024 is uneven: it was derived from the
year-end charts entry by entry, and the charts do not care about the table.
The floor that does matter is one entry per year, because an empty year is a
dead round.

**The resolver knows German words for this deck.** `notTheSong` in
`tool/resolve_spotify_tracks.dart` carries `neuaufnahme`, `neu aufgenommen`,
`im stil von` and `instrumentalversion` beside the English ones, because the
Schlager corner of Spotify announces a best-of playback in German - without
them it walks through a clean artist+title match. Keep adding to that list
rather than hand-picking around it. The more dangerous pressing gets through anyway -
Schlager singers re-record their own hits every ten years and that pressing
often calls itself nothing at all. It is no reason to drop the entry, the song
is right and only the recording is young, but it makes the "Check the year by
hand" list even louder here than for the hit deck. The rule stands: never move
a catalog year onto what the API reports.

## A deck that does not span the century

The cards run over the whole century, so the rule behind "every year needs its
ten" is really *every year the cards can show*. K-Pop (2016 on) and White Girl
Music (2007 on) break that on purpose - their curation rule has an end at the
bottom, and no amount of work extends them downwards without turning the older
cards into coin flips.

**Such a deck can still be played on its own.** There used to be a
`needsCompanion` flag that kept it from being the only pick, because alone it
answers most cards with nothing. It is gone: the selection card shows the span
(`115 songs · 2016-2026`), so a room that picks K-Pop alone plays the cards of
those years, and a card outside the span only brings up "K-Pop covers
2016-2026 - draw another card" - a card drawn again, not a round without a
song. `canCarryGame` in `lib/models/song_category.dart` only asks for a deck
with songs in it.

Next to a full deck nothing changes: `GameController._draw` picks only among the
categories that hold something for the scanned year, so the other deck steps in
and the short one waits for a year it can serve. On a 1950-2026 card deck it
then serves maybe a fifth of the rounds.

**A short deck must not have holes inside its span.** Played alone, a card in
the middle of the range is one the room was told to play; `catalog_test.dart`
checks every deck for a gap.

## How many songs a K-Pop year gets

`assets/songs/kpop.json`. Ten per year, 6 core and 4 tail, the same split as a
2000+ hit year - the deck only serves part of the rounds, so depth per year
matters less here than in a deck that has to carry an evening.

**The deck starts in 2016 and the reason is the room, not the music.** K-Pop
before that is a different set of groups, and a song nobody recognises turns
the round into a coin flip - the same "best known" filter the other decks
apply. Gangnam Style and the 2nd generation would stretch the range by a few
years on world-hit recognition alone; take them only if the room actually names
them, and note that each such year still needs its ten.

**The year is the release year of the title track.** A comeback is a dated
event the fandom knows to the week, which makes this deck one of the sharpest
in the game - the production sound moves fast enough that 2018 and 2022 are
told apart on the intro. That also means the resolver's year warnings matter
here: unlike the hit deck, a mismatch is worth looking at rather than noise,
because there is no chart year that could legitimately differ from the release.

**Soundtrack acts count.** HUNTR/X and the Saja Boys are fictional groups, but
"Golden" was the song of 2025 for exactly the room this deck is for. The test
is what the room names, not what a label calls an act.

Filled from 2016 to 2026, 115 entries, every one of them with a track id. The
years from 2022 on do not sit on exactly ten - they run between 9 and 13,
because they were gone through by hand and a year somebody has just been
through deserves what they found. That is the curator's call and not a defect:
the ten is a target for a year nobody is looking at. No test guards the size
for that reason; only the tier split is checked, because the draw weight leans
on tier 1 being the majority.

2026 is a running year and was filled from the comebacks so far, so its tiers
are the softest in the deck - a year is only really sorted into core and tail
once it is over.

## How many songs a White Girl Music year gets

`assets/songs/white_girl_music.json`. Ten per year, 6 core and 4 tail, the same
split as K-Pop and for the same reason: next to a full deck it only serves part
of the rounds.

**The deck is the girls' night singalong, not a genre.** Taylor Swift, Olivia
Rodrigo, Lorde, Lana Del Rey, Paramore, Adele, One Direction, Sabrina Carpenter,
Noah Kahan - the songs the room screams along to in the car, whoever sings
them. Harry Styles and Ed Sheeran count, a woman on the mic is not the test.
The filter is the same "best known" as everywhere: a card is a song the room
names before the chorus is over, and the sad-girl indie corner (Phoebe
Bridgers, boygenius) only gets tail slots.

**The deck starts in 2007 and the reason is the canon.** What the phrase means
starts with Teardrops On My Guitar, Misery Business and Girlfriend; before that
the deck turns into the hit deck under another name. Mr. Brightside is the
famous hole - it belongs to 2004 and would need a year of ten around it. As with
K-Pop, the rule has an end at the bottom.

**The year is the year the song was everywhere**, like the hit deck, not the
release of the pressing. Stick Season (July 2022) sits on 2023, back to friends
(December 2024) and Messy (June 2024) on 2025, That's So True on 2025.

**A song with two hit years is left out**, and here that bites more often than
in the hit deck, because TikTok revives this exact corner: Cruel Summer, Sweater
Weather, 505, Skinny Love by Bon Iver. It also bites on album tracks that chart
on release week and again as a single a year later - Karma (2022 album, 2023
single) and Opalite (2025 album, 2026 number one) were taken out for that.

**The original recording, never Taylor's Version.** The room heard Love Story in
2008, and that is the pressing the card plays; the re-recording is a different
year's event. The one exception is All Too Well (10 Minute Version), which only
exists as Taylor's Version and was the 2021 event itself.

**No dedupe against the other decks**, same as between ESC and the hit deck.

Filled from 2007 to 2026, 200 entries, every one with a track id. The ids were
not filled by the resolver - there were no Spotify credentials in that session -
but taken from Spotify's own search results and each one read back from its
`open.spotify.com/embed/track/<id>` page, checking that title and artist match
and that the pressing is not a live, remix or karaoke cut. Run
`--recheck` over the file once when the resolver has credentials again.

2026 is a running year, filled from the Hot 100 number ones and the pop chart
so far; Choosin' Texas would have had a slot but had no id to be found and was
swapped for the cure.

## The Anthony deck

`assets/songs/anthony.json` is not curated by a rule like the others - it is
one person's library, built from their Spotify playlist export
(`all_the_music_i_know.csv`, kept out of the repo: it carries a user id). The
test is "Anthony knows it", so remixes, nightcore and party edits
stay in; that is what the deck is for.

Three things were decided when it was built (2026-10-13):

- **The year is the release date in the export**, against the rule everywhere
  else. With 1265 songs nobody is going to date them by hand, and for a library
  that is mostly 2010-2021 singles the pressing date is right far more often
  than not. Only the best-of pressings were moved by hand (Promiscuous 2006,
  the two Hannah Montana songs 2006/2007). A duplicate keeps its earliest year.
- **Mariah Carey 1994 is left out**: alone it would leave 1995-1998 empty, a
  hole inside the span. The deck runs 1999-2024.
- **Everything is tier 1.** A personal library has no core and tail, and
  1999-2009 and 2022-2024 are thin anyway.

## The Anthony All deck

`assets/songs/anthony_all.json` is the same library from a later, fuller
export (`all_the_music_i_know (1).csv`, 2238 rows, kept out of the repo), added
on 2026-10-17 as a deck of its own beside Anthony rather than replacing it.
The export holds every row of the first one, so those rows keep the year
`anthony.json` gave them, hand corrections included; everything new takes the
export date, and a duplicate keeps its earliest year - which puts TT on 2016
and The One That Got Away on 2010, where the new export has the earlier
pressing. The one exception is Kiss And Make Up, whose second pressing carries
the 2017 date of the Dua Lipa album it was added to later - it stays on 2018. Billie Jean 1982 and Mariah
Carey 1994 are left out for the same reason as in Anthony: alone they would
open a hole inside the span. 2104 songs, 1999-2026, all tier 1.

## The Jakob deck

`assets/songs/jakob.json`, built the same way as Anthony from a Spotify export
(`Liked_Songs.csv`, kept out of the repo). Unlike Anthony's library it reaches
back to the 60s, and the old songs are where the export lies: Spotify dates
the pressing it carries, and for Hey Jude that is a 2015 best-of. So here the
export date was **not** taken on trust below ~2010. Every song whose album is a
best-of, remaster, soundtrack or reissue was moved to its hit year by hand -
52 of them (2026-10-13); the commit that added the deck names them in its
message. A
year that could not be confirmed stays on the export date rather than a guess
(Mark 'Oh "Let This Party Never End").

**1994 is a hole and stays one.** Nothing in the library is from that year, a
song moved there would be a wrong card, and starting the deck at 1995 would
drop everything older. `catalog_test.dart` lists it in `knownGaps`; played
alone, a 1994 card asks for another card. Everything is tier 1, duplicates keep
their earliest year.

## Draw weight: `tier`

Within a year not everything should come up equally often. The core of a year
is drawn more often than its long tail:

- **`tier: 1`** - in ESC the winner, the German entry, and the 4 best known of
  the rest. This is the default when the field is missing.
- **`tier: 2`** - the remaining 4 of the eight. Only ESC 2005-2026 has them;
  the smaller years are core all the way through.

So a 2005+ ESC year is 6 tier 1 + 4 tier 2, and a tier 1 song is drawn 3x as
often as a tier 2 one *among the songs not played yet*. Keep the JSON at "core
or tail" rather than a per-song weight, so a year can still be filled in by
hand.

**Since the played memory is kept for good, the tier sets the order, not the
share.** Every song of a year plays once before any repeats, so over the long
run a 6 + 4 year lands 60% of its rounds on the core, not the ~80% the weight
alone would give. Within one pass the core comes first: about 82% core on the
first scan of a year, 12% on the tenth - the tail gathers at the end of every
pass. Looked at on 2026-10-26 and kept that way on purpose: getting the 80%
back would mean letting a core song repeat before the tail of its year has
been heard, against the rule in the ESC section.

The hit, German, K-Pop and White Girl Music decks split the same way, read off the size of the
year: a 10 song year is 6 + 4, an 8 song year 5 + 3, a 5 or 3 song year is core
all the way through. Core is the same question there as here - the songs the
room names before the chorus is over.

Implemented: `Song.tier` (default 1, anything but 1 or 2 is a `FormatException`
at startup) and `GameController._pickWeighted`. The weighting sits inside the
"prefer unplayed" pass, so within one game every song of a year is still played
before one repeats - the tier decides the *order*, and with it which songs a
year that is only scanned once or twice ever gets to show. The factor is
`_tierOneWeight` in `lib/game/game_controller.dart`, one number to tune.

**A swapped song is drawn like the tail.** `redraw` is the room saying it does
not know the song, so its `Song.key` goes into `SkippedSongsStore` and from
then on it weighs what a tier 2 song weighs, on this device, in every deck it
stands in. It stays in the deck and still comes once per pass - the swap only
moves it to the back. The undo beside the swap button
(`GameController.undoRedraw`) takes the last swap of the round back and leaves
no trace: the song leaves that memory, the one swapped in counts as unplayed
again. Past the round nothing takes a song out of it.

**Played is per deck, the order looks across decks.** Anthony and Anthony All
share 1263 songs, Anthony All and Jakob 115, the hit deck and White Girl Music
45 in the same year. Picked together, `_draw` prefers a song whose `Song.key`
no deck has played yet, but only within what its own deck still has unplayed:
it never starts a year over early and never keeps a song out that its deck
needs. Same key means same track id, so the ESC and hit deck pressings of
Waterloo and the like are not caught - accepted, see the hit deck section.

## Two ways to play a song, one of them optional

`SongLauncher` has two Spotify implementations and the choice is not a
preference:

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

**A launch that succeeded can still fail afterwards.** Spotify answers the
play request with 204 and only then reports `playback_error` - a DRM stack
that refuses, a mobile browser that would not unlock audio. The session keeps
that as `playbackError`, the game screen hands it to
`GameController.playbackFailedInApp`, and the round turns into a link round
with its "Open in Spotify" button. `reopen` goes through the link launcher
only: trying the player again would fail the same way.

**A swap must not move the screen.** It hands the song over again, and until
that launch answers `playingInApp` is false - the bar would go and the reveal
card change its text for a moment. `_looksInApp` in `lib/ui/game_screen.dart`
keeps the in-tab layout while a launch is out on a ready session. Layout only:
the round itself still reads `playingInApp`.

**The seek bar is an in-app extra, nothing more.** `SongProgressBar` shows only
where `playingInApp` is true, because a song handed over by link is out of
reach. Do not build round flow on it - the link round has to stay complete
without it.

**A round can end while its launch is still out.** Reset, a new game, a swap -
`startPlayback` checks after the `await` that the round it launched is still
the one on screen, and stops a song that started in the tab too late. Anything
new that awaits a launch needs the same check.

`README.md` has the setup under "Playing in the tab".

## The wide layout is for the projector, and for a phone turned over

The game screen has a second layout for wide screens (`isWideScreen`,
`_WideRound` in `lib/ui/game_screen.dart`), added 2026-10-26 so the game can
run from a laptop on a projector. It picks itself by size, not by a setting:
the laptop is the device then, and a phone column in the middle of a wall is
never what anybody wants.

**Landscape is the whole question - there is no size floor under it.** It
started with one (`width >= 900`), on the idea that a turned phone would only
get a stage the width of a strip. The device it was tried on says otherwise: on
an S24 Ultra sideways, ~893x412 CSS pixels, the one column kept its 560 and
left a sixth of the screen empty on either side, while the height it wants is
exactly what a turned phone has least of. So `isWideScreen` is `width >=
height * 1.2` and nothing else (2026-10-26). The ratio rather than plain
`width > height` keeps a nearly square browser window on the one column, where
two things side by side would both be too narrow.

**That makes the stage's floors wrong.** Its blocks are shares of the height -
year card, words, score tiles - and each had a minimum sized for a projector.
On a 319 high stage (375 minus the app bar) the minimums alone came to more
than the screen, so the shares are now capped at the top end only. Nothing
needs a floor: every block below sits in a `_FitBody` and scales what it holds
down. The same for the two fixed-size things that stood in a `Row` beside
flexible ones - the 140pt year and the reveal pill - they are `Flexible` and
scale with the card now, instead of pushing the name off it.

**A phone's stage is a phone's stage.** Small type for whoever holds it, not
for a room; the point of the layout here is the space, not the distance. Tested
at 893x412 and 667x375, playing and revealed, in `game_screen_test.dart` -
a widget test fails on an overflow, which is what caught both of the above.

**The reveal is on the stage and in the column** (`revealInColumnKey`,
2026-10-26). The card on the stage stays the button it was - that is what makes
revealing a swap rather than a rearrangement - but on a wall it is out of
reach, and whoever runs the game sits at the device with every other control of
theirs. Two buttons for one action, deliberately; both call
`GameController.reveal`, and the key is only there so a test can say which one
it pressed.

**The wide layout has no app bar** (2026-10-26). 56 pixels of a landscape
phone's 412 for a deck name the room does not need and a menu that belongs to
whoever runs the game: the menu moved into the corner of the camera panel,
where it costs no height, and the bar's automatic back arrow went with it - so
the menu carries `Leave the game`, which is `_onBack` under another name. A
game nobody can leave would be the one thing worse than a bar.

Measured on an S24 Ultra's 893x412 before and after: the words' box went from
109 to 156 pixels, about three readable lines to seven. The rest of that came
from three things sized for a projector and wrong on a phone - the box's own
padding (fixed 28 above and 72 below, a tenth of a 560 pixel box and most of a
109 pixel one, now a share of it), the camera panel (4:3 whatever the height,
160 of a 364 pixel column, now capped at a third of it), and the scores, which
take 0.11 of a short stage instead of 0.14 and drop the line about tapping
them. **The scores get less, not more, on a short stage**, and that is the
owner's call: the tiles are never used in practice, the words are the whole
reason to lay the game out sideways.

**The player is a band across the bottom, under both halves** (2026-10-26).
In the side column the track was ~190 pixels for a 3:20 song - a second of
music per pixel, which is not a bar anybody finds a chorus with. Across the
screen it is 501, so 0.4 seconds per pixel. The buttons came along and stand
to the left of the track, under the column they belong to, rather than beneath
it: height is what the stage is short of, and a tap gains nothing from width.
They keep their 48 pixel targets, which is what costs the track the last ~100
pixels of the screen - that trade can be reopened, the buttons are tapped a
few times a round and the track is dragged.

The band is kept 8 pixels off the bottom edge, because a drag down there fights
the phone's own home gesture. It shows while `playingInApp` and its room is
held while a launch is still out (`_looksInApp`), the same rule the column used
- so a swap does not pull the floor out from under the stage. A link or YouTube
round has neither band nor reserved room: nothing to scrub, so the words get
those 50 pixels instead. The swap stays in the column, where the rest of the
round's controls are.

**The stage is the words, from the first note to the next card** (2026-10-27).
It used to carry the reveal banner across its top while the room guessed, and
then the year card - first beside the words, then instead of them. All of that
is gone: the stage holds the words and the scores, and nothing else ever.

The banner went because the reveal is a button in the column, and a fifth of
the stage spent telling the room about a button it cannot reach is a fifth too
much. The year card went because an answer laid over the words takes away what
the room was reading - the words are the reason to put the game on a wall, and
they now keep their full height through the reveal (213 pixels on a landscape
phone, the same before and after it). The answer is top left in the column
(`_ColumnYear`): on a projector that box is on the same wall, so the room reads
it there, and next to it the camera is already waiting for the next card.

So `_YearCard` is the phone's card alone, and `_RevealSlot` too; both lost
their `wide` branch with the thing it was drawn for. The deck-and-place line
(`_originLine`) moved into the column's box - it is what makes a year read as
the year of that contest, and that box is the only card the wide layout has
left.

**The scores can be switched off, and then nothing counts** (`ShowScoresStore`,
per device). `Hide the scores` in the menu takes the strip, its heading and the
tapping hint off the stage and the grid off every phone screen - the words then
have the whole stage, 364 of 412 pixels on a landscape phone against 109 before
any of this. With nothing to tap there are no points and the game never reaches
its target: that is the option working, not a bug to fix. A game's scores are
kept while they are hidden and come back with them.

**The size of the words is set from the menu and kept per device**
(`LyricsScaleStore`, a factor on the size the stage reads off its height).
It belongs to the room - how far the sofa is from the wall, what the projector
does to a 24pt line - not to a game, so it outlives every game like the music
service does. A press is a factor (1.2) rather than a step, so it does the same
amount of work at either end of the 0.6-2.4 range; the menu carries the current
percentage as a disabled row above the two entries, and an entry greys out at
the end of the range rather than going dead without saying so.

It started as a row of two buttons in the column and moved into the menu on
2026-10-27. A press closes the menu, so a second step is a second trip through
it - the fair price for a setting that is made once for a room and then left
alone, and it buys the column the room back. The sheet on the phone has its own
size and is not affected: there the distance to the reader is arm's length,
whatever the room looks like.

**Two halves for two audiences.** The stage is for the room and holds only what
the room reads: reveal or year, words, scores. The column is for whoever runs
the game: camera and song controls. New things go on the side they are for.

**The words are up for the whole round the room is guessing in.** That is the
reason to put the game on a wall, and it was the ask. The phone keeps them
behind the button. Title and artist stay off the stage until the reveal,
exactly as in the sheet - the words are a hint, the name is the answer. At the
reveal they hand the stage to the answer, see below.

**The camera that opens itself reads past one card, for three seconds.** That
took three goes to get right, and the two wrong ones are worth keeping here
because each looked done.

The card of the round is lying in front of the lens at the moment of the
reveal, and reading it would start a round on top of the year nobody has read
yet. So it is ignored - but only briefly: a second later the same card in front
of the camera is somebody holding it up on purpose, which is the normal way to
try the thing. `_staleCard` is that window.

The first try ignored it for as long as the camera stayed open, which reads as
a camera that scans nothing at all. The second try moved the test in front of
`ScannerView`'s own latch (`ScannerView.ignore`), because the view reports one
code and then stops looking - a code thrown away *after* it was reported locks
the camera for good. That was necessary and still not enough: the controller
ran on `DetectionSpeed.noDuplicates`, so a code read past was a duplicate from
then on and that card could not be read again at all in that session. Only
closing the camera and opening it again helped, which is exactly what the
report said. The speed is `normal` now; one report per view is `_handled`'s job
and always was.

**The camera opens on demand - and the reveal is a demand** (2026-10-26). It
used to open only on a tap, because a running camera reads the card still lying
in front of it and starts the next round over the reveal. That danger is real
and it is handled by name rather than by keeping the camera shut, see the three
seconds above. A scan the operator asked for has no guard at all - a card
presented to a camera that was opened by hand is a decision, not a leftover.

**The column is two fixed homes** (`_ActionSlot`, `_CameraBox`), and that is
the second half of the same decision. The slot on top is what to do or what
came of it - `Scan a card`, `Reveal the year` while the song runs, then the
year it produced, small, for whoever runs the game. The camera lives at the
foot of the column. Neither displaces the other, so nothing in the column moves
from one round to the next; the reveal panel in particular is always in the
same place, which it was not while one slot morphed between button and preview.

**The split is dragged, not derived** (`ColumnWidthStore`, per device,
2026-10-27). The column was a share of the width with a floor and a cap; now
there is a grip between the two halves (`splitHandleKey`) and the share is
whatever it was last pulled to, 0.16 to 0.5. A projector wants a wide stage and
a laptop run by hand wants a wide column, and which one an evening is depends
on the room rather than on anything measurable here - so it is a decision made
with the screen in front of you, and it is remembered.

**The menu is in the top right corner of the screen**, over neither half. It
belongs to whoever runs the game but it is reached once or twice an evening,
and the corner is the one place no round needs - in the column it was taking
room from the boxes, which is what the missing app bar had just given back.

**The two boxes of the column are one width.** The camera is as wide as the
slot above it and takes its height from that width, capped at a third of the
column; where the cap bites it crops rather than narrowing itself, because what
the scanner reads is the camera's frame and not the painted preview.

**The camera box is off screen while a round plays.** There is nothing to look
at then, and a grey placeholder earns its space less than the air around the
controls. It comes back with the reveal, open, and a camera closed by hand
leaves a `Next round` button in its place.

**The answer is centred in its box, and two columns where that box is wide**
(2026-10-27). The year beside the name rather than over it leaves the year
twice the height, so `_ColumnYear` lays itself out as a row once the box is
wider than it is tall and stacks them when it is not - a phone turned over has
a column too narrow for two of anything. The year is deliberately not the
biggest thing in it: four digits are read at a glance, and the title is what
the room talks about at the reveal, so the name got the size the year gave up.

**The keyboard hints sit directly above the camera**, at the foot of the
column: out of the way of the round's controls, and where the eye goes between
two rounds anyway. They live inside the same bounded box as the controls and
scale as one block from a width of their own - wrapped to the column's width
instead, a single chip is wider than a phone's column, and the overflow moved
from the side to the bottom, where it ran under the preview. Under 30 pixels of
room they go entirely: scaled into nothing says less than the air it takes.

**The camera grows into place** (`AnimatedSize`, 240ms), so the keys above it
slide up rather than jump. It is the one animation in the layout and it is
there because the camera arrives on its own - a thing that appears without
being asked for should move like something that was always coming.

Two things follow that are easy to get wrong. The auto-scan is started from
inside the tap that revealed, which is what lets a mobile browser unlock sound
for the next round - do not defer it. And `_nextRound` now awaits a card while
the points are being handed out, so the game can be won after the camera
opened: it checks the winners **again** after the scan and drops the card, or
the finish screen would be skipped by a round nobody asked for.

`_scanCode` hides the rest of the difference: it awaits the inline camera the
same way it awaits the scanner page, so the round flow behind it has one path.

**The stage's lyrics outlive the launch.** They are built with the round, before
the launch says whether the song plays in the tab, so `LyricsView` picks the
session up when it arrives and picks the text again once the recording's length
is known. Anything else on the stage that depends on the session has to cope
with it turning up late, or going away on a `playbackError`.

**The link path gives the answer away on a wall.** The Spotify tab opens on the
projected screen with title and cover, and coming back to the game tab reveals
the year. It still has to work - the in-app player is never a requirement - but
the projector is played through the tab. Do not change what a `resumed` does
for wide screens without asking: the link round on a laptop is the same round
as on the web anywhere else.

**No right click on the tiles.** It looked like the desktop way to take a point
back, but Flutter web shows the browser's context menu on every right click.
Long press works with a mouse too.

## Keyboard shortcuts: six moves, and the keys are taken

`GameShortcut` in `lib/ui/game_screen.dart` is the one list - the bindings and
the hint line are both built from it, so they cannot drift apart. Space plays
and pauses, Enter reveals, N is "nobody knows it" and Z takes that swap back,
and the four moves of the song have an arrow and its WASD letter each: left/A
and right/D step ten seconds, up/W jumps to the middle and down/S back to the
start. The pairs are laid out the way the moves are, the horizontal keys
stepping and the vertical ones jumping. It is not a convention anybody arrives
knowing - it is one evening's learning and then it is muscle.

**Taking these keys means taking them from Flutter.** `CallbackShortcuts` sits
below the app's own shortcuts and above every button on the screen, so inside
the game screen space and enter no longer press whatever button holds the focus
and the arrows no longer walk from one to the next. That is the price of using
the obvious keys rather than letters, and for a game run with a mouse on a
laptop it is the right one. A dialog, the countdown and the scanner page are
routes of their own and keep their keys - the shortcuts resolve along the focus
chain, which does not run through this screen from there.

**A key does only what a finger could**, and `GameShortcut.isLive` is where
that is decided - once, for the bindings and the hint line together, so a key
is written down exactly when it works. The song can only be moved in a round
that plays in this tab (`playingInApp`), so on a link or YouTube round the
player keys do nothing at all; the swap and its undo ask the controller's own
`canRedraw` and `canUndoRedraw`, so N is dead in a year with one song and Z
only after a swap. `seekSongBy` is shared with the bar's own buttons rather
than written twice.

**Where they are written down: the column, and only with a keyboard.**
`hasKeyboard` in `lib/ui/layout.dart` reads `defaultTargetPlatform`, which on
the web is the operating system - a laptop says macOS, Windows or Linux and a
phone says Android or iOS. The hint line goes at the foot of the column's
controls, never on the stage: a key nobody in the room can press is of no use
to the room, and on a projector the stage is the wall. It lists only the keys
that do something at that moment, so a link round shows one line and an in-app
round all six. A tablet with a keyboard is called wrong by `hasKeyboard` and
loses the hint - the keys themselves still work wherever one is pressed.

## Fullscreen is an offer, never a state the game keeps

`lib/ui/fullscreen/`, in the shape `wake_lock/` already has: a native file that
says no and a web file that asks `document.documentElement`. The menu entry
only appears where `Fullscreen.isSupported` - an iframe without the permission
and an iPhone before 16.4 do not have it - and a refusal is the normal case
rather than an error, because a browser grants fullscreen to a gesture and to
nothing else. The game reads `isOn` when the menu opens, so the entry says what
the tap will do, and nothing else in the app asks: a page that came out of
fullscreen by itself (Escape, a tab switch) is not a page in a wrong state.

It earns its place twice. On a projector it takes the address bar off the wall,
and on a phone turned over the browser's bars are a tenth of the screen the
stage could have instead - which is the same arithmetic as the missing app bar.

## The page's script sources are a list

`web/index.html` carries a Content-Security-Policy that names every host a
script may come from: this site, `www.gstatic.com` (CanvasKit) and
`sdk.scdn.co` (the Spotify player). The page keeps the Spotify refresh token in
`localStorage`, so an injected script is the one thing that must not run. A new
script host that is not added there is blocked silently in production - the
browser console names it.

That is also why the QR reader is served from `web/zxing/` instead of the CDN
`mobile_scanner` would use: `reader.js` and `zxing_reader.wasm` are zxing-wasm
at the version `mobile_scanner` pins, and `mobile_scanner` is pinned exactly in
`pubspec.yaml` so the two cannot drift apart. Upgrading it means copying the
matching zxing-wasm files - `README.md`, "Camera".

## The camera runs only while a scanner is on screen

`mobile_scanner` 7.4.0 never stops a camera stream on the web: `stop` and
`dispose` drop the stream without ending its tracks. Measured on 2026-10-26 in
Chrome with a fake camera: two scans, two camera streams still live, no
scanner on screen. Every scan opens one more and leaves the ones before it
running - an evening of thirty rounds would end with thirty. 7.4.1 and 7.4.2
do not touch it.

`CameraStreams` (`lib/ui/camera_streams/`) works around it from outside,
because the plugin keeps the stream to itself: it wraps
`navigator.mediaDevices.getUserMedia`, notes every stream, and stops them all
once no `ScannerView` holds the camera any more - a stream that only arrives
after its scanner closed is stopped as it arrives. The game asks the browser
for nothing else, so every stream is the camera. **When upgrading
`mobile_scanner`**, check whether it stops its tracks itself now; the wrapper
does no harm either way, but it should not outlive its reason unnoticed.

Every scanner is handed its controller, and the plugin only pauses a camera on
the app lifecycle for a controller it made itself. So `ScannerView` does it:
it stops the camera when the page goes `hidden` or `paused` - a hidden tab,
the phone switched over to Spotify - and starts it again on `resumed`. Not on
`inactive`: the browser's camera permission prompt takes the focus, and
stopping there stops the camera that is just being asked for.

Checking this needs a browser, not a widget test: headless Chrome with
`--use-fake-device-for-media-stream --use-fake-ui-for-media-stream`, and a hook
on `getUserMedia` that counts the video tracks still `live`. Simulate a hidden
tab with a `visibilitychange` event, not by freezing the page - a frozen page
stops rendering frames, and the scanner is then never taken down at all.

## YouTube Music: a link, never a player

The second service, picked per device on the setup screen (`MusicService`,
stored by `MusicServiceStore`). It opens `music.youtube.com/watch?v=<id>` and
that is all it does - no player in the tab, and the countdown runs before every
round even when a Spotify session happens to be connected
(`needsCountdown` in `lib/ui/game_screen.dart`).

**The in-tab player was looked at and left out** (2026-09-16). The YouTube
IFrame player would play without login or Premium, but only a *visible* one is
allowed - hiding it, which a guessing game has to because the video shows
title and cover, breaks the API policies. On top of that an ad plays invisibly
before the intro, and many official uploads refuse embedding (error 101/150),
so a share of the rounds would fall back anyway. Pulling the audio stream out
directly (yt-dlp and friends) is out for the same reason and breaks every few
weeks. Do not build either without asking again.

**A missing `youtubeVideoId` is not a swap.** The catalogs are curated against
Spotify - "What Spotify does not carry is not a card" stays the rule. An entry
YouTube Music does not carry keeps its slot in the file. Swapping it would cost
the Spotify deck a good card for the sake of the smaller path.

**The game only draws what the service can play** (`GameController.songsFor`,
`Song.playsOn`). On Spotify a song without `spotifyTrackId` is never drawn, on
YouTube Music a song without `youtubeVideoId` is not - another song of the year
takes the round instead of a search page nobody taps. So a missing id no longer
costs a round, it costs the song its turn on that service; only a year where
*no* song carries the id is a dead card, and the setup check for that is to
count, per deck and service, the years without a single id. At the time of
writing there are none. The six ESC entries neither service carries (Venedig im
Regen 1991, Fra Mols til Skagen and Il me donne rendez-vous 1995, Everybody
2001, Weil der Mensch zählt 2003, Tick-Tock 2014) were dropped on 2026-09-16 -
Everybody was the winner, and a winner nobody can hear is still no card.

**The resolver goes through an undocumented endpoint.**
`tool/resolve_youtube_music_tracks.dart` asks the search behind
music.youtube.com, because the official Data API allows about 100 searches a
day - two weeks for the catalogs. When it stops working, that is the endpoint
having changed, not the catalog: fix the client version or the parsing, never
book the misses as missing songs. The game itself never talks to it.

YouTube Music carries far more second takes than Spotify - acoustic, live,
sped up, uploaded by the artist next to the original and often ranked above it.
The resolver refuses those on top of Spotify's `notTheSong` list; a new kind
that slips through belongs in `notTheSongHere`, not in a hand edit.

The first full pass took all of that on trust and a read-through of every hit
whose title was not the catalog title word for word turned up what else has to
be refused, now in the rules and their tests: mixes that are remixes under
another name ("Nite Mix", "Motiv8 Extended Vocal Mix"), re-recordings dated in
a bracket ("MfG (2022)", "Mine (Taylor's Version)"), takes in another language
("Boom Bang a Bang (Deutsch Version)" - allowed only in `german_songs`), and
any name that cannot be compared: a Cyrillic title turned out to be another
song of the artist, a Thai artist a cover. Those entries go to the search in
the game - a miss costs a tap, a wrong id costs the round.

**Some songs are only there as a video in Germany.** The search runs with
`gl: DE`, and labels keep album tracks out of the German catalog that the US
one has ("New Rules", "Somebody That I Used to Know"). The resolver falls back
to the videos filter then and takes the video from the artist's own channel.
Keep `gl` on `DE`: an id found for another country can be greyed out for the
room.

**What the rules miss can be set by hand - after reading the rows.** The last
misses were mostly the song under another name: an artist renamed (Lady
Antebellum, Charlotte Perrelli), written in its own script (Сергей Лазарев), a
title spelled differently ("Zieh die Schuh aus"), or a hit that is itself a
remix ("Cheerleader (Felix Jaehn Remix)"). Loosening the rules for those would
let the wrong hits back in, so 34 ids went in by hand, each one the artist's
own recording seen in the search rows. What only exists as a fan upload or a
live cut stays without an id - nine old ESC entries, "Venedig im Regen" among
them - and opens the search.

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

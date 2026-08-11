--!strict
-- Every sound in the game, and ONLY here -- same rule as every other Config
-- module in this project. See SoundPlayer.luau (the only module that ever
-- creates a Sound instance) and REPORT.md for the full routing story.
--
-- ===== EVERY ASSET ID IS DELIBERATELY nil, AND THAT IS THE POINT OF THIS
-- PASS. Neither the author of this system nor its reviewer can hear anything:
-- an asset ID cannot be auditioned from here, and a plausible-looking
-- rbxassetid:// that resolves to the wrong sound -- or to nothing -- is WORSE
-- than a nil, because nil is visibly unset while a wrong ID looks finished.
-- So this pass ships the whole system wired, mixed and torn down correctly,
-- with the ids left as named holes.
--
-- TO FILL THEM IN: put a real "rbxassetid://..." in the `id` field of any entry
-- below and it starts playing, everywhere it is already wired, with no code
-- change anywhere. Entries with a nil id no-op silently -- no error, no warning
-- spam, no gap in the surrounding logic (see SoundPlayer's own header).
--
-- ===== HOW TO READ AN ENTRY WHEN SHOPPING FOR THE ASSET. Each carries a
-- WHAT/LENGTH/CHARACTER comment written for exactly that job -- what the sound
-- is for, how long it may run, and what it should feel like. The LENGTH is a
-- real constraint, not a suggestion: several of these fire on every launch
-- cycle (5-16 seconds at the current pacing), so anything with a long tail will
-- overlap its own next firing. REPORT.md carries the same information as one
-- table, which is the sheet to shop from.
--
-- ===== VOLUME IS RELATIVE TO ITS GROUP, not absolute. Final loudness is
-- entry.volume * its SoundGroup's Volume * the master group's Volume (see
-- GROUP_VOLUMES below and SoundPlayer.ensureGroups). Tuning one entry against
-- its neighbours is what `volume` is for; tuning a whole category against the
-- others is what the group is for.

export type SoundEntry = {
	-- nil until a real asset is dropped in. Never invent one.
	id: string?,
	-- Multiplied by the group volume; see above.
	volume: number,
	-- Sound.PlaybackSpeed. Several callers override this per-firing (the flight
	-- loop tracks speed, the doubling chain climbs, the reveal scales by tier);
	-- where they do, this is the value at the bottom of that range.
	pitch: number,
	-- One of "UI" | "WORLD" | "FLIGHT" | "REWARD".
	group: string,
	-- TRUE = 3D, positioned in the world, attenuating with distance. FALSE = 2D,
	-- parented to SoundService, identical wherever the listener stands.
	spatial: boolean,
	-- 3D only, and REQUIRED when spatial (asserted at load below). Studs at
	-- which the sound reaches SILENCE -- a real cutoff, because SoundPlayer
	-- forces RollOffMode.Linear; see its own comment for why the default
	-- Inverse mode would make these audible across the whole 3,000-stud map.
	rollOffMaxDistance: number?,
	-- 3D only. Studs within which the sound plays at full `volume` before
	-- attenuation begins.
	rollOffMinDistance: number?,
	-- Loops until explicitly stopped. Only the flight rush and the conveyor.
	looped: boolean,
	-- Hard ceiling, in seconds, on how long a ONE-SHOT instance may live before
	-- SoundPlayer destroys it regardless. A backstop for the case where Ended
	-- never fires (a failed asset load leaves a Sound that never plays and never
	-- ends), NOT a fade -- set it comfortably above the asset's real length.
	-- Ignored for looped entries, which are torn down by their owner.
	maxLifetimeSeconds: number,
}

export type SoundConfig = {
	MASTER_VOLUME: number,
	GROUP_VOLUMES: { [string]: number },
	GROUP_ORDER: { string },
	MUTE_TOGGLE_KEYCODE: Enum.KeyCode,
	SOUNDS: { [string]: SoundEntry },
}

-- ===== GROUP MIXING (see REPORT.md §5a). Four categories, nested under one
-- master SoundGroup so a single number moves everything.
--
-- The levels are NOT uniform, and the reasoning is duration and frequency, not
-- importance:
--
--   REWARD (0.85) is loudest because it is the payoff, it is short, and it
--     fires at most once per launch cycle. It should sit on top of everything.
--   UI (0.60) is next: one-shots that must read as crisp confirmations, but
--     button clicks fire constantly while a menu is open, so they cannot sit at
--     reward level.
--   WORLD (0.50) is other players' events, mostly. It is scenery -- it should
--     tell you something happened nearby without competing with your own
--     reward.
--   FLIGHT (0.30) is the quietest by a wide margin, and this is the number most
--     likely to need retuning. It is the only category with a sound that runs
--     CONTINUOUSLY for up to 11 seconds (see the tier-keyed flight duration),
--     and a rush loop mixed at one-shot level would dominate the single longest
--     moment in the game and mask the landing that ends it.
local GROUP_VOLUMES: { [string]: number } = {
	UI = 0.60,
	WORLD = 0.50,
	FLIGHT = 0.30,
	REWARD = 0.85,
}

-- Deterministic order, purely so the group-creation loop and any UI listing
-- them are stable rather than depending on hash iteration order.
local GROUP_ORDER: { string } = { "UI", "WORLD", "FLIGHT", "REWARD" }

local SOUNDS: { [string]: SoundEntry } = {

	--=======================================================================--
	-- UI -- all 2D, all fired on the owning player's own client, never heard
	-- by anyone else. Nothing in this group is positioned.
	--=======================================================================--

	-- WHAT: the generic press for EVERY GuiButton in the game -- shop open and
	--   close, inventory open and close, the buy buttons, the upgrade strips
	--   over the slot slimes, the dev panel. Wired once, centrally, by
	--   SoundClient walking PlayerGui, so it covers all fourteen button
	--   construction sites without any of them knowing.
	-- LENGTH: 0.05-0.12 s. Genuinely short.
	-- CHARACTER: a soft, neutral, non-musical click or tick. It fires more
	--   often than anything else in the game, so it must be unobtrusive and
	--   have NO pitch identity -- anything melodic becomes maddening at the
	--   fiftieth press. One-shot.
	UI_BUTTON_CLICK = {
		id = nil,
		volume = 0.35,
		pitch = 1.0,
		group = "UI",
		spatial = false,
		looped = false,
		maxLifetimeSeconds = 2,
	},

	-- WHAT: a purchase went through -- a swing tier bought (ShopServer) or one
	--   or more slime levels bought (UpgradeServer). Fired from the RESULT
	--   remote's success branch, so it can never play for a purchase the server
	--   refused.
	-- LENGTH: 0.4-0.8 s.
	-- CHARACTER: an ascending two- or three-note confirmation chime. Money
	--   well spent. Warm rather than triumphant -- the reveal is the game's
	--   celebration and this must not compete with it. One-shot.
	UI_PURCHASE_SUCCESS = {
		id = nil,
		volume = 0.7,
		pitch = 1.0,
		group = "UI",
		spatial = false,
		looped = false,
		maxLifetimeSeconds = 3,
	},

	-- WHAT: a purchase or inventory action was REFUSED by the server -- not
	--   enough money, base full, slot empty, already max tier.
	-- LENGTH: 0.15-0.3 s.
	-- CHARACTER: a short, low, soft "no". A dull thud or a descending
	--   two-note. Explicitly NOT harsh or buzzer-like: the player will hit this
	--   often while saving up, and a punishing sound makes an ordinary "not
	--   yet" feel like a mistake. One-shot.
	UI_ACTION_DENIED = {
		id = nil,
		volume = 0.5,
		pitch = 1.0,
		group = "UI",
		spatial = false,
		looped = false,
		maxLifetimeSeconds = 2,
	},

	-- WHAT: a slime was placed into a slot, removed to inventory, or sold --
	--   any successful inventory action. One sound for all three; they are the
	--   same kind of small confirmation and three near-identical assets would
	--   be three things to shop for and no clearer.
	-- LENGTH: 0.2-0.4 s.
	-- CHARACTER: a soft organic "plop" or shuffle -- something physical being
	--   set down. Slimes are the subject, so a wet/squishy character fits the
	--   game better than a UI beep. One-shot.
	UI_INVENTORY_ACTION = {
		id = nil,
		volume = 0.55,
		pitch = 1.0,
		group = "UI",
		spatial = false,
		looped = false,
		maxLifetimeSeconds = 2,
	},

	-- WHAT: the pending pot was banked by walking over a collect pad. Fired to
	--   the OWNING player only (2D), from the server, at the moment the pot
	--   actually moves -- see PlayerProfile.collectPending.
	-- LENGTH: 0.15-0.25 s, and this ceiling is the important part of the entry.
	--   The return pad sits on the post-flight walk, so this fires on EVERY
	--   cycle -- roughly every 5 to 16 seconds, indefinitely, for the whole
	--   session. It will be heard hundreds of times an hour.
	-- CHARACTER: a single soft coin or register "ding". Short decay, no tail,
	--   no melody, nothing that resolves -- a sound that goes somewhere is a
	--   sound you notice, and this one must become texture. If in doubt pick
	--   the quieter, duller option. One-shot.
	UI_COLLECT = {
		id = nil,
		volume = 0.45,
		pitch = 1.0,
		group = "UI",
		spatial = false,
		looped = false,
		maxLifetimeSeconds = 2,
	},

	--=======================================================================--
	-- FLIGHT -- the launch loop's own audio, all 2D and all on the FLYING
	-- player's own client. None of it is heard by anyone else; the world-facing
	-- half of a launch is WORLD_LAUNCH_RELEASE below.
	--=======================================================================--

	-- WHAT: the rush of air for the whole flight, from release to landing. The
	--   flight is 2 seconds at tier 1 and 11 seconds at tier 10 -- the single
	--   longest continuous moment in the game, and currently silent.
	-- LENGTH: a SEAMLESSLY LOOPING bed, 2-4 seconds of source material. It must
	--   loop without a click or an audible seam, because at tier 10 it will
	--   repeat three to five times in one flight. Avoid anything with a
	--   recognisable rhythm or event in it -- a gust, a flutter, a doppler
	--   sweep -- since that event will then recur every few seconds and give
	--   away the loop point.
	-- CHARACTER: broadband wind/air rush. Steady, no melody, no pitch centre.
	--   SoundPlayer drives PlaybackSpeed and Volume from live speed every frame
	--   (see REPORT.md §3b), so pick something that survives being pitched
	--   between roughly 0.85x and 1.30x without sounding artificial -- i.e.
	--   noise, not a tone.
	-- LOOPED. Torn down on every flight-exit path including death and
	--   disconnect; a leaked loop here would be a permanent drone.
	FLIGHT_WIND_LOOP = {
		id = nil,
		volume = 1.0,
		pitch = 1.0,
		group = "FLIGHT",
		spatial = false,
		looped = true,
		maxLifetimeSeconds = 0,
	},

	-- WHAT: the instant of release, on the launching player's own client --
	--   the whip of leaving the seat. Paired with, but distinct from, the 3D
	--   WORLD_LAUNCH_RELEASE that everyone nearby hears.
	-- LENGTH: 0.3-0.6 s, and it should have DECAYED before the wind loop is
	--   established, not fought it.
	-- CHARACTER: a sharp upward whoosh. This is the most physical moment in the
	--   game and it should feel like effort released. One-shot.
	FLIGHT_RELEASE = {
		id = nil,
		volume = 0.8,
		pitch = 1.0,
		group = "FLIGHT",
		spatial = false,
		looped = false,
		maxLifetimeSeconds = 3,
	},

	-- WHAT: the multiplier bar entering the sweet-spot window, while riding.
	--   An audible anchor for a timing window that is 0.288 s wide overall and
	--   only 0.072 s at the top tier's snap threshold -- narrow enough that a
	--   purely visual cue is genuinely hard at speed.
	-- LENGTH: 0.04-0.08 s. Shorter than the window it marks, or it is lying
	--   about when the window is.
	-- CHARACTER: a single dry tick or rimshot. NOT a tone with a pitch, and
	--   emphatically not a rising sweep: it marks an EDGE, and the player's job
	--   is to release just after hearing it. It repeats every 2.4 s for as long
	--   as someone sits on the swing, so it must be tiny.
	-- See REPORT.md §3c for why this one is wired but the per-frame "sweep
	-- tone" alternative deliberately is not.
	FLIGHT_SWEET_SPOT_ENTER = {
		id = nil,
		volume = 0.4,
		pitch = 1.0,
		group = "FLIGHT",
		spatial = false,
		looped = false,
		maxLifetimeSeconds = 2,
	},

	--=======================================================================--
	-- WORLD -- 3D, positioned, and the ONLY category other players hear. Every
	-- entry here is broadcast by the server and played locally by each client
	-- at the given position (see SoundBroadcast.luau for why it is a broadcast
	-- rather than a server-parented Sound).
	--
	-- EVERY rollOffMaxDistance here is justified in REPORT.md §2c against the
	-- map's real dimensions: the road runs from Z -4 to Z -2,964, the six lanes
	-- are 60 studs apart across a 360-stud road, and the plots sit at Z 108-192.
	--=======================================================================--

	-- WHAT: a player's landing on the scoring road -- the ordinary outcome, and
	--   the one that earns a mystery box.
	-- LENGTH: 0.3-0.5 s.
	-- CHARACTER: a solid, weighty impact. Dust and body, not a crash. This is
	--   the punctuation at the end of the flight and it should feel like
	--   arriving, not like crashing. One-shot.
	-- ROLLOFF 250: tiers land 320 studs apart in Z (see REPORT.md §2c), so at
	--   250 a player only ever hears landings from others on THEIR OWN tier --
	--   which is exactly the "someone landed near me" signal wanted -- and
	--   never one from an adjacent tier, let alone across the map.
	WORLD_LANDING_ROAD = {
		id = nil,
		volume = 0.9,
		pitch = 1.0,
		group = "WORLD",
		spatial = true,
		rollOffMinDistance = 15,
		rollOffMaxDistance = 250,
		looped = false,
		maxLifetimeSeconds = 4,
	},

	-- WHAT: a landing SHORT of the road -- a mistimed release, zero luck, no
	--   box. The whiff.
	-- LENGTH: 0.3-0.5 s.
	-- CHARACTER: duller and flatter than the road landing. A soft flop into
	--   dirt with no ring to it. It must be recognisably a WORSE sound than
	--   WORLD_LANDING_ROAD without being a punishment -- the player already
	--   knows, and the HUD already says so. One-shot.
	WORLD_LANDING_SHORT = {
		id = nil,
		volume = 0.8,
		pitch = 1.0,
		group = "WORLD",
		spatial = true,
		rollOffMinDistance = 15,
		rollOffMaxDistance = 250,
		looped = false,
		maxLifetimeSeconds = 4,
	},

	-- WHAT: a landing PAST the road, on the giant slime's platform -- the
	--   perfect top-tier launch that earns a treasure chest. The rarest and
	--   best landing in the game.
	-- LENGTH: 0.6-1.2 s. It may be longer than the other two; nothing follows
	--   it immediately (the player walks to the chest).
	-- CHARACTER: triumphant arrival. An impact with a bright ascending tail, or
	--   an impact layered with a short shimmer. It must be unmistakably the
	--   good one from the first tenth of a second. One-shot.
	-- ROLLOFF 250, same as the others: the platform is ~3,100 studs from
	--   everything else, so this is only ever heard by other players who are
	--   also on the platform.
	WORLD_LANDING_PAST = {
		id = nil,
		volume = 1.0,
		pitch = 1.0,
		group = "WORLD",
		spatial = true,
		rollOffMinDistance = 20,
		rollOffMaxDistance = 250,
		looped = false,
		maxLifetimeSeconds = 5,
	},

	-- WHAT: someone's swing releasing, heard at the swing itself. The
	--   world-facing half of a launch; the launcher's own copy is
	--   FLIGHT_RELEASE above.
	-- LENGTH: 0.3-0.5 s.
	-- CHARACTER: rope and timber under load, then release. Mechanical and
	--   woody rather than airy -- the air is the flyer's sound, this is the
	--   apparatus.
	-- ROLLOFF 120: the six swings sit 60 studs apart on one 360-stud row, so at
	--   120 a player hears their own lane and the two either side, not all six.
	--   See REPORT.md §2d -- this is the entry most exposed to six-way stacking
	--   and 120 is the number that bounds it to three.
	WORLD_LAUNCH_RELEASE = {
		id = nil,
		volume = 0.7,
		pitch = 1.0,
		group = "WORLD",
		spatial = true,
		rollOffMinDistance = 10,
		rollOffMaxDistance = 120,
		looped = false,
		maxLifetimeSeconds = 3,
	},

	-- WHAT: a player being auto-mounted onto their swing by proximity.
	-- LENGTH: 0.15-0.3 s.
	-- CHARACTER: a light creak and settle -- weight arriving on a seat. Very
	--   quiet. This fires on every single cycle for every player, so it is
	--   texture, not an event.
	-- ROLLOFF 120: same reasoning as the release above, and the same lane
	--   spacing.
	WORLD_SWING_MOUNT = {
		id = nil,
		volume = 0.4,
		pitch = 1.0,
		group = "WORLD",
		spatial = true,
		rollOffMinDistance = 10,
		rollOffMaxDistance = 120,
		looped = false,
		maxLifetimeSeconds = 2,
	},

	-- WHAT: the treasure chest's lid opening on the platform. The single
	--   biggest reward moment in the game (20% Divine), and the only one other
	--   players standing there should hear.
	-- LENGTH: 0.8-1.5 s.
	-- CHARACTER: a heavy wooden lid with metal fittings, hinges under strain,
	--   then a bright magical bloom as it opens. Two-part: mechanism, then
	--   payoff. This is the sound the whole ladder exists to reach.
	-- ROLLOFF 150: the platform is a small area ~3,100 studs from anything
	--   else, so this only ever carries to others standing on it. Slightly
	--   wider than a launch because it is rare and worth turning your head for.
	WORLD_CHEST_OPEN = {
		id = nil,
		volume = 1.0,
		pitch = 1.0,
		group = "WORLD",
		spatial = true,
		rollOffMinDistance = 20,
		rollOffMaxDistance = 150,
		looped = false,
		maxLifetimeSeconds = 6,
	},

	-- WHAT: the two-way conveyor walkway between the swings and the plots.
	--   Ambient; attached to each belt half by the client at startup.
	-- LENGTH: a SEAMLESSLY LOOPING bed, 2-5 seconds. Same seam warning as the
	--   flight loop, and more important here: this one never stops.
	-- CHARACTER: a low mechanical rumble with a faint roller texture. NO
	--   squeak, NO rhythmic clank -- anything with a recognisable period will
	--   drive players mad, because unlike every other sound in this file it is
	--   ALWAYS ON.
	-- ROLLOFF 40, the tightest in the file and deliberately so: the belt sits
	--   at Z 76 and the plots start at Z 108, so 40 studs keeps it audible on
	--   the approach and while riding, and effectively gone by the time a
	--   player is standing among their slimes. If any sound in this pass turns
	--   out to grate, it is this one -- it is the first to cut. See REPORT.md
	--   §2b.
	-- LOOPED, and the only always-on sound in the game.
	WORLD_CONVEYOR_LOOP = {
		id = nil,
		volume = 0.35,
		pitch = 1.0,
		group = "WORLD",
		spatial = true,
		rollOffMinDistance = 8,
		rollOffMaxDistance = 40,
		looped = true,
		maxLifetimeSeconds = 0,
	},

	--=======================================================================--
	-- REWARD -- the mystery box chain, the slime reveal and the chest reveal.
	-- All 2D and all on the rewarded player's own client: a reward is a private
	-- moment framed by a camera move, and the box hangs in front of that one
	-- player's face. The only part of it anyone else hears is WORLD_CHEST_OPEN.
	--=======================================================================--

	-- WHAT: the mystery box materialising in front of the player after a
	--   landing that earned luck.
	-- LENGTH: 0.4-0.8 s.
	-- CHARACTER: a magical appear -- a shimmer with a soft impact under it.
	--   Anticipatory. It is asking a question the press will answer. One-shot.
	REWARD_BOX_APPEAR = {
		id = nil,
		volume = 0.8,
		pitch = 1.0,
		group = "REWARD",
		spatial = false,
		looped = false,
		maxLifetimeSeconds = 3,
	},

	-- WHAT: each press of the box, before the result is known.
	-- LENGTH: 0.08-0.15 s. It must be shorter than BOX_PRESS_COOLDOWN_SECONDS
	--   (0.25) or presses will overlap themselves.
	-- CHARACTER: a dull thump -- knuckles on a crate. Deliberately
	--   unrewarding: it is the ACT of pressing, and the reward for it is the
	--   doubling sound that may follow. One-shot.
	REWARD_BOX_PRESS = {
		id = nil,
		volume = 0.6,
		pitch = 1.0,
		group = "REWARD",
		spatial = false,
		looped = false,
		maxLifetimeSeconds = 2,
	},

	-- WHAT: the box DOUBLED instead of opening -- the luck went up and the
	--   player may press again. Fires once per link in the chain.
	-- LENGTH: 0.15-0.3 s. Short, because at a 55% double chance a chain of five
	--   or six is routine and each link fires this.
	-- CHARACTER: a bright rising "ching" or arpeggio step. THE PITCH IS DRIVEN
	--   UP PER LINK by the caller (see REPORT.md §4a: +0.06 per doubling,
	--   clamped at 2.0), so pick something with a clear pitch centre that
	--   survives being transposed up an octave -- a bell or pluck, not noise.
	--   This is the game's escalation sound and the chain is the most exciting
	--   thing in the reward. One-shot.
	REWARD_BOX_DOUBLE = {
		id = nil,
		volume = 0.75,
		pitch = 1.0,
		group = "REWARD",
		spatial = false,
		looped = false,
		maxLifetimeSeconds = 2,
	},

	-- WHAT: the box opening -- the chain ended and it bursts.
	-- LENGTH: 0.3-0.6 s, and it must be clear of REVEAL_BOX_TO_SLIME_DELAY_
	--   SECONDS (0.6) so it does not still be ringing under the reveal.
	-- CHARACTER: a crack and burst -- something breaking open and scattering.
	--   Decisive. It resolves the tension the doubling chain built. One-shot.
	REWARD_BOX_OPEN = {
		id = nil,
		volume = 0.9,
		pitch = 1.0,
		group = "REWARD",
		spatial = false,
		looped = false,
		maxLifetimeSeconds = 3,
	},

	-- WHAT: the slime itself appearing, for EVERY tier. The caller pitches this
	--   down and raises its volume as the tier climbs (Common 1.15 down to
	--   Divine 0.90 -- see REPORT.md §4b), so one asset covers the whole range
	--   and a Common genuinely does not sound like a Divine.
	-- LENGTH: 0.5-0.9 s.
	-- CHARACTER: a soft organic rise with a bright bloom at the top -- the
	--   creature arriving. Must read correctly pitched a little either side of
	--   centre, so avoid anything with strong formants or a recognisable
	--   instrument that will sound obviously slowed.
	-- One-shot.
	REWARD_SLIME_REVEAL = {
		id = nil,
		volume = 0.8,
		pitch = 1.0,
		group = "REWARD",
		spatial = false,
		looped = false,
		maxLifetimeSeconds = 4,
	},

	-- WHAT: layered ON TOP of REWARD_SLIME_REVEAL for the top three tiers
	--   (Mythic, Secret, Divine -- tier >= RARE_REVEAL_MIN_TIER below). Pitch
	--   alone across eight tiers is a gradient; this is what makes the best
	--   pulls categorically different rather than just lower.
	-- LENGTH: 1.0-2.0 s. It may ring on under the reveal panel.
	-- CHARACTER: a fanfare or choral swell. Unashamedly celebratory. This is
	--   the sound a player should learn to recognise before they have read the
	--   name on screen. One-shot.
	REWARD_SLIME_REVEAL_RARE = {
		id = nil,
		volume = 0.95,
		pitch = 1.0,
		group = "REWARD",
		spatial = false,
		looped = false,
		maxLifetimeSeconds = 5,
	},

	-- WHAT: layered on a reveal of a slime this player has NEVER SEEN before.
	--   The `isNew` flag already arrives with the reveal (see LaunchServer's
	--   slimeRevealedRemote), so this costs nothing to know.
	-- LENGTH: 0.4-0.8 s.
	-- CHARACTER: a short discovery sting -- a bright "new!" flourish, clearly
	--   distinct from the rarity fanfare above, since both can fire together on
	--   a first Divine. Keep it thin and high so it sits ON TOP of the other
	--   two rather than fighting them for the same space. One-shot.
	REWARD_SLIME_NEW = {
		id = nil,
		volume = 0.7,
		pitch = 1.0,
		group = "REWARD",
		spatial = false,
		looped = false,
		maxLifetimeSeconds = 3,
	},

	-- WHAT: the chest's own reveal, on the opening player's client -- the slime
	--   rising out of the chest. Distinct from REWARD_SLIME_REVEAL because the
	--   chest is a 20%-Divine table and the single biggest reward in the game;
	--   it should not share its sound with an ordinary box pull.
	-- LENGTH: 1.5-2.5 s.
	-- CHARACTER: a grand ascending swell -- the biggest sound in the file. It
	--   plays over WORLD_CHEST_OPEN's mechanism, so it should occupy a
	--   different register: that one is wood and metal, this one is light and
	--   air. One-shot.
	REWARD_CHEST_REVEAL = {
		id = nil,
		volume = 1.0,
		pitch = 1.0,
		group = "REWARD",
		spatial = false,
		looped = false,
		maxLifetimeSeconds = 6,
	},
}

local SoundConfig = {
	-- The master group's volume; every category above is nested inside it, so
	-- this is the one number that moves all audio at once. 1.0 leaves the
	-- per-group levels as authored. The mute toggle drives THIS, not the
	-- individual groups, so unmuting always restores exactly the authored mix.
	MASTER_VOLUME = 1.0,
	GROUP_VOLUMES = GROUP_VOLUMES,
	GROUP_ORDER = GROUP_ORDER,
	-- Matches DevConfig.TOGGLE_KEYCODE's pattern -- a named key constant rather
	-- than a literal at the input site. M for mute. There is also an on-screen
	-- button, since a keybind alone excludes every touch player (see
	-- SoundClient.client.luau).
	MUTE_TOGGLE_KEYCODE = Enum.KeyCode.M,
	SOUNDS = SOUNDS,
}

-- Lowest slime tier that also gets REWARD_SLIME_REVEAL_RARE layered on top.
-- 6 = Mythic, against SlimeConfig.SLIME_TIER_NAMES' eight tiers (Common,
-- Uncommon, Rare, Epic, Legendary, Mythic, Secret, Divine) -- so the top THREE
-- tiers are categorically louder and everything below is on the pitch gradient.
-- Deliberately not 8 (Divine only): Secret and Mythic are rare enough to be
-- worth celebrating, and a threshold that fires only on the single rarest tier
-- would almost never be heard.
SoundConfig.RARE_REVEAL_MIN_TIER = 6

-- ===== ASSERTED AT LOAD, because both of these are silent failures otherwise.
-- A spatial entry with no rollOffMaxDistance falls back to Roblox's default
-- attenuation, which on a 3,000-stud map means audible from everywhere; a bad
-- group name means the sound is created with no SoundGroup and escapes the
-- mixer entirely. Neither would error at runtime -- they would just sound
-- wrong, which is exactly the class of bug nobody can hear their way to here.
local validGroups: { [string]: boolean } = {}
for _, groupName in GROUP_ORDER do
	validGroups[groupName] = true
	assert(
		GROUP_VOLUMES[groupName] ~= nil,
		string.format("SoundConfig: group %q is in GROUP_ORDER but has no entry in GROUP_VOLUMES", groupName)
	)
end

for key, entry in SOUNDS do
	assert(
		validGroups[entry.group],
		string.format("SoundConfig: entry %q has group %q, which is not one of the four in GROUP_ORDER", key, entry.group)
	)
	if entry.spatial then
		assert(
			typeof(entry.rollOffMaxDistance) == "number" and entry.rollOffMaxDistance > 0,
			string.format("SoundConfig: entry %q is spatial but has no positive rollOffMaxDistance -- it would be audible across the whole map", key)
		)
		assert(
			typeof(entry.rollOffMinDistance) == "number" and entry.rollOffMinDistance < (entry.rollOffMaxDistance :: number),
			string.format("SoundConfig: entry %q needs a rollOffMinDistance below its rollOffMaxDistance", key)
		)
	else
		assert(
			entry.rollOffMaxDistance == nil and entry.rollOffMinDistance == nil,
			string.format("SoundConfig: entry %q is 2D but carries rolloff distances, which would be ignored -- drop them or set spatial = true", key)
		)
	end
	-- The id is the ONE field allowed to be nil, and it is nil for every entry
	-- as this ships. Asserting its TYPE still catches a typo'd number or a bare
	-- id with no "rbxassetid://" prefix the moment someone fills one in.
	assert(
		entry.id == nil or (typeof(entry.id) == "string" and string.match(entry.id, "^rbxassetid://%d+$") ~= nil),
		string.format("SoundConfig: entry %q has an id that is not nil and not a well-formed \"rbxassetid://<number>\" string", key)
	)
end

return SoundConfig

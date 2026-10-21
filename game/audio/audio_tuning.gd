extends RefCounted
## Every tunable number of the audio unit, with its unit. The logic files must not contain bare
## literals (except 0, 1 and 0.5) — everything that can be tuned lives here.
##
## Load it with: const Tuning := preload("res://audio/audio_tuning.gd")

# --- buses and mixing ----------------------------------------------------------------------------------
## The one-shot pool: the 2D players and the 3D ones (the hard cap is their sum).
const POOL_2D := 16
const POOL_3D := 8
## How much the music bed is ducked while a voice line plays (dB, positive number).
const DUCK_DB := 6.0
const DUCK_ATTACK_S := 0.18
const DUCK_RELEASE_FACTOR := 0.6
## The sub-bus the music bed plays on (a child of the Music bus).
const MUSIC_BUS := &"MusicBed"
## The master limiter: the ceiling and the release.
const LIMITER_CEILING_DB := -1.0
const LIMITER_RELEASE_S := 0.1
## The level a silent player sits at.
const SILENT_DB := -60.0
## The full scale of a 16 bit sample (the hiss table is read as integers).
const S16_SCALE := 32768.0
## The seconds per minute (the whine fundamental is rpm / 60 * POLE_PAIRS).
const SECONDS_PER_MINUTE := 60.0
## The highest frequency a filter of the unit is opened to.
const FILTER_MAX_HZ := 20000.0
## The N2 tank that counts as one slot ("氮气就绪" is announced per slot).
const N2_TIER_AMOUNT := 100.0
## The 3D one-shot players.
const POOL_MAX_DISTANCE_M := 120.0
const POOL_UNIT_SIZE := 8.0

# --- music bed ------------------------------------------------------------------------------------------
## Equal-power crossfade time between two music states (s).
const MUSIC_CROSSFADE_S := 2.0
## The menu state filters the bed instead of detuning it.
const MENU_LOWPASS_HZ := 1200.0
const MENU_LOWPASS_SWEEP_S := 0.6
## Target level of each music state on the MusicBed bus (dB).
const MUSIC_LEVEL_MENU_DB := -10.0
const MUSIC_LEVEL_CRUISE_DB := -6.0
const MUSIC_LEVEL_PURSUIT_DB := -3.0
const MUSIC_LEVEL_RACE_DB := -3.0
## The ambience bed (the city and the rain) can be switched off (the demo does that).
const AMBIENCE_CITY_DB := 0.0
const AMBIENCE_RAIN_DB := -3.0

# --- collisions -----------------------------------------------------------------------------------------
## The minimum impulse that counts as a hit (N.s).
const IMPACT_MIN_IMPULSE_NS := 1500.0
## The impulse (N.s) that picks the impact severity.
const IMPULSE_HEAVY := 12000.0
const IMPULSE_MEDIUM := 3000.0
const IMPULSE_SCALE := 15000.0
## The minimum gap between two impacts of the same car (s).
const IMPACT_COOLDOWN_S := 0.15
## The scrape loop follows a sustained contact and fades out this long after the last hit (s).
const SCRAPE_FADE_S := 0.15
## The scrape loop is silent below this level (dB).
const SCRAPE_FADE_EPSILON_DB := 0.5
## The scrape level at the strongest impulse, and the level of the player car.
const SCRAPE_MAX_DB := -6.0
const SCRAPE_PLAYER_DB := -3.0
## The scrape level never drops below this share of the strongest impulse.
const SCRAPE_MIN_NORM := 0.25
## A scrape needs a repeated contact: the same car has to hit again within this window (s).
const SCRAPE_REPEAT_S := 0.2
## The scrape pitch with the speed.
const SCRAPE_PITCH_MIN := 0.9
const SCRAPE_PITCH_SPAN := 0.3

# --- mix trims of the one-shots -------------------------------------------------------------------------
const IMPULSE_LEVEL_DB := 4.0
const IMPACT_MIX_DB := -4.0
const GLASS_MIX_DB := -6.0
const BOOST_IGNITE_MIX_DB := -1.0
const BOOST_READY_MIX_DB := -8.0
const BOOST_READY_PITCH := 1.3
const COUNTDOWN_BEEP_MIX_DB := -4.0
const COUNTDOWN_GO_MIX_DB := -3.0
const MINI_BOOST_MIX_DB := -3.0
const HOP_RELEASE_MIX_DB := -6.0
const HOP_EXIT_MIX_DB := -8.0
const HOP_EXIT_PITCH := 0.8
const LAND_MIX_DB := -6.0
const LAND_LEVEL_SCALE := 25.0
const LAND_PITCH_MIN := 0.92
const LAND_PITCH_SPAN := 0.2
const NEAR_MISS_MIX_DB := -6.0
const SKY_LANE_MIX_DB := -4.0
const SKY_LANE_PITCH := 1.15
const RING_CHIME_MIX_DB := -6.0
const RING_CHIME_PITCH := 1.6
const CHARGE_ZAP_MIX_DB := -3.0
const CHARGE_CHIME_MIX_DB := -4.0
const TAKEDOWN_MIX_DB := -2.0
## The pitch tweaks of the one-shots.
const HOP_RELEASE_PITCH := 1.2
## A charge has to refill more than this to play the chime.
const CHARGE_FULL_AMOUNT := 0.5
## A drift has to last this long before it counts as clean.
const DRIFT_CLEAN_MIN_S := 0.5

# --- player drive voice ---------------------------------------------------------------------------------
## The whine fundamental is rpm / 60 * POLE_PAIRS.
const POLE_PAIRS := 4.0
## The inharmonic "inverter" partials of the whine.
const PARTIAL_2 := 2.76
const PARTIAL_3 := 5.41
## The partial mix moves with the motor load (the timbre opens under throttle).
const PARTIAL_2_GAIN_MIN := 0.12
const PARTIAL_2_GAIN_MAX := 0.30
const PARTIAL_3_GAIN_MIN := 0.04
const PARTIAL_3_GAIN_MAX := 0.14
## A partial is muted above this fraction of the mix rate.
const PARTIAL_CUTOFF_RATIO := 0.45
## The drive voice level at zero load and at full load.
const WHINE_LEVEL_MIN := 0.45
const WHINE_LEVEL_MAX := 1.0
## The rpm per km/h, and the idle rpm floor so a standing start still whines.
const RPM_PER_KMH := 60.0
const RPM_IDLE := 3200.0
const RPM_MAX := 20000.0
## The rpm at which the whine reaches its full level.
const RPM_FULL := 2500.0
## Below this frequency the oscillators are silent (a zero frequency is unstable).
const MOTOR_MIN_HZ := 5.0
## A rotator state below this magnitude is reset (a state of zero would stay silent).
const ROTATOR_MIN_MAGNITUDE := 0.0001
## The road and wind beds (looping OGG) instead of noise inside the synth.
const ROAD_BED_ID := &"road_roll"
const WIND_BED_ID := &"wind_rush"
## The road layer is proportional to speed, the wind to speed squared.
const SPEED_MAX_KMH := 300.0
## The road and the wind beds sit this far under their loudest level (dB).
const ROAD_MIX_OFFSET_DB := -2.0
const WIND_MIX_OFFSET_DB := -4.0
## The smallest level the road and the wind beds are ever driven to (a linear factor).
const ROAD_MIN_NORM := 0.02
const WIND_MIN_NORM := 0.01
## The tyre squeal starts at this rear slip and is trimmed by this many dB.
const SQUEAK_SLIP_MIN := 0.15
const SQUEAK_TRIM_DB := -6.0
## The squeal pitch with the slip, and how fast it fades in and out.
const SQUEAK_PITCH_MIN := 0.92
const SQUEAK_PITCH_SPAN := 0.2
const SQUEAK_FADE_RATE := 8.0
## The boost roar sits this far above the motor at full thrust (dB).
const BOOST_ROAR_MIX_OFFSET_DB := 5.0
## The roar follows the rear nozzles from this level up, and its pitch follows the speed.
const BOOST_ROAR_REAR_MIN := 0.15
const BOOST_ROAR_SPAN := 6.0
const BOOST_ROAR_FADE_RATE := 10.0
const BOOST_ROAR_PITCH_MIN := 1.0
const BOOST_ROAR_PITCH_SPAN := 0.08
## Wind pitch rises with speed (gameplay DOSSIER §8.5: 0.8 -> 1.3).
const WIND_PITCH_MIN := 0.8
const WIND_PITCH_MAX := 1.3
## The road bed's pitch range with the speed.
const ROAD_PITCH_MIN := 0.85
const ROAD_PITCH_SPAN := 0.35
## The fan whine: 1.5 kHz at rest, 3 kHz at full downforce, this far under the motor.
const FAN_HZ_MIN := 1500.0
const FAN_HZ_MAX := 3000.0
const FAN_LEVEL_DB := -18.0
## The fan never goes fully silent (it idles at this share of the full level).
const FAN_FLOOR := 0.25
## Downforce in kg that counts as "full suction".
const DOWNFORCE_MAX_KG := 4700.0
## Output gain of the drive voice (dB) — the level the car sits at in the mix.
const EV_OUTPUT_GAIN_DB := -2.0
## The drive voice is high-passed so the whine carries no DC.
const DC_BLOCK_HZ := 20.0

# --- the player's own synth voices ---------------------------------------------------------------------
## The audio sphere of the two synth voices (m). The player hears its own car from inside it,
## so the sphere has to cover the chase camera (6-9 m behind the car), otherwise the motor
## whine is attenuated by 15 dB and inaudible in the mix.
const SYNTH_UNIT_SIZE_M := 30.0
## How far the synth voices can be heard (m).
const SYNTH_MAX_DISTANCE_M := 200.0

# --- thruster voice -------------------------------------------------------------------------------------
## The envelope of the nozzle groups. The attack is the 10% -> 90% span (a sharp jet), the release
## is the time constant (it reaches -8.7 dB after exactly one time constant).
const THRUSTER_ATTACK_S := 0.030
const THRUSTER_RELEASE_S := 0.120
## The 10% -> 90% span of a one-pole envelope, in time constants.
const THRUSTER_ATTACK_SPAN_TAU := 2.197
## The Q of the low-pass of the rear body layer (the hiss table itself is generated offline
## by tools/audio/gen_noise_table.py, which is the single source of its filter chain).
const HISS_FILTER_Q := 0.707
## The rear group adds a low body layer under the hiss.
const REAR_BODY_HZ := 900.0
const REAR_BODY_DB := -12.0
## The group sums are normalised: rear / 4 nozzles, perimeter / 6, then square-rooted.
const REAR_NOZZLE_COUNT := 4.0
const PERIMETER_NOZZLE_COUNT := 6.0
## The rear group is this many dB louder than the perimeter group at full thrust.
const REAR_GROUP_TRIM_DB := 3.0
## The hiss pitch follows the thrust by +-5 % (DOSSIER §6.3).
const THRUSTER_PITCH_SWING := 0.05
## Above this the nozzle groups count as firing.
const THRUSTER_ACTIVE_EPSILON := 0.02
## Above this the hop charge tone is audible.
const HOP_ACTIVE_EPSILON := 0.01
## The tremolo of the hop charge tone: a floor and a span.
const HOP_TREMOLO_MIN := 0.78
const HOP_TREMOLO_SPAN := 0.22
## Below this the chuff has died away.
const CHUFF_MIN_LEVEL := 0.001
## The pneumatic chuff on cut-off.
const CHUFF_ATTACK_S := 0.002
const CHUFF_DECAY_S := 0.040
const CHUFF_BURST_S := 0.090
const CHUFF_CENTRE_HZ := 1200.0
const CHUFF_Q := 1.0
const CHUFF_LEVEL := 0.28
const CHUFF_PUFF_HZ := 90.0
const CHUFF_PUFF_DB := -12.0
const CHUFF_PUFF_S := 0.05
## The puff is a tone, the burst is noise: the trim puts the tone 12 dB under the burst.
const CHUFF_PUFF_TRIM := 0.39
## Big Hop charge tone: a detuned saw pair through a resonant low-pass that opens.
const HOP_TONE_LOW_HZ := 220.0
const HOP_TONE_HIGH_HZ := 880.0
const HOP_TONE_GAIN := 0.16
## The detune of the two saws and the filter of the charge tone.
const HOP_DETUNE := 1.004
const HOP_FILTER_LOW_HZ := 500.0
const HOP_FILTER_HIGH_HZ := 4000.0
const HOP_FILTER_Q := 1.2
const HOP_TREMOLO_MIN_HZ := 4.0
const HOP_TREMOLO_MAX_HZ := 14.0
## Output gain of the thruster voice (dB) — the level the thrusters sit at in the mix.
const THRUSTER_OUTPUT_GAIN_DB := -3.0

# --- battery warning -----------------------------------------------------------------------------------
## The battery warning is edge triggered: it arms below ON and re-arms above OFF.
const BATTERY_LOW_ON := 0.15
const BATTERY_LOW_OFF := 0.20
const BATTERY_BEEP_INTERVAL_S := 4.0
const BATTERY_BEEP_MIX_DB := -8.0

# --- one-shot pool --------------------------------------------------------------------------------------
## The ids whose file is a seamless loop: they need a dedicated player, not the pool.
const LOOP_IDS: Array[StringName] = [
	&"scrape_loop", &"boost_roar_loop", &"thruster_hiss_loop", &"siren_wail", &"siren_yelp",
	&"traffic_ev_hum", &"tyre_squeal", &"city_ambience", &"rain_layer", &"river_ambience",
	&"road_roll", &"wind_rush",
]
## The seconds per millisecond (the timestamps use milliseconds).
const SECONDS_PER_MS := 0.001

# --- voice queue ---------------------------------------------------------------------------------------
## Priorities: 0 = never cut, 1 = queued, 2 = dropped when busy.
const VOICE_PRIORITY_NEVER_CUT := 0
const VOICE_PRIORITY_QUEUED := 1
const VOICE_PRIORITY_DROP := 2
## How long a queued line waits before it is dropped (s). P0 lines never time out.
const VOICE_QUEUE_TIMEOUT_S := 2.0
## The voice queue keeps at most this many waiting lines per channel.
const VOICE_QUEUE_MAX := 4
## The timestamp of a line that was never played.
const VOICE_NO_PREVIOUS := -99.0
## The minimum gap between two lines of the same id (s).
const VOICE_REPEAT_GAP_S := 4.0
## How often a repeating warning (battery low) may fire (s).
const VOICE_WARNING_GAP_S := 30.0
## The radio channel is quieter than the announcer.
const VOICE_RADIO_TRIM_DB := -2.0

# --- world emitters -------------------------------------------------------------------------------------
## How far a traffic car can be and still be heard.
const TRAFFIC_EMITTER_RANGE_M := 60.0
const TRAFFIC_EMITTER_MAX := 6
## The reach of the emitter players.
const EMITTER_MAX_DISTANCE_M := 220.0
## The mix trim of every emitter kind (dB) and the size of its audio sphere (m). The sphere is
## the distance at which the sound is heard at its full level: at twice the sphere it is 6 dB
## quieter (the engine's own attenuation).
const SIREN_EMITTER_DB := 0.0
const SIREN_UNIT_SIZE_M := 20.0
const HUM_EMITTER_DB := -6.0
const HUM_UNIT_SIZE_M := 6.0
const RIVER_EMITTER_DB := -8.0
const RIVER_UNIT_SIZE_M := 30.0
## The audio sphere of an emitter kind without its own value (m).
const EMITTER_DEFAULT_UNIT_SIZE_M := 8.0
## The police sirens: they only exist from this heat on.
const HEAT_SIREN_FROM := 1
const HEAT_YELP_FROM := 3
## The heat at which the police show up, the pursuit music starts and the heat is announced.
const HEAT_POLICE_FROM := 1
const HEAT_PURSUIT_FROM := 2
const HEAT_MAX_FROM := 5
const POLICE_EMITTER_RANGE_M := 220.0
const POLICE_EMITTER_MAX := 3
const POLICE_YELP_RANGE_M := 40.0
## How often a police car switches between the wail and the yelp (s).
const POLICE_YELP_PERIOD_S := 6.0
## The crossfade between the wail and the yelp (s). Both samples keep playing, so a switch
## never restarts a sample and never cuts.
const SIREN_CROSSFADE_S := 0.05
## The river bed is heard within this radius of the river.
const RIVER_EMITTER_RANGE_M := 150.0
## How often the world emitters re-scan the groups (s).
const EMITTER_SCAN_INTERVAL_S := 0.5
## The distance that counts as "far" when the player is unknown.
const EMITTER_FAR_DISTANCE_M := 9999.0
## The level an emitter fades in from and out to (dB).
const EMITTER_FADE_START_DB := -40.0
## The fade time of an emitter (s): the fade covers the span from the start level to the mix.
const EMITTER_FADE_S := 0.3
## The traffic hum follows the car's speed.
const HUM_PITCH_MIN := 0.8
const HUM_PITCH_MAX := 1.3
const HUM_PITCH_SPEED_KMH := 100.0
## The police horn is played on the patrol cars every few seconds.
const POLICE_HORN_INTERVAL_S := 8.0
const POLICE_HORN_RANGE_M := 30.0
const POLICE_HORN_MIX_DB := -6.0
## The traffic horn is played when the traffic unit asks for it.
const TRAFFIC_HORN_MIX_DB := -6.0
## The radio squelch before and after a police radio line.
const RADIO_SQUELCH_MIX_DB := -10.0

# --- the demo ------------------------------------------------------------------------------------------
## The level of the loop beds in the demo scene (dB) and the music (the game's bed level).
const DEMO_LOOP_DB := 0.0
const DEMO_MUSIC_DB := -6.0
## The meter turns amber above this level (dBFS).
const METER_WARN_DB := -3.0

# --- slow motion and the game pause ---------------------------------------------------------------------
## The slow-motion takedown cam: the SFX bus is pitched down and low-passed.
const SLOWMO_PITCH := 0.7
const SLOWMO_LOWPASS_HZ := 2000.0
const SLOWMO_LOWPASS_HZ_MAX := 20000.0
## The time scale below which the slow-motion effect switches on.
const SLOWMO_TRIGGER_SCALE := 0.9
## While the game is paused the gameplay players are stream-paused and the bed goes to the menu.
const PAUSE_MENU_STATE := &"menu"

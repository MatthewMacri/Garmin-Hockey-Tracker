//
// Indoor Hockey - game clock, automatic shift tracking and the FIT session.
//
// All state lives here. Views read it and draw; they keep nothing of their own.
//
// The design assumption is that the watch is not touched once the game starts.
// One press begins the game; after that every shift boundary is worked out by
// the app. Everything in here that would normally be a button is therefore
// driven from a clock or a sensor.
//
// There is no period model. The app used to run a game as three twenty-minute
// periods with intermissions between them, and end it when the last one
// expired - which on 2026-11-03 closed a recording at exactly 3600s while the
// game was still being played. The periods were a fiction anyway: a real game
// is longer than the sum of its periods, its clock stops for things the watch
// cannot see, and nothing here ever knew the real score or the real time.
//
// So a game is now one continuous recording with one clock, which starts when
// the player starts it and ends when the player ends it. What this app is
// actually good at - finding shift boundaries from wrist motion, and splitting
// heart rate into ice and bench - never needed periods to work.
//

import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Application;
import Toybox.Attention;
import Toybox.FitContributor;
import Toybox.Lang;
import Toybox.Position;
import Toybox.System;
import Toybox.UserProfile;
import Toybox.WatchUi;

//! Where the game currently is.
//! How long START has to be held down to pause the game.
//!
//! File scope because the hold is timed in GameModel and rendered from
//! GameView, and both have to agree on the threshold.
const PAUSE_HOLD_MS = 1000;

enum GameState {
    STATE_READY = 0,     //!< Nothing started; no FIT session yet.
    STATE_RUNNING = 1,   //!< Clock moving, session recording.
    STATE_PAUSED = 2,    //!< Manually stopped.
    STATE_FINISHED = 3   //!< Session saved or discarded; summary on screen.
}

//! Which FIT sport the finished activity is filed under. Hockey is the truthful
//! answer; skate is the one Strava can read. See hockeySport().
enum ActivityType {
    ACTIVITY_HOCKEY = 0, //!< FIT sport 73 / sub-sport 91: ice hockey.
    ACTIVITY_SKATE = 1   //!< FIT sport 33: ice skating.
}

//! Owns the whole game.
class GameModel {

    // Developer FIT field ids. These end up in the FIT file, so they are stable:
    // changing one changes how previously recorded games are read.
    private const FIELD_SHIFTS      = 0;
    private const FIELD_ICE_TIME    = 1;
    private const FIELD_BENCH_TIME  = 2;
    private const FIELD_AVG_SHIFT   = 3;
    private const FIELD_MAX_SHIFT   = 4;
    private const FIELD_WORK_REST   = 5;
    private const FIELD_ICE_HR      = 6;
    private const FIELD_HARD_TIME   = 7;
    private const FIELD_LAP_SHIFT   = 8;
    private const FIELD_LAP_BENCH   = 9;
    private const FIELD_ON_ICE      = 10;
    private const FIELD_CUR_SHIFT   = 11;

    // Diagnostics. These exist so a recorded game can be replayed against the
    // detector afterwards and its thresholds tuned against real skating, which
    // is the one thing that cannot be tested in the simulator. Garmin does not
    // record wrist acceleration into a FIT file, so unless the app writes this
    // itself the signal the detector runs on is gone the moment the game ends.
    private const FIELD_MOTION      = 12;
    private const FIELD_THRESHOLD   = 13;
    private const FIELD_STRIDE_R    = 15;
    private const FIELD_STRIDE_LAG  = 16;
    private const FIELD_STRIDE_PROM = 27;
    private const FIELD_BENCH_RECOV = 28;
    private const FIELD_SHIFT_FADE  = 29;
    private const FIELD_HR_DRIFT    = 30;

    //! The least coverage at which an average stride rate is worth
    //! publishing: one accepted second in twenty of the seconds actually
    //! examined. Below this the rate is an anecdote.
    private const STRIDE_MIN_COVERAGE = 5;

    // Stride rate, measured by autocorrelating wrist acceleration. The rate is
    // charted; the confidence and winning lag above are diagnostics on the same
    // footing as FIELD_MOTION - they are what a recorded game needs to settle
    // the acceptance gates against real skating rather than synthetic signals.
    private const FIELD_STRIDE_RATE = 14;
    private const FIELD_STRIDE_AVG  = 17;
    private const FIELD_STRIDE_COV  = 18;

    // Distance and speed are written when a stride length is available from
    // EITHER source: the player's own setting, or one this app learned from
    // GPS on a day it had a fix (see calibrateStride()). With neither they
    // stay absent rather than reporting a zero. There is no published stride
    // length for skating and nothing on the wrist can measure one directly,
    // so the alternative to having one is inventing a number.
    private const FIELD_DIST_EST    = 19;
    private const FIELD_SPEED_EST   = 20;

    // Per-shift heart rate, so the Splits tab reads as an intensity chart
    // rather than a list of durations. Lap scope: one value per shift and
    // per bench spell.
    private const FIELD_LAP_AVG_HR  = 21;
    private const FIELD_LAP_MAX_HR  = 22;

    // Heart-rate recovery: beats dropped in the first 60 seconds of a bench
    // spell, averaged over the spells long enough to measure. A fitness
    // number rather than a game number - it should improve across a season
    // while the shift counts stay the same.
    private const FIELD_HR_RECOVERY = 23;

    // Accumulated on-ice load. See ShiftDetector.iceLoad.
    private const FIELD_ICE_LOAD    = 24;
    private const FIELD_STRIDE_LEN  = 25;
    private const FIELD_INTENSITY   = 26;

    // ---- settings, refreshed whenever Garmin Connect pushes a change ----
    public var shiftTargetMs as Number = 60 * 1000;

    //! Buzz once a shift passes shiftTargetMs. Off by default since 2.5.6.
    //!
    //! It shipped ON with a 60-second target, and that combination is wrong
    //! for the player this app is for. Measured on the 2026-11-09 game: 25
    //! shifts, median 76 s, and 16 of them past 60 s. So this fired sixteen
    //! times in 74 minutes, each time a TONE_ALERT_HI plus a 500 ms / 150 /
    //! 500 ms double buzz, to tell a defenceman that a 76-second shift was
    //! long. For a defenceman at four D it was not long; it was normal.
    //!
    //! 2.5.4 answered a player who said the change-buzz "becomes an
    //! annoyance" by adding changeAlerts, defaulted off, and the reasoning
    //! given there was that off is the right default for an app whose whole
    //! claim is that you start it and forget it. That reasoning applies here
    //! and was not applied here: the louder of the two alerts was left on.
    //! The owner played a game on 2.5.5 and reported it was "buzzing and
    //! beeping a lot", with changeAlerts already off.
    //!
    //! Still worth having for anyone trying to hold a shift to a target, so
    //! the setting stays - it just no longer assumes that is why you are
    //! wearing it. Note this is not the only buzz in a game: addLap() fires
    //! at every segment change (49 times in that game) and the lap alert
    //! that follows is the watch's, which no app setting here can silence.
    public var shiftAlerts as Boolean = false;

    //! When START went down during a game, as a System.getTimer() reading, or
    //! -1 when no hold is in progress.
    //!
    //! The hold is timed here rather than in GameDelegate because two other
    //! objects have to be able to end it - the delegate on the key coming up,
    //! the view on losing the screen - and the model is the only thing both of
    //! them can see. See beginPauseHold() for why the view gets a say.
    private var _pauseHoldSince as Number = -1;

    //! Buzz on every change between on-ice and bench. Off by default.
    //!
    //! This buzz had no setting at all until 2.5.4 - shiftAlerts gates the
    //! long-shift alert and nothing gated this one, so a player who found it
    //! annoying had no way to stop it. One did, on 2026-11-09: "the
    //! vibration when changing between bench and on ice is unnecessary and
    //! becomes an annoyance... I don't need to be alerted that I'm sitting
    //! on the bench. I already know I'm sitting down."
    //!
    //! Off is the right default for an app whose whole claim is that you
    //! start it and forget it. The buzz tells a player something they can
    //! see by looking, and its only real use is noticing a misdetection in
    //! time to correct it - which is a thing to opt into, not out of.
    public var changeAlerts as Boolean = false;
    public var autoLap as Boolean = true;
    public var useGps as Boolean = true;
    public var sensitivity as Number = 1;
    public var activityType as Number = ACTIVITY_HOCKEY;

    //! Milliseconds off the ice before the game ends itself. 0 turns it off.
    public var endIdleMs as Number = 25 * 60 * 1000;

    //! Centimetres covered by one skating push, as supplied by the player.
    //! 0 means "do not estimate distance", which is the default.
    public var strideLengthCm as Number = 0;
    //! Maximum heart rate for the 85% threshold; 0 means use the profile.
    public var maxHeartRate as Number = 0;

    //! The stride length actually used this game, in centimetres: the
    //! player's setting if they gave one, otherwise the one GPS taught the
    //! app on some earlier day. Resolved once, when the session is created,
    //! because a FIT field cannot be added to a session already running.
    public var usedStrideCm as Number = 0;

    // ---- GPS stride calibration ----
    //
    // Stride length is the one term in speed = rate x length that a wrist
    // cannot measure, and asking the player to skate a measured length is a
    // tax most will not pay. But the watch already has a second opinion on
    // the days it can get one: when GPS has a fix AND the stride meter has a
    // rhythm in the same second, length is simply speed divided by rate. That
    // never happens in this rink - 0 fixes in 5011 records - but it happens
    // at an outdoor rink, on a pond, and in arenas with enough glass, and it
    // costs nothing on the days it does not.
    //
    // Learned once and kept: the number is a property of the skater, not of
    // the day. Marino found stride length barely moves with velocity within
    // one skater, which is exactly what makes a stored constant defensible
    // and a per-second estimate not.
    private const CAL_KEY = "learnedStrideCm";
    private const CAL_MIN_SPEED = 1.5;      // m/s; below this nobody is skating
    private const CAL_MIN_CM = 100;         // a stride shorter than a metre
    // Matched to the Stride length setting's own maximum of 500, so a learned
    // value can never be one the player is not allowed to type. They were 600
    // and 500, which meant a calibration could outrank the range it claimed
    // to belong to.
    private const CAL_MAX_CM = 500;
    private const CAL_MIN_SAMPLES = 30;     // half a minute of agreement
    private var _calSum as Number = 0;
    private var _calCount as Number = 0;

    // Mean on-ice wrist motion, for the intensity index.
    private var _iceMotionSum as Number = 0;
    private var _iceMotionSamples as Number = 0;
    // Fewest on-ice seconds the intensity index may be built from. Half a
    // minute of ice is the least that says anything about how a game was
    // skated; below it the mean is one burst.
    private const INTENSITY_MIN_SAMPLES = 30;

    // ---- live game state ----
    public var state as GameState = STATE_READY;
    public var shiftCount as Number = 0;

    // Summary values, captured before the session is handed back to the system.
    public var finalAvgHr as Number = 0;
    public var finalMaxHr as Number = 0;
    public var finalCalories as Number = 0;

    // Clocks are kept as "time already banked" plus "running since", both in
    // milliseconds from System.getTimer(), which is monotonic.
    private var _gameAccumMs as Number = 0;
    private var _gameSince as Number = -1;

    // Shift and bench clocks run on wall time, not game time. Recovery happens
    // during whistles too, so a bench spell that spans a stoppage is longer
    // than the game clock says it is.
    private var _segmentSince as Number = -1;
    // The segment clock is banked the same way the game clock is, so that a
    // pause does not land in ice or bench time. See pause().
    private var _segmentAccumMs as Number = 0;
    private var _iceMs as Number = 0;
    private var _benchMs as Number = 0;
    private var _completedShiftMs as Number = 0;
    private var _completedShiftCount as Number = 0;
    private var _longestShiftMs as Number = 0;
    private var _shiftAlerted as Boolean = false;

    // Heart rate accumulated separately for on-ice seconds and for the whole
    // game. The difference between the two is the number this app exists to
    // produce: a game average includes the bench and badly understates how hard
    // the player was actually working.
    // Per-segment heart rate, reset at every shift and bench boundary.
    private var _segHrSum as Number = 0;
    private var _segHrSamples as Number = 0;
    private var _segHrMax as Number = 0;

    // Heart-rate recovery.
    //
    // Both ends of the measurement are averaged over five seconds rather than
    // read as a single sample. A wrist optical sensor at 1 Hz carries several
    // beats of jitter, and HRR60 is a difference between two numbers: the
    // jitter in each one lands in the result at full size. Five samples cuts
    // it by better than half, and five seconds either side of the minute mark
    // is far shorter than the timescale the curve itself moves on.
    //
    // _recoveryFrom is the averaged rate as the shift ended; _recoverySeconds
    // counts the bench spell; _recoveryEnd* collect the window at the far end.
    // All are armed only by a shift ending, so the pre-game bench, which has
    // no exertion behind it, never contributes.
    private const HRR_WINDOW = 5;       // samples averaged at each end
    private const HRR_AT = 60;          // the "60" in HRR60
    // First second of the far window, chosen so the HRR_WINDOW samples it
    // starts are centred on HRR_AT: 60 - (5 - 1) / 2 = 58, covering 58..62.
    private const HRR_START = HRR_AT - ((HRR_WINDOW - 1) / 2);
    private const HRR_GIVE_UP = 70;     // stop waiting for a usable sample
    // Fewest far-end samples that may stand as a measurement. A five-second
    // mean was the whole point of the window; one sample carries the several
    // beats of jitter a 1 Hz optical sensor has, at full size, straight into
    // a difference of two numbers.
    private const HRR_MIN_END = 3;
    // The longest a transition can be dated back by, so the longest a
    // committed recovery stays revocable. Matches the detector's widest
    // confirmation window.
    private const HRR_ROLLBACK = 14;
    private var _recoveryFrom as Number = 0;
    private var _recoverySeconds as Number = -1;
    private var _recoverySum as Number = 0;
    private var _recoveryCount as Number = 0;
    private var _recoveryEndSum as Number = 0;
    private var _recoveryEndCount as Number = 0;
    // The last recovery committed, and how many seconds ago. A transition is
    // dated back by the window that confirmed it, so the final seconds of a
    // bench spell can be reassigned to the shift AFTER a recovery has already
    // averaged them in. -1 means there is nothing that could still be taken
    // back.
    private var _recoveryLast as Number = 0;
    private var _recoveryDoneAgo as Number = -1;

    // The last few heart rates, oldest overwritten. Supplies the average at
    // the near end of a recovery, which has to be known the instant a shift
    // ends and so cannot be collected forwards like the far end.
    private var _hrRecent as Array<Number> = [0, 0, 0, 0, 0] as Array<Number>;
    private var _hrRecentCount as Number = 0;
    private var _hrStaleTicks as Number = 0;

    private var _iceHrSum as Number = 0;
    private var _iceHrSamples as Number = 0;
    private var _hardSeconds as Number = 0;
    private var _hardThreshold as Number = 0;

    // The 85% line is only as good as the maximum it is 85% of, and the
    // number on a Garmin profile is very often 220-minus-age that nobody ever
    // checked. The ceiling is therefore the higher of two things: a seed - the
    // player's own setting if they gave one, otherwise the profile - and the
    // highest beat actually recorded in this game. A beat that has happened
    // is better evidence than any setting; a setting is better evidence than a
    // formula. Keeping the two apart is what lets a player correct a profile
    // that is too HIGH, which raising-only could never do.
    private var _hrSeed as Number = 0;
    private var _hrObservedMax as Number = 0;
    private var _hrCeiling as Number = 0;
    // A candidate maximum, and how many seconds have supported it.
    private var _hrMaxPending as Number = 0;
    private var _hrMaxSeen as Number = 0;

    // Seconds a cached fix may still be fed to the detector, and the whole of
    // the staleness window. This used to say it was "matched to" the
    // detector's SPEED_MAX_AGE; it is not matched to it, it REPLACES it. The
    // two counters do not agree on a bound, they add up: the model stopped
    // feeding at second 5, and only then did the detector's own age start
    // climbing from zero toward its own limit, so a fix still voted at second
    // nine. The detector now drops a speed the moment it is handed a null, so
    // this constant alone decides how old a fix may be.
    private const SPEED_STALE_AFTER = 4;
    // The instant the frame being drawn belongs to, or -1 between frames.
    private var _frameNow as Number = -1;

    private var _speed as Float? = null;
    // Seconds since onPosition() last supplied a usable fix.
    //
    // The cache has to age HERE, where it is written, not in the detector.
    // The position callback only fires when the system has something to
    // report, so a watch that walks into a rink and never gets another fix
    // leaves _speed holding the last good value indefinitely - and because
    // onTick() re-feeds that cache every second, the detector sees a non-null
    // speed every second and resets its own staleness counter every second.
    // Its guard catches a model that stops supplying a speed; only this one
    // catches a model that keeps supplying the same one.
    private var _speedTicks as Number = SPEED_STALE_AFTER + 1;
    private var _gpsOn as Boolean = false;

    public var detector as ShiftDetector;

    private var _session as ActivityRecording.Session? = null;
    private var _shiftsField as FitContributor.Field? = null;
    private var _iceTimeField as FitContributor.Field? = null;
    private var _benchTimeField as FitContributor.Field? = null;
    private var _avgShiftField as FitContributor.Field? = null;
    private var _maxShiftField as FitContributor.Field? = null;
    private var _workRestField as FitContributor.Field? = null;
    private var _iceHrField as FitContributor.Field? = null;
    private var _hardTimeField as FitContributor.Field? = null;
    private var _lapShiftField as FitContributor.Field? = null;
    private var _lapBenchField as FitContributor.Field? = null;
    private var _onIceField as FitContributor.Field? = null;
    private var _curShiftField as FitContributor.Field? = null;
    private var _motionField as FitContributor.Field? = null;
    private var _thresholdField as FitContributor.Field? = null;
    private var _strideRateField as FitContributor.Field? = null;
    private var _strideRField as FitContributor.Field? = null;
    private var _strideLagField as FitContributor.Field? = null;
    private var _stridePromField as FitContributor.Field? = null;
    private var _benchRecovField as FitContributor.Field? = null;
    private var _shiftFadeField as FitContributor.Field? = null;
    private var _hrDriftField as FitContributor.Field? = null;
    private var _strideAvgField as FitContributor.Field? = null;
    private var _strideCovField as FitContributor.Field? = null;
    private var _distEstField as FitContributor.Field? = null;
    private var _speedEstField as FitContributor.Field? = null;
    private var _lapAvgHrField as FitContributor.Field? = null;
    private var _lapMaxHrField as FitContributor.Field? = null;
    private var _hrRecoveryField as FitContributor.Field? = null;
    private var _iceLoadField as FitContributor.Field? = null;
    private var _strideLenField as FitContributor.Field? = null;
    private var _intensityField as FitContributor.Field? = null;

    // Whether the player has already been warned that motion data stopped.
    private var _sensorWarned as Boolean = false;

    //! Constructor.
    public function initialize() {
        detector = new ShiftDetector(1);
        loadSettings();
        detector.start();
    }

    // ------------------------------------------------------------------
    // Settings
    // ------------------------------------------------------------------

    //! Re-read the user's settings. Safe to call at any time.
    public function loadSettings() as Void {
        shiftTargetMs = readNumber("shiftSeconds", 60, 15, 600) * 1000;
        sensitivity = readNumber("sensitivity", 1, 0, 2);
        shiftAlerts = readBoolean("shiftAlerts", false);
        changeAlerts = readBoolean("changeAlerts", false);
        autoLap = readBoolean("autoLap", true);
        useGps = readBoolean("useGps", true);
        // Read, but only consulted when a session is created, so changing it
        // mid-game cannot retype an activity that is already recording.
        activityType = readNumber("activityType", ACTIVITY_HOCKEY, 0, 1);
        // 0 is off; anything else is floored at END_IDLE_MIN_MINUTES. The
        // numeric setting control cannot express "zero, or twenty and up", so
        // the floor is applied here rather than left to the prompt text. A
        // player who types 10 means "end it promptly", not "end it during the
        // second intermission" - and an auto-save mid-game is the one failure
        // this feature must never cause, because it is the failure 2.0.0
        // removed the period clock to fix.
        var endIdleMinutes = readNumber("endIdleMinutes", 25, 0, 180);
        if (endIdleMinutes > 0 && endIdleMinutes < END_IDLE_MIN_MINUTES) {
            endIdleMinutes = END_IDLE_MIN_MINUTES;
        }
        endIdleMs = endIdleMinutes * 60 * 1000;
        // Read once per settings change, but only consulted when the session is
        // created: the distance and speed fields either exist for a game or
        // they do not, and a field cannot be added to a session already running.
        strideLengthCm = readNumber("strideLengthCm", 0, 0, 500);

        // 0 means "use the profile". Anything between 1 and 99 is not a
        // maximum heart rate - it is a slip of the numeric picker - and is
        // treated as 0 rather than clamped up to 100, because inventing a
        // ceiling of 100 would put the 85% line at 85 and count the whole
        // game as hard.
        maxHeartRate = readNumber("maxHeartRate", 0, 0, 240);
        if (maxHeartRate > 0 && maxHeartRate < 100) {
            maxHeartRate = 0;
        }
        _hrSeed = (maxHeartRate > 0) ? maxHeartRate : profileMaxHeartRate();
        refreshHrCeiling();

        detector.setSensitivity(sensitivity);
    }

    //! Read a numeric property, clamped, falling back to a default.
    private function readNumber(key as String, fallback as Number, minimum as Number, maximum as Number) as Number {
        var value = fallback;
        try {
            var raw = Application.Properties.getValue(key);
            if (raw instanceof Lang.Number) {
                value = raw;
            } else if (raw instanceof Lang.Float || raw instanceof Lang.Double) {
                value = raw.toNumber();
            } else if (raw instanceof Lang.String) {
                var parsed = raw.toNumber();
                if (parsed != null) {
                    value = parsed;
                }
            }
        } catch (ex) {
            value = fallback;
        }
        if (value < minimum) {
            value = minimum;
        }
        if (value > maximum) {
            value = maximum;
        }
        return value;
    }

    //! Read a boolean property, falling back to a default.
    private function readBoolean(key as String, fallback as Boolean) as Boolean {
        try {
            var raw = Application.Properties.getValue(key);
            if (raw instanceof Lang.Boolean) {
                return raw;
            }
        } catch (ex) {
            // fall through
        }
        return fallback;
    }

    // ------------------------------------------------------------------
    // Clocks
    // ------------------------------------------------------------------

    //! How long the game has been running, pauses excluded.
    //!
    //! There is nothing to count down to - no period length, no end - so this
    //! counts up and has no ceiling. It is the activity's timer time, and it is
    //! what the big clock shows.
    public function gameElapsedMs() as Number {
        return _gameAccumMs + sinceMs(_gameSince);
    }

    //! What the big clock shows.
    public function clockMs() as Number {
        return gameElapsedMs();
    }

    //! True when the player is on the ice right now.
    public function onIce() as Boolean {
        return detector.state == ON_ICE;
    }

    //! Length of the segment in progress, whether that is a shift or a spell on
    //! the bench. Runs on wall time while the game runs, and stops when the
    //! game is paused - a whistle is part of your shift, an intermission is not.
    public function segmentMs() as Number {
        return _segmentAccumMs + sinceMs(_segmentSince);
    }

    //! Total clock time played. Kept as its own name because the summary and
    //! the FIT session fields read it, and they mean "the whole game".
    public function totalPlayedMs() as Number {
        return gameElapsedMs();
    }

    //! Average length of the shifts that have been completed.
    public function averageShiftMs() as Number {
        if (_completedShiftCount < 1) {
            return 0;
        }
        return (_completedShiftMs / _completedShiftCount).toNumber();
    }

    //! Longest single shift of the game.
    public function longestShiftMs() as Number {
        return _longestShiftMs;
    }

    //! Total time on the ice, including the shift in progress.
    public function iceTimeMs() as Number {
        return _iceMs + (onIce() ? segmentMs() : 0);
    }

    //! Total time on the bench, including the spell in progress.
    public function benchTimeMs() as Number {
        return _benchMs + (onIce() ? 0 : segmentMs());
    }

    //! Rest per unit of work: 1.0 is a minute of bench for every minute of
    //! ice, 2.4 is nearly two and a half minutes of bench per minute of ice.
    //!
    //! It goes into the FIT file as a float, shown to one decimal place. It
    //! was a UINT16 carrying the ratio times 100 - which is all an integer
    //! field can do - and Garmin Connect duly rendered a 3.17 ratio as the
    //! number 317: correct data, meaningless on screen.
    public function workRest() as Float {
        var ice = iceTimeMs();
        if (ice < 1000) {
            return 0.0;
        }
        // Divided down to seconds before anything else, because bench * 100
        // in milliseconds overflowed a 32-bit Number after about six minutes
        // of bench time. Both divisions are integer, so the ice < 1000 guard
        // above is what keeps the denominator off zero.
        var ratio = (benchTimeMs() / 1000).toFloat() / (ice / 1000).toFloat();
        // A first shift almost entirely eaten by the detector backdate leaves
        // a tiny ice time and an absurd ratio. Cap it rather than publish it.
        if (ratio > 999.9) {
            ratio = 999.9;
        }
        return ratio;
    }

    //! The same ratio in hundredths, for the watch's own "1:2.4" display.
    public function workRestX100() as Number {
        return (workRest() * 100.0).toNumber();
    }

    //! Average heart rate counting only the seconds actually spent on the ice.
    public function iceAverageHr() as Number {
        if (_iceHrSamples < 1) {
            return 0;
        }
        if (_iceMs < 1000) {
            return 0;
        }
        // No ice time means no on-ice heart rate to report. The two are
        // accumulated separately - the rate every second the detector says
        // ON, the time only once a shift banks - so a game whose shifts were
        // all dated back out of existence used to show "On-Ice HR 162"
        // directly above "Ice 0:00". Whatever that pair means, it is not a
        // measurement of anything.
        return ((2 * _iceHrSum + _iceHrSamples) / (2 * _iceHrSamples)).toNumber();
    }

    //! Mean beats dropped in the first 60 seconds after a shift, over the
    //! bench spells long enough to measure one. 0 when none were.
    public function heartRateRecovery() as Number {
        if (_recoveryCount < 1) {
            return 0;
        }
        // Rounded toward zero's correct side for either sign: a negative mean
        // is a real result here (a rate still climbing a minute after a
        // shift), so it cannot be rounded with the positive formula.
        if (_recoverySum >= 0) {
            return ((2 * _recoverySum + _recoveryCount)
                / (2 * _recoveryCount)).toNumber();
        }
        return -((2 * -_recoverySum + _recoveryCount)
            / (2 * _recoveryCount)).toNumber();
    }

    //! How many bench spells that average rests on. A recovery figure from one
    //! spell is an anecdote; this is what says whether to believe it.
    //! The mean of the heart rates still in the ring, newest first in
    //! significance only - they are all within five seconds of each other.
    private function recentHrAverage() as Number {
        var n = (_hrRecentCount < HRR_WINDOW) ? _hrRecentCount : HRR_WINDOW;
        if (n < 1) {
            return 0;
        }
        var sum = 0;
        for (var i = 0; i < n; i++) {
            sum += _hrRecent[i];
        }
        return ((2 * sum + n) / (2 * n)).toNumber();
    }

    public function recoveryCount() as Number {
        return _recoveryCount;
    }

    //! Seconds spent above 85% of maximum heart rate.
    public function hardSeconds() as Number {
        return _hardSeconds;
    }

    //! Elapsed milliseconds since a start marker, or 0 if it is not running.
    //!
    //! Reads the frame clock when one is open. Every live number on the screen
    //! comes through here, and each call used to take its own
    //! System.getTimer() reading - so a draw that straddled a second boundary
    //! mixed two different seconds. Observed: `Ice 1:42` beside `ON 1:43` when
    //! the game had one unfinished shift and those are the SAME quantity,
    //! iceTimeMs() being _iceMs + segmentMs() with _iceMs at zero. Ice reading
    //! SMALLER than the shift inside it is impossible from one instant, and
    //! that is the tell.
    private function sinceMs(marker as Number) as Number {
        if (marker < 0) {
            return 0;
        }
        var delta = ((_frameNow >= 0) ? _frameNow : System.getTimer()) - marker;
        if (delta < 0) {
            // System.getTimer() wrapped around. Lose the wrap, not the game.
            return 0;
        }
        return delta;
    }

    // ------------------------------------------------------------------
    // Game control
    // ------------------------------------------------------------------

    //! Start, or resume after a manual pause. The one press of the game.
    public function start() as Void {
        if (state == STATE_RUNNING || state == STATE_FINISHED) {
            return;
        }

        if (state == STATE_READY) {
            beginSession();
            detector.reset();
            detector.start();
            _sensorWarned = false;
            enableGps();

            // Open the game on the ice. The press that starts the app is the
            // one at the faceoff, so that is the likelier of the two, and it is
            // also the safe failure: on a watch with no usable accelerometer
            // the detector never flips and the player still gets a game
            // clock and a recorded activity rather than a screen that says
            // BENCH for an hour.
            detector.forceState(ON_ICE);
            shiftCount = 1;
            _segmentAccumMs = 0;
            _shiftAlerted = false;
        }

        // Restarts the segment clock as well as the game clock. On a resume
        // _segmentAccumMs still holds the part of the shift played before the
        // pause, so the shift continues rather than starting over.
        _segmentSince = System.getTimer();

        // Any arm belongs to the run that is over. pause() already clears it
        // on the path through a pause, but clearing it on every entry to
        // RUNNING is what makes "you cannot enter a game already armed" a
        // property of the code rather than a coincidence of the routes.

        // Same reasoning for the idle clock. A resume is someone touching the
        // watch, which is the strongest possible evidence the game is not
        // forgotten, so the count starts again from there.
        _idleMs = 0;
        _endArmedAt = -1;

        // pause() stops the accelerometer, so resuming has to start it again.
        // Both calls are no-ops when they are not needed.
        detector.start();
        detector.flushPending();

        // The system writes a record at the instant the timer restarts, before
        // onTick() next runs, so without this the first record after every
        // resume repeats the values from before the pause.
        writeRecordFields();

        var session = _session;
        if (session != null && !session.isRecording()) {
            session.start();
        }

        _gameSince = System.getTimer();
        state = STATE_RUNNING;
        alert(Attention.TONE_START, [new Attention.VibeProfile(100, 300)]);
    }

    // How long a first press stays armed, waiting for the second.
    //
    // Five seconds rather than three. The accident this guards against is a
    // single continuous contact - a glove dragging over the glass, a shove
    // against the boards - which produces one event, not two separated ones.
    // So a wider window costs very little in accidental pauses and buys a lot
    // for the deliberate case, where the player is wearing hockey gloves and
    // may not feel the first press at all.
    //
    // ...which a player falsified on 2026-11-09: "every time the button got
    // barely touched moving around in my glove it would pause the workout".
    // Five seconds is a long time for a button to be rubbed by a glove, and
    // anywhere in it a second contact pauses the game. Two seconds is still
    // generous for a gloved hand that has just felt the double-pulse arming
    // buzz - a deliberate second press follows in well under a second - and
    // it removes three fifths of the window an accident can land in.
    //
    // This narrows the odds; it does not change the shape of the problem.
    // Any press-twice scheme is a scheme a rubbing button can satisfy. The
    // alternative is hold-to-pause, which no stray contact can produce, at
    // the cost of the muscle memory this binding was chosen for.

    // ...but ignore a second press that lands too soon after the first, which
    // is mechanical bounce or one drag registering twice rather than a person
    // pressing twice.

    //! How long the auto-end warning stays on screen before it saves. Long
    //! enough to notice a buzz, pull a sleeve back and read the screen; short
    //! enough that a watch nobody is wearing is not waiting around.
    private const END_PROMPT_MS = 30000;

    //! The shortest idle setting that is not "off". An intermission is a
    //! normal 15 to 18 minutes of sitting down and a player may well sit
    //! longer, so anything under this would end live games between periods.
    private const END_IDLE_MIN_MINUTES = 20;


    //! True while GameView is the screen on top. The app owns the game tick,
    //! so onTick keeps running under a menu; this is how the model knows
    //! whether anything it does could be seen or answered.
    public var viewVisible as Boolean = false;

    //! Continuous milliseconds off the ice. Any on-ice second clears it.
    // The last few heart rates, for reading a rate AT a moment rather than
    // across one. A single sample at a segment boundary is at the mercy of
    // one optical glitch; five seconds of it is not.
    private var _hr5 as Array<Number> = [0, 0, 0, 0, 0] as Array<Number>;
    private var _hr5Count as Number = 0;

    // Bench recovery: heart rate at the moment a bench began, and the running
    // total of what each bench gave back.
    private var _benchStartHr as Number = 0;
    private var _benchRecovSum as Number = 0;
    private var _benchRecovCount as Number = 0;

    // Every completed shift's length in seconds, for the fade comparison.
    // Capped because an array that grows without limit on a watch is a bug
    // waiting for a long game; 200 shifts is far past any real one.
    private var _shiftLens as Array<Number> = [] as Array<Number>;

    // Cardiac drift: an incremental least-squares fit of heart rate against
    // elapsed minutes, over on-ice seconds in a fixed band of effort, so a
    // game that simply got easier does not read as a player who got fitter.
    // Floats and minutes, not Numbers and seconds: sum of t squared over a
    // thousand seconds overflows a 32-bit Number, and silently.
    private var _driftN as Float = 0.0;
    private var _driftT as Float = 0.0;
    private var _driftH as Float = 0.0;
    private var _driftTT as Float = 0.0;
    private var _driftTH as Float = 0.0;

    private var _idleMs as Number = 0;

    //! When the auto-end warning went up, or -1 when it is not showing.
    private var _endArmedAt as Number = -1;


    //! Mean of the last few heart rates, or 0 when there are none.
    private function recentHr() as Number {
        if (_hr5Count <= 0) {
            return 0;
        }
        var n = (_hr5Count < 5) ? _hr5Count : 5;
        var sum = 0;
        for (var i = 0; i < n; i++) {
            sum += _hr5[i];
        }
        return sum / n;
    }

    //! Average beats per minute given back over a bench, across the game.
    //! Negative is a real answer: it means the player went back out with a
    //! HIGHER rate than they came off with, which is what a bench too short
    //! to recover on looks like.
    public function benchRecovery() as Number {
        if (_benchRecovCount <= 0) {
            return 0;
        }
        return _benchRecovSum / _benchRecovCount;
    }

    //! Late shifts as a percentage of early ones, by mean length. 100 is no
    //! fade; 85 means the second half of the game was played in shifts 15%
    //! shorter than the first.
    //!
    //! Split by shift INDEX rather than by the clock, because the halves then
    //! hold the same number of shifts and neither is a mean of two.
    public function shiftFade() as Number {
        var n = _shiftLens.size();
        if (n < 6) {
            return 0;       // Too few to divide; 0 reads as "not measured".
        }
        var half = n / 2;
        var early = 0;
        var late = 0;
        var i;
        for (i = 0; i < half; i++) {
            early += _shiftLens[i];
        }
        for (i = n - half; i < n; i++) {
            late += _shiftLens[i];
        }
        if (early <= 0) {
            return 0;
        }
        return (late * 100) / early;
    }

    //! Heart-rate drift across the whole game at a fixed effort, in beats per
    //! minute: the slope of the fitted line times the length of the game.
    public function hrDrift() as Number {
        // Four points is the least that makes a slope worth reporting, and
        // they have to span some time: a fit over thirty seconds extrapolated
        // across an hour is noise multiplied by eighty.
        if (_driftN < 4.0 || _driftTT <= 0.0) {
            return 0;
        }
        var denom = (_driftN * _driftTT) - (_driftT * _driftT);
        if (denom == 0.0) {
            return 0;
        }
        var span = _driftTT - ((_driftT * _driftT) / _driftN);
        if (span < 4.0) {       // less than ~2 minutes of spread
            return 0;
        }
        var slope = ((_driftN * _driftTH) - (_driftT * _driftH)) / denom;
        var minutes = gameElapsedMs().toFloat() / 60000.0;
        return (slope * minutes).toNumber();
    }

    //! START has gone down during a game: start timing the hold.
    //!
    //! Nothing is decided here, and nothing is decided on a timer either. The
    //! pause happens in endPauseHold(), when the button comes back UP.
    //!
    //! That is a reversal of 2.5.5, which paused at the threshold while the
    //! button was still down because firing on release "feels broken". It was
    //! the wrong call, and a 1-star review on 2026-11-10 is what it cost:
    //! "i started the recording, locked the watch, it simply stopped after 13
    //! seconds and did not resume. weird app."
    //!
    //! On 34 of this app's 126 products there is no separate LIGHT key - every
    //! Venu, Venu Sq, Venu X1, vivoactive, Approach and D2 Air - and on those
    //! Garmin's own documented way to lock the watch is to HOLD THE TOP
    //! BUTTON. The top button is KEY_ENTER. Locking the watch and pausing the
    //! game were the same gesture, so the app paused itself 13 seconds in and
    //! sat there, because a locked watch is one nobody is about to press.
    //!
    //! The system owns that gesture and wins the race, so the app must not try
    //! to win it. Once the controls menu opens over the app the key release is
    //! delivered to the overlay and never reaches GameDelegate. A scheme that
    //! pauses at the threshold therefore pauses; one that pauses on release
    //! does nothing at all. Those are the only two failure modes available
    //! here, and just one of them loses somebody's game.
    public function beginPauseHold() as Void {
        _pauseHoldSince = System.getTimer();
    }

    //! The hold is over. True if it lasted long enough to have been meant.
    public function endPauseHold() as Boolean {
        var since = _pauseHoldSince;
        _pauseHoldSince = -1;
        if (since < 0 || state != STATE_RUNNING) {
            return false;
        }
        var held = System.getTimer() - since;
        if (held < 0) {
            return false;   // getTimer() wrapped mid-hold. Lose the pause.
        }
        return held >= PAUSE_HOLD_MS;
    }

    //! Abandon a hold without acting on it, from GameView.onHide().
    //!
    //! Losing the screen mid-hold is the signature of the controls menu
    //! opening, which is to say of somebody reaching for the lock rather than
    //! for the pause. Belt and braces next to the release rule above: this way
    //! a stolen hold is dropped on the spot instead of staying armed until
    //! some later, unrelated key comes up.
    public function cancelPauseHold() as Void {
        _pauseHoldSince = -1;
    }

    //! True while START is down and the hold is being timed.
    public function pauseHoldArmed() as Boolean {
        return _pauseHoldSince >= 0;
    }

    //! True once the hold has run long enough that letting go will pause.
    public function pauseHoldReady() as Boolean {
        var since = _pauseHoldSince;
        if (since < 0) {
            return false;
        }
        var held = ((_frameNow >= 0) ? _frameNow : System.getTimer()) - since;
        return held >= PAUSE_HOLD_MS;
    }

    //! Stop the clock without ending the game.
    public function pause() as Void {
        if (state != STATE_RUNNING) {
            return;
        }
        _gameAccumMs += sinceMs(_gameSince);
        _gameSince = -1;
        // Bank the segment and stop its clock. Without this the whole pause
        // would be banked as ice or bench time at the next flip: a fifteen
        // minute intermission would be recorded as a fifteen minute shift,
        // and the shift alert would fire the moment play resumed.
        _segmentAccumMs += sinceMs(_segmentSince);
        _segmentSince = -1;
        // Nothing reads the accelerometer while the clock is stopped, so
        // sampling through a pause only spends battery and piles up samples
        // that would be averaged into the first second after the resume.
        detector.stop();
        var session = _session;
        if (session != null && session.isRecording()) {
            session.stop();
        }
        state = STATE_PAUSED;
        _endArmedAt = -1;

        // Abandon any recovery in flight. _recoverySeconds counts ticks, and
        // onTick() returns early while paused, so a recovery armed before a
        // pause would resume counting afterwards and measure a "sixty second"
        // drop across an intermission - the largest and most flattering
        // number in the file, and pure artefact.
        _recoverySeconds = -1;
        _recoveryEndSum = 0;
        _recoveryEndCount = 0;
        // Nothing banked before a pause stays revocable: the streaks are
        // cleared too, so no later backdate can reach back across it.
        _recoveryDoneAgo = -1;
        _recoveryLast = 0;

        // Invalidate the heart rate ring as well. After the resume its newest
        // entry is from before the pause, and switchSegment() would start a
        // recovery from a rate the player had minutes ago. _hrStaleTicks is
        // what guards that, so it has to reflect the gap rather than the last
        // second the sensor happened to report.
        _hrRecentCount = 0;
        _hrStaleTicks = HRR_WINDOW + 1;
        // Restart the idle window rather than carrying the bench spell into
        // it. A player who sits out an intermission and then pauses the watch
        // partway through has done nothing wrong, and carrying over would
        // spend most of the window before the pause even began - the full
        // window has to clear an intermission from the moment of the pause,
        // which is the whole reason the default is longer than one.
        _idleMs = 0;
        alert(Attention.TONE_STOP, [new Attention.VibeProfile(100, 300)]);
    }

    //! One button for both, because that is how the START key behaves.
    public function toggleRun() as Void {
        if (state == STATE_RUNNING) {
            pause();
        } else {
            start();
        }
    }

    // ------------------------------------------------------------------
    // Shifts
    // ------------------------------------------------------------------

    //! Close the segment in progress and open the opposite one.
    //!
    //! backdateMs moves the boundary into the past, because the detector only
    //! confirms a change after it has persisted for several seconds. Without it
    //! every shift would lose its first few seconds to the bench and every
    //! bench spell would lose its first few seconds to the shift.
    private function switchSegment(toIce as Boolean, backdateMs as Number) as Void {
        // The backdate cannot reach back past the start of the segment being
        // closed, or the new segment would begin before the old one did and the
        // overlap would be counted twice.
        var available = segmentMs();
        var backdate = backdateMs;
        if (backdate > available) {
            backdate = available;
        }
        if (backdate < 0) {
            backdate = 0;
        }
        var elapsed = available - backdate;

        // The segment that just ENDED is the opposite of the one being opened.
        // This must not be read from the detector: by the time onTick() calls
        // in, the detector has already flipped, so asking it which state we are
        // in returns the new one and every segment gets banked as its own
        // opposite - ice time counted as bench and bench counted as a shift.
        var wasIce = !toIce;

        // Bench recovery and shift fade are both measured AT the boundary,
        // so they are taken before anything below moves the clocks on.
        var hrNow = recentHr();
        if (wasIce) {
            // A shift just ended: this is where a bench begins.
            if (hrNow > 0) {
                _benchStartHr = hrNow;
            }
            if (elapsed >= 1000 && _shiftLens.size() < 200) {
                _shiftLens.add(elapsed / 1000);
            }
        } else {
            // A bench just ended. What it gave back is the difference between
            // the rate going on to it and the rate coming off it.
            if (_benchStartHr > 0 && hrNow > 0) {
                _benchRecovSum += (_benchStartHr - hrNow);
                _benchRecovCount++;
            }
            _benchStartHr = 0;
        }

        if (wasIce) {
            _iceMs += elapsed;
            if (!bankShift(elapsed) && shiftCount > 0) {
                // The whole shift was dated back out of existence, so it
                // contributed no ice time, no average and no maximum. Take
                // back the count as well: a `shifts` of 7 against an
                // `avg_shift` built from 5 of them makes shifts x avg_shift
                // disagree with ice_time, and Garmin Connect shows all three
                // side by side. Better six real shifts than seven of which
                // two are bookkeeping.
                shiftCount--;
                var undo = _shiftsField;
                if (undo != null) {
                    undo.setData(shiftCount);
                }
            }
            // A segment that banked nothing gets no lap either. closeLap()
            // used to run here unconditionally, so a shift dated back out of
            // existence still produced a lap - and setLapFields() rounds
            // half-up where bankShift() takes a floor, so the two disagreed
            // by construction: a 970 ms segment was REFUSED by bankShift (and
            // `shifts` decremented for it) while its lap claimed
            // `shift_time 1`. A fully clamped segment was worse still,
            // writing `shift_time 0` AND `bench_lap 0` and breaking the rule
            // this file states at setLapFields(): that every lap reads
            // unambiguously as either a shift or a spell on the bench. Both
            // are common - any shift the detector ends within about twelve
            // seconds of opening it lands here, which is most of the false
            // positives in a real game.
            //
            // Skipping the lap merges the sliver into the next one. That
            // leaves lap-timer time exceeding the developer fields by under a
            // second, which is a rounding difference; a lap claiming to be
            // both a shift and a bench spell of zero seconds is a wrong
            // number.
            if (autoLap && elapsed >= 1000) {
                closeLap(elapsed, true);
            }
        } else {
            _benchMs += elapsed;
            // No `shiftCount > 0` here any more. That guard was written for a
            // bench spell with no shift before it, which cannot happen:
            // start() sets shiftCount to 1 and forces ON_ICE, so the game
            // always opens on the ice and every bench segment follows a
            // shift. It was dead code until the decrement above was added,
            // at which point it came alive with the wrong meaning - a game
            // whose single shift was dated away took shiftCount to 0, and the
            // real bench spell that followed then silently got no lap at all,
            // leaving the session's bench_time with nothing behind it.
            if (autoLap && elapsed >= 1000) {
                closeLap(elapsed, false);
            }
        }

        // Arm the recovery clock when a SHIFT ends, and only then. A bench
        // spell that follows nothing - the pre-game stand-around - has no
        // exertion to recover from, so measuring a drop across it would
        // report the player's resting drift as a fitness number.
        //
        // The rate is read now, which is a few seconds after the boundary the
        // backdate says the shift really ended at. Heart rate keeps climbing
        // for 10-20 seconds after a shift ends, so this reads at or near the
        // peak either way, and moving it earlier would not obviously be more
        // correct.
        //
        // A stale ring is refused rather than used. If the sensor has been
        // dropping out for longer than the window, the newest value in it is
        // from some earlier part of the shift, and starting a recovery from a
        // rate the player no longer had would report a drop that never
        // happened.
        // A recovery measured across seconds that have just been reassigned
        // to this shift is not a recovery. transition() dates the boundary
        // back by the window that confirmed it, so the bench spell the drop
        // was measured over may have ended before the drop finished - which
        // makes the far end a mid-shift rate, read while the player was
        // skating, and a drop that never happened.
        if (toIce && _recoveryDoneAgo >= 0
                && _recoveryDoneAgo * 1000 < backdate) {
            _recoverySum -= _recoveryLast;
            _recoveryCount--;
            _recoveryLast = 0;
            _recoveryDoneAgo = -1;
        }

        // The near end needs the same minimum as the far end. HRR_MIN_END
        // was added because a mean of one or two samples is a jittery optical
        // reading rather than a measurement - and that argument says nothing
        // about which end of the window it is. _hrRecentCount > 0 accepted a
        // single sample, which pause() made newly reachable by clearing the
        // ring: one good second after a resume was enough to arm a recovery
        // whose starting point was that one second.
        if (wasIce && _hrRecentCount >= HRR_MIN_END && _hrStaleTicks <= HRR_WINDOW) {
            _recoveryFrom = recentHrAverage();
            _recoverySeconds = 0;
        } else {
            _recoverySeconds = -1;
        }
        _recoveryEndSum = 0;
        _recoveryEndCount = 0;

        // Start the next segment's heart rate from nothing. Carrying it would
        // average a shift together with the bench spell before it.
        _segHrSum = 0;
        _segHrSamples = 0;
        _segHrMax = 0;

        detector.forceState(toIce ? ON_ICE : OFF_ICE);
        // Carried as accumulated time rather than by moving the marker into the
        // past, so the marker is never negative and sinceMs() cannot read it as
        // "unset" and freeze the segment clock at zero.
        _segmentAccumMs = backdate;
        _segmentSince = System.getTimer();
        _shiftAlerted = false;

        if (toIce) {
            shiftCount++;
            var shiftsField = _shiftsField;
            if (shiftsField != null) {
                shiftsField.setData(shiftCount);
            }
            if (changeAlerts) {
                alert(Attention.TONE_LAP, [new Attention.VibeProfile(100, 250)]);
            }
        } else {
            if (changeAlerts) {
                alert(Attention.TONE_KEY, [new Attention.VibeProfile(70, 150)]);
            }
        }
    }

    //! Manual correction from the menu, for when the detector got it wrong.
    //! Toggles from whatever the state is NOW. Safe from a button, where the
    //! press and the read are the same instant; not safe from a menu item
    //! whose label was chosen when the menu opened - that goes through
    //! markSwitchTo().
    public function markSwitch() as Void {
        if (state != STATE_RUNNING) {
            return;
        }
        markSwitchTo(!onIce());
    }

    //! Correct to a STATED state rather than to the opposite of the current
    //! one, so a correction cannot invert itself if the detector flips between
    //! the player reading the label and choosing it.
    public function markSwitchTo(toIce as Boolean) as Void {
        if (state != STATE_RUNNING) {
            return;
        }
        // Already there: the detector agreed with the player before the
        // correction arrived. Doing nothing is right, and switching would
        // bank a zero-length segment and a phantom shift.
        if (onIce() == toIce) {
            return;
        }
        switchSegment(toIce, 0);
    }

    //! Bank one finished shift. Every caller that ends a shift goes through
    //! here so the count, the total and the maximum can never drift apart.
    private function bankShift(elapsed as Number) as Boolean {
        // A shift has to survive into the published units. Anything under a
        // second rounds to an ice_time of 0, and counting it would put
        // `shifts 1` next to `ice_time 0` - the same disagreement one scale
        // down from the fully-backdated case this guard already caught.
        if (elapsed < 1000) {
            return false;
        }
        _completedShiftMs += elapsed;
        _completedShiftCount++;
        if (elapsed > _longestShiftMs) {
            _longestShiftMs = elapsed;
        }
        return true;
    }

    //! Write the segment's length into the right lap field, then close the lap.
    //! A lap developer field keeps its last value until it is set again, so a
    //! lap closed without setting it reports the previous segment's length - a
    //! wrong number rather than a blank one. Both fields are written every
    //! time, with a zero in the one that does not apply, so each lap in Garmin
    //! Connect reads unambiguously as either a shift or a spell on the bench.
    //! Put the finished segment's length into the lap fields. Kept separate
    //! from adding the lap because the final segment of a game has no lap to
    //! add: the system writes that one itself when the session is saved, and
    //! it writes it with whatever these fields hold at that moment.
    private function setLapFields(elapsedMs as Number, wasIce as Boolean) as Void {
        // Round rather than truncate. Integer division threw away whatever was
        // left under a second on every lap, and a game is mostly laps: across
        // the 95 laps of 2026-11-05 the per-lap fields came to 5028 seconds
        // against 5121 of lap timer time.
        //
        // That truncation was ALL of the 93.5-second gap, not half of it as
        // this comment first claimed, and it was losing a whole second per lap
        // rather than the half-second an even spread would give - 0.984 s/lap
        // measured. The reason is that `elapsed` lands a few tens of
        // milliseconds BELOW a whole second almost every time: _segmentSince is
        // set inside one onTick() and read from a later one, so the interval is
        // always a hair under an exact multiple of 1000 ms, and floor() takes
        // the whole second rather than a fraction of one.
        //
        // The backdate contributes exactly zero, which is worth knowing because
        // it looks like it should contribute a lot. It telescopes: each segment
        // is banked as `available - backdate` and the next one opens with
        // _segmentAccumMs = backdate, so every backdated second is carried into
        // the following segment rather than lost. The per-lap differences are
        // large and signed - the confirmation windows, plus or minus - and they
        // sum to zero by construction.
        //
        // What the backdate does do is make these fields and the lap BOUNDARY
        // answer different questions. These describe the segment as the
        // detector finally decided it happened; the lap boundary is where the
        // change was confirmed, several seconds later. Garmin Connect's Splits
        // tab reads boundaries, so it overstates total ice time by about 11.5%
        // and gets a lap's average heart rate wrong by 2.2 bpm on average and
        // 15 bpm at worst. That is not fixable here - addLap() cannot be
        // backdated - but it should not be filed under "not a defect" either.
        var seconds = ((elapsedMs + 500) / 1000).toNumber();
        var shiftField = _lapShiftField;
        if (shiftField != null) {
            shiftField.setData(wasIce ? seconds : 0);
        }
        var benchField = _lapBenchField;
        if (benchField != null) {
            benchField.setData(wasIce ? 0 : seconds);
        }

        // Written for bench laps as well as shifts. A bench spell's average
        // heart rate is how hard the last shift was still costing you, which
        // is the number beside it in the Splits tab that makes the shift's own
        // average mean something.
        var avgHrField = _lapAvgHrField;
        if (avgHrField != null) {
            avgHrField.setData(_segHrSamples > 0 ? (_segHrSum / _segHrSamples).toNumber() : 0);
        }
        var maxHrField = _lapMaxHrField;
        if (maxHrField != null) {
            maxHrField.setData(_segHrMax);
        }
    }

    private function closeLap(elapsedMs as Number, wasIce as Boolean) as Void {
        setLapFields(elapsedMs, wasIce);
        var session = _session;
        if (session != null && session.isRecording()) {
            session.addLap();
        }
    }

    // ------------------------------------------------------------------
    // Per-second work
    // ------------------------------------------------------------------

    //! Housekeeping, once a second: run the detector, accumulate the heart rate
    //! statistics and raise alerts.
    //! Pin every clock on this draw to one instant, so the numbers on a frame
    //! cannot disagree with each other. Paired with closeFrame().
    public function openFrame() as Void {
        _frameNow = System.getTimer();
    }

    //! Release the frame clock. Always called, so a frame that throws part way
    //! through cannot freeze the clocks: openFrame() overwrites unconditionally
    //! and onTick() clears it as well.
    public function closeFrame() as Void {
        _frameNow = -1;
    }

    public function onTick() as Void {
        // Never run a tick against a frame's clock. Belt and braces: if a draw
        // somehow failed to close its frame, the per-second work would
        // otherwise read a stale instant and stop advancing.
        _frameNow = -1;

        // Before any branch returns: a fix goes stale on the bench, on pause
        // and on the ready screen exactly as it does during play.
        if (_speedTicks <= SPEED_STALE_AFTER) {
            _speedTicks++;
        }

        if (state == STATE_READY) {
            // Keep the detector running before the game starts. The ready
            // screen doubles as a self-test: wave the arm, watch the number
            // move. That is the only way to find out the accelerometer is
            // dead before a game rather than after one.
            detector.observe(currentHeartRate(), freshSpeed());
            detector.tick();
            return;
        }

        if (state == STATE_PAUSED) {
            trackPausedIdle();
            return;
        }

        if (state != STATE_RUNNING) {
            return;
        }

        var heartRate = currentHeartRate();

        detector.observe(heartRate, freshSpeed());
        if (detector.tick()) {
            // The detector flipped; it reports the state it has moved to, so
            // the segment that just ended was the other one.
            switchSegment(detector.state == ON_ICE, detector.backtrackMs());
        }

        var onTheIce = onIce();

        // Both terms of the intensity index need the same gate. The stride
        // term only ever sees seconds with a readable rhythm; the motion term
        // used to take every on-ice second including the stale ones, where
        // detector.motion still holds the last window it managed to average.
        // A dropout therefore quietly weighted an old value into the mean.
        if (onTheIce && detector.hasMotionSensor && detector.staleSeconds == 0) {
            _iceMotionSum += detector.motion;
            _iceMotionSamples++;
        }
        calibrateStride();

        if (heartRate != null && heartRate > 0) {
            _hr5[_hr5Count % 5] = heartRate;
            _hr5Count++;

            // Cardiac drift, over a FIXED band of effort. Taking every on-ice
            // second instead would measure how the game changed, not how the
            // player did: intensity fell about 9% across the game of
            // 2026-11-09, which on its own would read as the heart rate
            // improving. The band is relative to the learned threshold, so it
            // means the same thing on a quiet rink and a frantic one.
            if (onTheIce && detector.hasMotionSensor && detector.staleSeconds == 0
                    && detector.threshold > 0
                    && detector.motion >= detector.threshold
                    && detector.motion < (detector.threshold * 2)) {
                var tMin = gameElapsedMs().toFloat() / 60000.0;
                _driftN += 1.0;
                _driftT += tMin;
                _driftH += heartRate.toFloat();
                _driftTT += tMin * tMin;
                _driftTH += tMin * heartRate.toFloat();
            }

            if (onTheIce) {
                _iceHrSum += heartRate;
                _iceHrSamples++;
            }

            _hrRecent[_hrRecentCount % HRR_WINDOW] = heartRate;
            _hrRecentCount++;
            _hrStaleTicks = 0;

            // Per-segment, for the lap fields.
            _segHrSum += heartRate;
            _segHrSamples++;
            if (heartRate > _segHrMax) {
                _segHrMax = heartRate;
            }

            // Self-calibrate upwards. Hockey reaches a genuine maximum:
            // across twelve recorded games this player's profile ceiling was
            // beaten repeatedly, peaking at 199. A beat that has actually
            // happened outranks both the setting and the formula.
            offerHrMaximum(heartRate);

            if (_hardThreshold > 0 && heartRate >= _hardThreshold) {
                _hardSeconds++;
            }
        } else {
            _hrStaleTicks++;
        }

        // Recovery. Deliberately outside the guard above: the clock has to
        // advance on every second that passes, not only on the seconds the
        // sensor managed to report. Counting ticks instead would turn a
        // ten-second dropout into a seventy-second "HRR60" - a BIGGER drop,
        // because the heart is still falling at second seventy, for a reason
        // that has nothing to do with fitness. (This comment and the README
        // both said "smaller" until 2.5.2; release-2.4.0.md had it right.)
        //
        // The clock runs on the bench and only when a shift armed it. A spell
        // that ends before the window is simply not reported: there is no
        // 60-second drop to measure across a 20-second bench.
        if (_recoveryDoneAgo >= 0) {
            _recoveryDoneAgo++;
            if (_recoveryDoneAgo > HRR_ROLLBACK) {
                _recoveryDoneAgo = -1;   // out of reach of any backdate now
            }
        }

        if (!onTheIce && _recoverySeconds >= 0) {
            _recoverySeconds++;

            // Centre the far window ON sixty seconds. _recoverySeconds is 0
            // when the shift ends and is incremented at the top of each bench
            // tick, so it IS the number of seconds since the shift ended;
            // HRR_WINDOW samples taken from HRR_START onwards therefore cover
            // seconds 58 to 62, whose mean is 60. That is HRR60.
            //
            // 2.5.0 moved this to HRR_AT - 4 on the belief that the old window
            // "put the mean at 62" and was really HRR62. That was simply
            // wrong - 58 through 62 averages 60, as the sentence above it in
            // the same comment said - and the change moved a correctly centred
            // window off its mark, making the shipped figure HRR58: seconds 56
            // to 60, a mean of 58, and a smaller drop than the field claims.
            // Reverted in 2.5.2 and derived from the two constants here, so it
            // cannot drift again.
            if (_recoverySeconds >= HRR_START && _recoveryEndCount < HRR_WINDOW
                    && heartRate != null && heartRate > 0) {
                _recoveryEndSum += heartRate;
                _recoveryEndCount++;
            }

            var done = (_recoveryEndCount >= HRR_WINDOW);
            var timedOut = (_recoverySeconds >= HRR_GIVE_UP);
            if (done || timedOut) {
                // Too few samples at the far end is NOT a recovery of zero.
                // It is a bench spell the sensor did not cover, and averaging
                // it in would pull the game's figure toward nothing measured.
                if (_recoveryEndCount >= HRR_MIN_END) {
                    // A negative drop is a rate still climbing a minute after
                    // a shift. It is real, it is informative, and averaging it
                    // in is what makes this a measurement rather than a
                    // highlight reel, so it is kept rather than floored at 0.
                    // Rounded, not truncated. Truncating both ends biases a
                    // difference of two means upward by up to a beat, every
                    // time, in the same direction.
                    var endMean = (2 * _recoveryEndSum + _recoveryEndCount)
                        / (2 * _recoveryEndCount);
                    _recoveryLast = _recoveryFrom - endMean.toNumber();
                    _recoverySum += _recoveryLast;
                    _recoveryCount++;
                    _recoveryDoneAgo = 0;
                }
                _recoverySeconds = -1;
                _recoveryEndSum = 0;
                _recoveryEndCount = 0;
            }
        }

        writeRecordFields();

        if (onTheIce && shiftAlerts && !_shiftAlerted && segmentMs() >= shiftTargetMs) {
            _shiftAlerted = true;
            alert(Attention.TONE_ALERT_HI,
                [new Attention.VibeProfile(100, 500), new Attention.VibeProfile(0, 150),
                 new Attention.VibeProfile(100, 500)]);
        }

        // The session fields used to be written only at the end of the game.
        // If the battery dies or the firmware restarts mid-game, the system
        // recovers the activity but no app code runs again, so the session
        // message kept whatever was last set - the zeros written at creation.
        // Garmin Connect would then show "Shifts 19" beside "Ice Time 0s", and
        // a zero reads as a measurement rather than as missing data. These are
        // eight setData calls on in-memory objects, so doing it every tick is
        // cheap and makes the recovery path produce a true summary.
        writeSessionFields();

        if (!detector.isHealthy() && !_sensorWarned) {
            // Shift tracking has stopped and nothing else on screen would show
            // it: the game would quietly record as one enormous shift. Say so
            // while there is still time to do something about it.
            _sensorWarned = true;
            alert(Attention.TONE_ERROR,
                [new Attention.VibeProfile(100, 400), new Attention.VibeProfile(0, 150),
                 new Attention.VibeProfile(100, 400), new Attention.VibeProfile(0, 150),
                 new Attention.VibeProfile(100, 400)]);
        } else if (detector.isHealthy()) {
            _sensorWarned = false;
        }

        trackIdle(onTheIce);
    }

    //! End a game nobody is playing any more.
    //!
    //! 2.0.0 removed a clock that ended the game on a schedule, because a
    //! schedule knows nothing about whether play is still going and it cut
    //! recordings short mid-shift. This is the opposite trigger: not a clock
    //! running out, but a long absence of any skating at all. A schedule can
    //! be wrong while the player is mid-shift; a quarter of an hour with no
    //! detected motion cannot be, provided the threshold stays well clear of
    //! an intermission.
    //!
    //! It warns before it acts, and when the warning goes unanswered it SAVES
    //! rather than discards. The whole premise of the app is that the watch is
    //! not being touched, so silence has to mean keep the game: the failure
    //! this fixes is a recording left running, and throwing the game away
    //! would be a worse one.
    private function trackIdle(onTheIce as Boolean) as Void {
        // The detector's state is only evidence about the player while the
        // accelerometer is actually delivering. ShiftDetector.tick() HOLDS its
        // state through a silent sensor rather than guessing, and the file says
        // why: silence is a fault in its own right, not a player standing very
        // still. Reading a held state as stillness would turn a dead sensor
        // into an auto-end - the detector pins OFF_ICE on the bench, the
        // listener dies, and twenty-five minutes of real play later the game
        // saves itself mid-shift. That is the period clock's failure wearing a
        // different hat, so the idle clock stops dead while the sensor is
        // unhealthy rather than counting evidence it does not have.
        //
        // This also means the feature cannot work at all on a watch whose
        // accelerometer never delivers, which is correct: start() forces
        // ON_ICE there, so there is no bench to time in the first place. Better
        // to do nothing than to end games on a signal that does not exist.
        if (!detector.isHealthy()) {
            _endArmedAt = -1;
            return;
        }

        if (onTheIce) {
            _idleMs = 0;
            _endArmedAt = -1;
            return;
        }

        advanceIdle();
    }

    //! The paused counterpart, and the case the auto-end originally missed.
    //!
    //! A paused game has no clocks running, but it is still an open recording
    //! - and pausing is the likeliest route to a forgotten one. "Pause at the
    //! final whistle, put the gloves away, remember four hours later" is the
    //! exact complaint this feature was built for, and it was the one path
    //! that never reached the idle clock: onTick() returned early on anything
    //! that was not STATE_RUNNING.
    //!
    //! There is no isHealthy() gate here, unlike trackIdle(). That gate exists
    //! because a held detector state is an absence of evidence, and absence
    //! must not be read as a signal. A pause is the opposite: a deliberate act
    //! by the player, with a timestamp. Gating on the detector would in fact
    //! disable this path outright, because pause() stops the accelerometer on
    //! purpose, so isHealthy() is false for every paused game by design.
    private function trackPausedIdle() as Void {
        advanceIdle();
    }

    //! Advance the idle clock by one second and arm, or fire, the warning.
    //! Shared so the running and paused paths cannot drift apart - the two
    //! differ in what counts as idle, not in what happens once it is.
    private function advanceIdle() as Void {
        // Nothing can be shown or cancelled while a menu or confirmation
        // covers the game screen: the countdown lives in GameView's header and
        // every cancel path runs through GameDelegate, neither of which is
        // reachable then. Acting anyway would save the game out from under an
        // open menu with no warning at all, so the clock freezes until the
        // screen comes back. A menu left open therefore suspends the feature,
        // which is the right way round - failing to end a game is recoverable
        // and ending one silently is not.
        if (!viewVisible) {
            return;
        }

        // The disable switch is checked before the armed branch, not after, so
        // turning the setting off in Garmin Connect during the countdown
        // actually calls the end off instead of watching it happen.
        if (endIdleMs <= 0) {
            _endArmedAt = -1;
            return;
        }

        if (_endArmedAt >= 0) {
            var age = System.getTimer() - _endArmedAt;
            // A negative age means the millisecond clock wrapped, so the
            // warning can no longer be timed. Saving is the safe outcome of an
            // untimeable warning, exactly as "not armed" is the safe outcome
            // of an untimeable pause arm: both pick the option that cannot
            // lose a game.
            if (age < 0 || age >= END_PROMPT_MS) {
                endGame(true);
            }
            return;
        }

        // onTick runs once a second. Counting in whole seconds here keeps this
        // on the same footing as _hardSeconds rather than inventing a second
        // notion of elapsed time.
        _idleMs += 1000;
        if (_idleMs >= endIdleMs) {
            _endArmedAt = System.getTimer();
            // Long-short-long-short-long, intended to be unmistakable
            // against the sensor warning - the alert most likely to be felt
            // in the same minute, and which used to share this array byte for
            // byte as three equal 400ms pulses. A player who cannot tell them
            // apart through a jersey reads "sensor unhappy again", ignores it,
            // and loses the game thirty seconds later.
            //
            // IT DOES NOT WORK ON THIS WATCH. Toybox/Attention.html states:
            // "Note: Forerunner devices do not support vibration patterns.
            // Vibration may still be used, but the vibration will always run
            // at the same duty cycle." So on an FR570 this array and the
            // sensor warning's array collapse to the same flat buzz, and the
            // rhythm that was supposed to carry the difference carries
            // nothing. The comment above described an intention, not the
            // behaviour.
            //
            // Tone cannot be the fallback either, for the reason originally
            // given - tones are routinely silenced, and the advice for the
            // lap-alert noise is specifically to turn Alert Tones off - so on
            // a Forerunner there is currently NO way to tell these two alerts
            // apart. The fix is separate vibrate() calls spaced by a timer,
            // since each call is its own buzz, rather than one call carrying a
            // pattern. Not done here: it needs a state machine and this
            // comment is the honest description until it exists.
            alert(Attention.TONE_ALERT_LO,
                [new Attention.VibeProfile(100, 700), new Attention.VibeProfile(0, 200),
                 new Attention.VibeProfile(100, 150), new Attention.VibeProfile(0, 200),
                 new Attention.VibeProfile(100, 700)]);
        }
    }

    //! True while the auto-end warning is on screen.
    public function isEndArmed() as Boolean {
        // PAUSED counts: a paused game can arm the warning now, and the header
        // in GameView is the only place it is ever shown. Leaving this at
        // RUNNING would arm a countdown that nothing draws and then save the
        // game with no warning at all - worse than not having the feature.
        return _endArmedAt >= 0
            && (state == STATE_RUNNING || state == STATE_PAUSED);
    }

    //! Milliseconds left before the game saves itself, for the countdown.
    public function endArmRemainingMs() as Number {
        if (!isEndArmed()) {
            return 0;
        }
        // Deliberately not sinceMs(): it reports 0 for a wrapped millisecond
        // clock, which here would read as a full thirty seconds remaining on
        // the exact tick advanceIdle() decides an untimeable warning has
        // expired and saves the game. The screen would freeze on ENDING GAME
        // 30 and then the game would be gone. A wrap has to mean "no time
        // left" in both places or one of them is lying.
        var age = System.getTimer() - _endArmedAt;
        if (age < 0) {
            return 0;
        }
        var left = END_PROMPT_MS - age;
        return (left > 0) ? left : 0;
    }

    //! Call off a pending auto-end. Returns true when there was one to call
    //! off, so the press that dismissed it can be swallowed rather than also
    //! pausing the game.
    public function cancelAutoEnd() as Boolean {
        if (_endArmedAt < 0) {
            return false;
        }
        _endArmedAt = -1;
        // Start the idle clock over, or the next tick would re-arm instantly
        // and the warning the player just dismissed would come straight back.
        _idleMs = 0;
        // Disarm any pause question underneath as well. The red ENDING GAME
        // header draws over PRESS AGAIN, so a player who armed a pause and
        // then got the auto-end warning cannot see that the pause question is
        // still live. Their dismissal press is swallowed here, the header
        // reverts to PRESS AGAIN, and the screen is now asking for a press
        // that would pause the game - so "cancelling is all that press does"
        // would be false for the one press after this one.
        return true;
    }

    //! Maximum heart rate from the top of the user's zone 5. There is no
    //! maximum heart rate field on the user profile, so the zones are the only
    //! place the figure is available at all.
    //! The ceiling, and the 85% line under it, from whichever evidence is
    //! strongest. Recomputed rather than nudged, so a settings change during a
    //! game takes effect without losing a maximum already recorded.
    // The highest beat worth believing from a wrist sensor. Optical heart
    // rate spikes on cadence lock and on a knock; a single 230 would move the
    // 85% line to 196 and silence hard_time for the rest of the game.
    private const HR_MAX_CREDIBLE = 230;

    // How many seconds a new maximum has to be ALMOST matched before it is
    // allowed to raise the ceiling. A genuine maximum is approached, held and
    // approached again; a spike is one sample.
    private const HR_MAX_CONFIRM = 3;

    private function refreshHrCeiling() as Void {
        // A seed of 0 means nobody told us a maximum and the profile had none.
        // The running observed maximum must NOT stand in for it: early in a
        // game the highest beat so far is whatever the warm-up reached, and
        // 85% of that is a line the player crosses constantly. With no seed
        // there is no threshold and hard_time stays 0, which is the honest
        // answer - the field is documented as needing a maximum.
        if (_hrSeed <= 0) {
            _hrCeiling = _hrObservedMax;
            _hardThreshold = 0;
            return;
        }
        _hrCeiling = (_hrSeed > _hrObservedMax) ? _hrSeed : _hrObservedMax;
        _hardThreshold = ((_hrCeiling * 85) / 100).toNumber();
    }

    //! Offer a beat as a new observed maximum. Raises the ceiling only when the
    //! reading is credible and has been very nearly repeated, so one optical
    //! spike cannot raise the bar for a whole game.
    //! A candidate counts as repeated only if this beat is within one of it,
    //! in EITHER direction. The first version tested `heartRate >=
    //! _hrMaxPending - 1`, which is true of every reading above the candidate
    //! however far above - so a 229 bpm spike read as "the candidate, seen
    //! again" rather than as a new candidate.
    private function sameCandidate(heartRate as Number) as Boolean {
        return _hrMaxPending > 0
            && heartRate >= _hrMaxPending - 1
            && heartRate <= _hrMaxPending + 1;
    }

    //! Offer a beat as a new observed maximum. Raises the ceiling only when the
    //! reading is credible and has been very nearly repeated, so one optical
    //! spike cannot raise the bar for a whole game.
    //!
    //! The count has to be CLEARED on promotion. Without that, _hrMaxSeen only
    //! ever rises: it reaches HR_MAX_CONFIRM on the third second of any game
    //! with a heart rate and stays there, after which every new high satisfies
    //! `_hrMaxSeen >= HR_MAX_CONFIRM` on the very sample that raised it. The
    //! guard then had no effect whatever - it was the bare `if (heartRate >
    //! _hrObservedMax)` it replaced, plus the credibility ceiling - and a
    //! single 229 bpm cadence-lock artefact at minute 7 would put the 85% line
    //! at 194 instead of 169 and silence hard_time for the rest of the game,
    //! which is the exact failure it was written to prevent.
    private function offerHrMaximum(heartRate as Number) as Void {
        if (heartRate > HR_MAX_CREDIBLE) {
            return;
        }
        if (heartRate <= _hrObservedMax) {
            // Not a new high, but it can still corroborate a candidate that is
            // waiting above the standing maximum.
            if (_hrMaxPending > _hrObservedMax && sameCandidate(heartRate)) {
                _hrMaxSeen++;
                promoteHrCandidate();
            }
            return;
        }
        // A new high. Hold it as a candidate rather than acting on it.
        if (sameCandidate(heartRate)) {
            if (heartRate > _hrMaxPending) {
                _hrMaxPending = heartRate;
            }
            _hrMaxSeen++;
        } else {
            _hrMaxPending = heartRate;
            _hrMaxSeen = 1;
        }
        promoteHrCandidate();
    }

    //! Accept the waiting candidate once enough seconds have supported it, and
    //! start the next count from zero.
    private function promoteHrCandidate() as Void {
        if (_hrMaxSeen < HR_MAX_CONFIRM || _hrMaxPending <= _hrObservedMax) {
            return;
        }
        _hrObservedMax = _hrMaxPending;
        _hrMaxSeen = 0;
        refreshHrCeiling();
    }

    private function profileMaxHeartRate() as Number {
        try {
            var zones = UserProfile.getHeartRateZones(UserProfile.HR_ZONE_SPORT_GENERIC);
            if (zones != null && zones.size() >= 6) {
                var maximum = zones[zones.size() - 1];
                if (maximum != null && maximum > 100) {
                    return maximum;
                }
            }
        } catch (ex) {
            // Fall through to "unknown": better no number than a wrong one.
        }
        return 0;
    }

    // ------------------------------------------------------------------
    // GPS
    // ------------------------------------------------------------------

    //! Turn on positioning. Indoors this will usually never get a fix, which is
    //! harmless: speed stays null and the detector simply does not get that
    //! vote. Outdoor rinks, and indoor rinks with enough glass, do get one, and
    //! then the activity carries real speed and distance into Garmin Connect.
    private function enableGps() as Void {
        if (!useGps || _gpsOn) {
            return;
        }
        if (!(Toybox has :Position)) {
            return;
        }
        try {
            Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
            _gpsOn = true;
        } catch (ex) {
            _gpsOn = false;
        }
    }

    //! Turn positioning back off, so it is not left running after the game.
    private function disableGps() as Void {
        if (!_gpsOn) {
            return;
        }
        try {
            Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
        } catch (ex) {
            // Nothing useful to do.
        }
        _gpsOn = false;
        _speed = null;
        _speedTicks = SPEED_STALE_AFTER + 1;
    }

    //! Position callback. Only the speed is kept, and only when the fix is good
    //! enough to be worth believing.
    public function onPosition(info as Position.Info) as Void {
        var accuracy = info.accuracy;
        // QUALITY_USABLE or better, not merely "not unavailable". The old test
        // was `< QUALITY_POOR`, which admitted a POOR fix - and a POOR fix's
        // speed is the input to a stride length that is then stored and reused
        // for every later game. A wrong constant is worse than none.
        if (accuracy == null || accuracy < Position.QUALITY_USABLE) {
            _speed = null;
            _speedTicks = SPEED_STALE_AFTER + 1;
            return;
        }
        var speed = info.speed;
        _speed = (speed == null) ? null : speed.toFloat();
        _speedTicks = (_speed == null) ? SPEED_STALE_AFTER + 1 : 0;
    }

    //! The cached speed, or null once it is too old to stand for the second
    //! being judged.
    private function freshSpeed() as Float? {
        return (_speedTicks <= SPEED_STALE_AFTER) ? _speed : null;
    }

    //! True when positioning is on and reporting a usable, current fix.
    public function hasGpsFix() as Boolean {
        return _gpsOn && freshSpeed() != null;
    }

    // ------------------------------------------------------------------
    // Finishing
    // ------------------------------------------------------------------

    //! Finish the game. Saving writes the activity to Garmin Connect.
    public function endGame(keep as Boolean) as Void {
        if (state == STATE_FINISHED) {
            return;
        }

        _gameAccumMs += sinceMs(_gameSince);
        _gameSince = -1;

        var elapsed = segmentMs();
        var endedOnIce = onIce();
        if (endedOnIce) {
            _iceMs += elapsed;
            // Honour the refusal, exactly as switchSegment() does. A final
            // segment under a second contributes no average and no maximum,
            // so counting it in `shifts` reproduces the very disagreement
            // between shifts, avg_shift and ice_time that bankShift() exists
            // to prevent - on the one path that never got the guard. Ending
            // the game shortly after an entry is enough to reach it, because
            // the entry's own backdate has already consumed the segment.
            if (!bankShift(elapsed) && shiftCount > 0) {
                shiftCount--;
                var undo = _shiftsField;
                if (undo != null) {
                    undo.setData(shiftCount);
                }
            }
        } else {
            _benchMs += elapsed;
        }
        // The system closes the final lap itself when the session is saved,
        // using whatever the lap fields hold at that moment. So set them and
        // do NOT add a lap: adding one here would either duplicate the final
        // lap or, if the game was paused first, be dropped silently and leave
        // the system to write the previous segment's length instead.
        if (autoLap) {
            setLapFields(elapsed, endedOnIce);
        }
        _segmentAccumMs = 0;
        _segmentSince = -1;
        _endArmedAt = -1;

        detector.stop();
        disableGps();

        captureSummary();
        // Saved whether the game is kept or discarded: a discarded game still
        // happened, and what GPS taught the app during it is still true.
        saveCalibration();
        writeSessionFields();

        var session = _session;
        if (session != null) {
            if (session.isRecording()) {
                session.stop();
            }
            if (keep) {
                session.save();
            } else {
                session.discard();
            }
            _session = null;
            clearFields();
        }

        state = STATE_FINISHED;
        alert(Attention.TONE_STOP,
            [new Attention.VibeProfile(100, 500), new Attention.VibeProfile(0, 200),
             new Attention.VibeProfile(100, 500)]);
    }

    //! If the app is being killed mid-game, keep the activity rather than lose it.
    public function saveIfRecording() as Void {
        detector.stop();
        disableGps();

        var session = _session;
        if (session == null) {
            return;
        }
        // Keep what this game learned about the player's stride. endGame()
        // does this too; this is the path taken when the system shuts the app
        // down instead, and a calibration thrown away there is a whole game's
        // worth of agreement lost for no reason. It is two storage calls.
        saveCalibration();
        // onStop() runs on a tight shutdown budget, so do the minimum that
        // still gets the game into the FIT file. captureSummary() is skipped
        // deliberately: it only feeds the on-screen summary, which nobody is
        // about to look at.
        writeSessionFields();
        if (session.isRecording()) {
            session.stop();
        }
        session.save();
        _session = null;
        clearFields();
    }

    // ------------------------------------------------------------------
    // FIT session
    // ------------------------------------------------------------------

    //! Create the activity recording session and its developer fields.
    private function beginSession() as Void {
        if (!(Toybox has :ActivityRecording)) {
            return;
        }
        try {
            _session = ActivityRecording.createSession({
                :name => WatchUi.loadResource($.Rez.Strings.FitSessionName) as String,
                :sport => hockeySport(),
                :subSport => hockeySubSport()
            });
            createFields();
        } catch (ex) {
            // Without a session the app still works as a clock and shift timer.
            //
            // Discard before dropping the reference: a created session that is
            // never started and never discarded leaves the system believing an
            // activity is in progress, and the next createSession() can be
            // refused. Clearing the field handles matters just as much - if
            // createField() threw partway, the handles already set point into
            // the abandoned session, and onTick() would keep calling setData()
            // on them once a second.
            var failed = _session;
            if (failed != null) {
                try {
                    failed.discard();
                } catch (ignored) {
                    // Nothing further to try.
                }
            }
            _session = null;
            clearFields();
        }
    }

    //! False when there is no activity session, so the game is being timed
    //! and nothing is being recorded.
    //!
    //! beginSession() catches everything createSession() and createFields()
    //! can throw, because a watch that cannot record is still a usable shift
    //! timer and refusing to start would be worse. But the catch was SILENT,
    //! and that is a different decision: a player could skate a whole game
    //! watching a perfectly normal screen and find nothing saved at the end.
    //! One known way to reach it is the firmware's limit on how many
    //! developer fields may be active at once - this app asks for 27 - and
    //! the simulator does not enforce such a limit, so the watch is the only
    //! place it can be seen.
    public function isWritingFit() as Boolean {
        return _session != null;
    }

    //! Push the per-second record fields: what the detector sees and what it
    //! decided. Called every tick, and again on resume so the record the system
    //! writes at the restart instant is not a copy of the one before the pause.
    private function writeRecordFields() as Void {
        var onTheIce = onIce();
        var segmentSeconds = (segmentMs() / 1000).toNumber();

        var curShiftField = _curShiftField;
        if (curShiftField != null) {
            curShiftField.setData(onTheIce ? segmentSeconds : 0);
        }
        var onIceField = _onIceField;
        if (onIceField != null) {
            onIceField.setData(onTheIce ? 1 : 0);
        }

        // The raw detection signal and the boundary it was judged against,
        // second by second, so the decision can be re-examined after the game.
        var motionField = _motionField;
        if (motionField != null) {
            motionField.setData(detector.motion);
        }
        var thresholdField = _thresholdField;
        if (thresholdField != null) {
            thresholdField.setData(detector.threshold);
        }

        // 0 is written, not skipped, for a second that produced no rate. A gap
        // in the trace would be read as "the watch missed it"; a zero is the
        // app saying it looked and found no rhythm, which is the truth during a
        // glide, a faceoff or a scrum.
        var strideRateField = _strideRateField;
        if (strideRateField != null) {
            strideRateField.setData(detector.stride.rate);
        }
        var strideRField = _strideRField;
        if (strideRField != null) {
            var r = detector.stride.strength;
            strideRField.setData(r > 255 ? 255 : r);
        }
        var strideLagField = _strideLagField;
        if (strideLagField != null) {
            strideLagField.setData(detector.stride.lag);
        }
        // Signed, because a peak BELOW the mean of its own lag curve is a
        // real and informative reading - it says the window had no peak at
        // all - and clamping it at zero would hide the difference between
        // "nearly a stride" and "nothing like one".
        var stridePromField = _stridePromField;
        if (stridePromField != null) {
            var pr = detector.stride.prominence;
            if (pr > 127) { pr = 127; }
            if (pr < -127) { pr = -127; }
            stridePromField.setData(pr);
        }
    }

    //! Drop every developer-field handle. Called whenever the session they
    //! belong to goes away, so nothing can write into a session that is gone.
    private function clearFields() as Void {
        _shiftsField = null;
        _iceTimeField = null;
        _benchTimeField = null;
        _avgShiftField = null;
        _maxShiftField = null;
        _workRestField = null;
        _iceHrField = null;
        _hardTimeField = null;
        _lapShiftField = null;
        _lapBenchField = null;
        _onIceField = null;
        _curShiftField = null;
        _motionField = null;
        _thresholdField = null;
        _strideRateField = null;
        _strideRField = null;
        _strideLagField = null;
        _stridePromField = null;
        _benchRecovField = null;
        _shiftFadeField = null;
        _hrDriftField = null;
        _strideAvgField = null;
        _strideCovField = null;
        _distEstField = null;
        _speedEstField = null;
        _lapAvgHrField = null;
        _lapMaxHrField = null;
        _hrRecoveryField = null;
        _iceLoadField = null;
        _strideLenField = null;
        _intensityField = null;
    }

    //! The FIT sport the activity is filed under.
    //!
    //! Activity.SPORT_HOCKEY (73) is the honest answer and is what makes Garmin
    //! Connect label this an ice hockey game. It is also a sport that Strava
    //! does not know, so a synced hockey game lands there as a bare "Workout".
    //! ACTIVITY_SKATE trades the correct Connect label for a sport Strava does
    //! understand - ice skating (33) - which is the closest thing it has.
    //!
    //! Both constants are gated on firmware version. Handing a watch a sport
    //! value its firmware predates is not something the compiler catches: the
    //! constant is inlined and never checked against minApiLevel.
    private function hockeySport() as Activity.Sport {
        if (activityType == ACTIVITY_SKATE && apiAtLeast(3, 2, 0)) {
            return Activity.SPORT_ICE_SKATING;
        }
        if (apiAtLeast(4, 1, 6)) {
            return Activity.SPORT_HOCKEY;
        }
        return Activity.SPORT_TRAINING;
    }

    //! SUB_SPORT_ICE is what separates ice hockey from the other hockeys. It
    //! arrived with the hockey sport, so it is gated the same way. Ice skating
    //! needs no qualifier.
    private function hockeySubSport() as Activity.SubSport {
        if (activityType == ACTIVITY_SKATE || !apiAtLeast(4, 1, 6)) {
            return Activity.SUB_SPORT_GENERIC;
        }
        return Activity.SUB_SPORT_ICE;
    }

    //! True when the watch's firmware is at or past the given API level.
    private function apiAtLeast(major as Number, minor as Number, micro as Number) as Boolean {
        var version = System.getDeviceSettings().monkeyVersion;
        if (version == null || version.size() < 3) {
            return false;
        }
        var have = [version[0], version[1], version[2]];
        var want = [major, minor, micro];
        for (var i = 0; i < 3; i++) {
            if (have[i] > want[i]) { return true; }
            if (have[i] < want[i]) { return false; }
        }
        return true;
    }

    //! Developer fields, so the numbers travel with the activity into Connect.
    //! Create the developer fields, in tiers, each tier able to fail alone.
    //!
    //! WARNING - the try/catch in each tier below cannot do what it was
    //! written to do. Read this before relying on it.
    //!
    //! The "16 developer fields" figure is not in any Garmin documentation.
    //! It traces to a single forum post by a Garmin engineer who said the
    //! firmware constant "is set to 16 for every device that I checked" - and
    //! who then added, in the same thread, "I only evaluated the number of
    //! RECORD fields allowed. It is possible that you can have more than 16
    //! fields if some of them are SESSION or LAP fields." The official docs
    //! state only BYTE limits, and state them per message: 256 bytes per
    //! message for an app, 32 for a data field. So the cap is per message
    //! type, and the counts that matter are these, not the total:
    //!
    //!     SESSION  19  (16 with no stride length - tier 5 skipped)
    //!     RECORD    8
    //!     LAP       4
    //!
    //! Bytes are not the binding constraint: SESSION carries 48 payload
    //! bytes of the 256 available. Count is.
    //!
    //! The 2026-11-09 game proves less than it looks. 24 fields were created
    //! and 24 landed, but that build ran SESSION at 13, which was never near
    //! any ceiling. With the three new metrics it is 16, and with a stride
    //! length set it is 19.
    //!
    //! And when it does bite, it does not throw. It raises an uncatchable
    //! System Error. Garmin's own engineer confirmed this by proposing a
    //! throw as a future improvement - "I think it would be much cleaner for
    //! us to throw an exception ... it would make it possible for you to
    //! handle the error vs just crashing the app" - and several developers
    //! report building exactly the fallback below and finding it "won't work
    //! because the errors can't be caught". Worse, the failure is not always
    //! at create time: session fields are written once, at the end of the
    //! recording, and overflow can crash there instead. That is the one
    //! moment a crash costs the whole game.
    //!
    //! So the tiering below is not a safety net. It is a priority ORDER, and
    //! that part still earns its place: a static order means the cheapest
    //! fields to lose are the ones created last. The real protection is
    //! keeping SESSION at or under 16 by construction, which is a budget to
    //! enforce here rather than an exception to catch. The simulator cannot
    //! help - the constant lives in device firmware, which the simulator
    //! does not model, which is why a probe created 227 without complaining.
    //!
    //! Before this, every field was created inside beginSession()'s single
    //! try. One throw anywhere in the list and the catch discarded the whole
    //! session: a player lost the entire game to the absence of a diagnostic
    //! nobody reads. The order below is therefore a priority order, each tier
    //! wrapped on its own, and a failure stops the list rather than unwinding
    //! it. Whatever was created up to that point still records.
    //!
    //! The tiers run least-losable first: the summary a player actually reads,
    //! then the splits table, then the shift chart, then the derived metrics,
    //! then distance, and last the per-second diagnostics that exist only to
    //! tune the detector. Note this is the reverse of the old order, where the
    //! diagnostics were created ahead of hr_recovery and skating_intensity.
    //!
    //! Field IDs are explicit constants, so reordering creation changes
    //! nothing about how the file decodes or how Connect renders it.
    //!
    //! No on-screen warning for a partial set, deliberately. The FIT file
    //! lists exactly which fields were created, so decoding one game says
    //! where the limit bit and how many this firmware really allows - a better
    //! measurement than any message could be. The failure worth shouting
    //! about is having no session at all, and the footer already does that.
    private function createFields() as Void {
        var session = _session;
        if (session == null) {
            return;
        }

        // Resolved once, before any tier that needs it. The player's own
        // setting outranks anything the app taught itself: they measured it,
        // we inferred it.
        usedStrideCm = (strideLengthCm > 0) ? strideLengthCm : learnedStrideCm();

        var ok = createSummaryFields(session);
        if (ok) { ok = createLapFields(session); }
        if (ok) { ok = createChartFields(session); }
        if (ok) { ok = createDerivedFields(session); }
        if (ok) { ok = createDistanceFields(session); }
        if (ok) { createDiagnosticFields(session); }

        writeSessionFields();
    }

    //! Tier 1: the eight numbers the game summary is made of. Losing these
    //! loses the point of the app, so they are created first and a watch that
    //! cannot take them is one that cannot record at all.
    //!
    //! These names are the file-internal identifiers. They are deliberately
    //! fixed ASCII rather than loaded from string resources: tools that read
    //! the FIT afterwards match on this name, so it must not change with the
    //! watch's language. The human-facing text lives in fitfields.xml.
    private function createSummaryFields(session as ActivityRecording.Session) as Boolean {
        try {
            _shiftsField = session.createField("shifts", FIELD_SHIFTS,
                FitContributor.DATA_TYPE_UINT16, {:mesgType => FitContributor.MESG_TYPE_SESSION});
            _iceTimeField = session.createField("ice_time", FIELD_ICE_TIME,
                FitContributor.DATA_TYPE_UINT32,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "s"});
            _benchTimeField = session.createField("bench_time", FIELD_BENCH_TIME,
                FitContributor.DATA_TYPE_UINT32,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "s"});
            _avgShiftField = session.createField("avg_shift", FIELD_AVG_SHIFT,
                FitContributor.DATA_TYPE_UINT16,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "s"});
            _maxShiftField = session.createField("max_shift", FIELD_MAX_SHIFT,
                FitContributor.DATA_TYPE_UINT16,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "s"});
            _workRestField = session.createField("work_rest", FIELD_WORK_REST,
                FitContributor.DATA_TYPE_FLOAT, {:mesgType => FitContributor.MESG_TYPE_SESSION});
            _iceHrField = session.createField("ice_avg_hr", FIELD_ICE_HR,
                FitContributor.DATA_TYPE_UINT8,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "bpm"});
            _hardTimeField = session.createField("hard_time", FIELD_HARD_TIME,
                FitContributor.DATA_TYPE_UINT32,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "s"});
        } catch (ex) {
            return false;
        }
        return true;
    }

    //! Tier 2: the Splits table - one row per shift and per spell on the
    //! bench, with what the heart was doing during each.
    private function createLapFields(session as ActivityRecording.Session) as Boolean {
        try {
            _lapShiftField = session.createField("shift_time", FIELD_LAP_SHIFT,
                FitContributor.DATA_TYPE_UINT16,
                {:mesgType => FitContributor.MESG_TYPE_LAP, :units => "s"});
            _lapBenchField = session.createField("bench_time_lap", FIELD_LAP_BENCH,
                FitContributor.DATA_TYPE_UINT16,
                {:mesgType => FitContributor.MESG_TYPE_LAP, :units => "s"});
            _lapAvgHrField = session.createField("shift_avg_hr", FIELD_LAP_AVG_HR,
                FitContributor.DATA_TYPE_UINT8,
                {:mesgType => FitContributor.MESG_TYPE_LAP, :units => "bpm"});
            _lapMaxHrField = session.createField("shift_max_hr", FIELD_LAP_MAX_HR,
                FitContributor.DATA_TYPE_UINT8,
                {:mesgType => FitContributor.MESG_TYPE_LAP, :units => "bpm"});
        } catch (ex) {
            return false;
        }
        return true;
    }

    //! Tier 3: the square wave against heart rate. Every rise is a shift, and
    //! it is the one picture that makes a recorded game legible at a glance.
    private function createChartFields(session as ActivityRecording.Session) as Boolean {
        try {
            _onIceField = session.createField("on_ice", FIELD_ON_ICE,
                FitContributor.DATA_TYPE_UINT8, {:mesgType => FitContributor.MESG_TYPE_RECORD});
            _curShiftField = session.createField("shift_time_live", FIELD_CUR_SHIFT,
                FitContributor.DATA_TYPE_UINT16,
                {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "s"});
        } catch (ex) {
            return false;
        }
        return true;
    }

    //! Tier 4: the derived session metrics. Valuable, and all of them
    //! reconstructible afterwards from a file that kept the tiers above.
    private function createDerivedFields(session as ActivityRecording.Session) as Boolean {
        try {
            _strideAvgField = session.createField("stride_avg", FIELD_STRIDE_AVG,
                FitContributor.DATA_TYPE_UINT16,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "ppm"});
            _strideCovField = session.createField("stride_coverage", FIELD_STRIDE_COV,
                FitContributor.DATA_TYPE_UINT8,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "%"});
            // SINT8, not UINT8: a heart rate still climbing a minute after a
            // shift gives a negative drop, and that is a real reading about a
            // player who is not recovering, not an error to be clamped away.
            _hrRecoveryField = session.createField("hr_recovery", FIELD_HR_RECOVERY,
                FitContributor.DATA_TYPE_SINT8,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "bpm"});
            _iceLoadField = session.createField("ice_load", FIELD_ICE_LOAD,
                FitContributor.DATA_TYPE_FLOAT,
                {:mesgType => FitContributor.MESG_TYPE_SESSION});
            _benchRecovField = session.createField("bench_recovery", FIELD_BENCH_RECOV,
                FitContributor.DATA_TYPE_SINT8,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "bpm"});
            _shiftFadeField = session.createField("shift_fade", FIELD_SHIFT_FADE,
                FitContributor.DATA_TYPE_UINT8,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "%"});
            _hrDriftField = session.createField("hr_drift", FIELD_HR_DRIFT,
                FitContributor.DATA_TYPE_SINT8,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "bpm/min"});
            _intensityField = session.createField("skating_intensity", FIELD_INTENSITY,
                FitContributor.DATA_TYPE_FLOAT,
                {:mesgType => FitContributor.MESG_TYPE_SESSION});
        } catch (ex) {
            return false;
        }
        return true;
    }

    //! Tier 5: distance and speed, and the stride length they were built
    //! from. Not created at all when the player has not calibrated and the app
    //! has learned nothing, so an uncalibrated game carries no distance field
    //! rather than a zero one.
    private function createDistanceFields(session as ActivityRecording.Session) as Boolean {
        if (usedStrideCm <= 0) {
            return true;
        }
        try {
            _strideLenField = session.createField("stride_length_used", FIELD_STRIDE_LEN,
                FitContributor.DATA_TYPE_UINT16,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "cm"});
            _distEstField = session.createField("distance_est", FIELD_DIST_EST,
                FitContributor.DATA_TYPE_UINT32,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "m"});
            _speedEstField = session.createField("speed_est", FIELD_SPEED_EST,
                FitContributor.DATA_TYPE_FLOAT,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "kph"});
        } catch (ex) {
            return false;
        }
        return true;
    }

    //! Tier 6, and last on purpose: the per-second diagnostics. These exist so
    //! a recorded game can settle the detector's thresholds without going back
    //! to a rink. They are the most expensive - five fields written every
    //! second - and the only ones whose loss costs a player nothing at all.
    private function createDiagnosticFields(session as ActivityRecording.Session) as Boolean {
        try {
            _motionField = session.createField("motion", FIELD_MOTION,
                FitContributor.DATA_TYPE_UINT16,
                {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "mg"});
            _thresholdField = session.createField("motion_threshold", FIELD_THRESHOLD,
                FitContributor.DATA_TYPE_UINT16,
                {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "mg"});
            _strideRateField = session.createField("stride_rate", FIELD_STRIDE_RATE,
                FitContributor.DATA_TYPE_UINT16,
                {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "ppm"});
            _strideRField = session.createField("stride_r", FIELD_STRIDE_R,
                FitContributor.DATA_TYPE_UINT8,
                {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "%"});
            _strideLagField = session.createField("stride_lag", FIELD_STRIDE_LAG,
                FitContributor.DATA_TYPE_UINT8,
                {:mesgType => FitContributor.MESG_TYPE_RECORD});
            _stridePromField = session.createField("stride_prom", FIELD_STRIDE_PROM,
                FitContributor.DATA_TYPE_SINT8,
                {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "%"});
        } catch (ex) {
            return false;
        }
        return true;
    }

    //! Push the running totals into the session-level FIT fields.
    private function writeSessionFields() as Void {
        var field = _shiftsField;
        if (field != null) { field.setData(shiftCount); }
        field = _iceTimeField;
        if (field != null) { field.setData((iceTimeMs() / 1000).toNumber()); }
        field = _benchTimeField;
        if (field != null) { field.setData((benchTimeMs() / 1000).toNumber()); }
        field = _avgShiftField;
        if (field != null) { field.setData((averageShiftMs() / 1000).toNumber()); }
        field = _maxShiftField;
        if (field != null) { field.setData((_longestShiftMs / 1000).toNumber()); }
        // Nothing derived from ice time may be published when no ice time
        // banked. These are accumulated on the detector's LIVE state, second
        // by second, while ice_time is only credited once a shift survives
        // the backdate - so a game whose shifts were all dated back out of
        // existence reported an on-ice heart rate, a skating load and a
        // stride coverage beside an ice_time of zero. An unwritten developer
        // field decodes as the FIT invalid value, which is the honest form of
        // "not measured"; a written 0 is a claim.
        // Tested against the PUBLISHED value, not the internal one. ice_time
        // is written in whole seconds, so a shift of 400 ms passes `_iceMs >
        // 0` and still reports ice_time 0 - which put an on-ice heart rate
        // and a skating load beside a zero again, one rounding step further
        // down. Whatever gates these has to be the number the reader sees.
        //
        // And the number the reader sees is iceTimeMs(), not _iceMs. _iceMs
        // holds only the shifts that have been BANKED; iceTimeMs() adds the
        // one in progress, and that is what ice_time is written from a dozen
        // lines above. The two differ on exactly the path this function
        // exists to serve: saveIfRecording(), which runs when the system
        // kills the app mid-game and - unlike endGame() - does not bank the
        // open segment. A battery that dies ten minutes into the first shift
        // left `ice_time 600` beside a withheld on-ice heart rate, skating
        // load and stride coverage, all of which had been measured for ten
        // minutes. Gating on _iceMs was the same error as `_iceMs > 0`, one
        // level up.
        var hadIce = (iceTimeMs() >= 1000);
        // And a second gate, one level in: everything below that is built
        // from WRIST MOTION is published only if some on-ice second actually
        // delivered a wrist-motion sample. A dead accelerometer leaves
        // iceLoad at 0.0 and coverage at 0% - "this player did not move" and
        // "no rhythm in any of 33 seconds" - which are measurements, made by
        // a sensor that reported nothing. The ready screen and isHealthy()
        // already say the accelerometer is dead; the file should not then
        // contradict them with three zeroes. Verified in the simulator, which
        // delivers no accelerometer data at all.
        var hadMotion = hadIce && _iceMotionSamples > 0;

        // work_rest needs its own gate, and it is neither of the two above.
        //
        // workRest() returns 0.0 in three cases and only the first two are
        // measurements: a game genuinely played without ever leaving the ice;
        // a game with too little ice to divide by; and a game in which the
        // detector never ran at all. That third one is the dead-accelerometer
        // game, where start() forces ON_ICE and nothing ever flips it, so the
        // whole game banks as one shift with no bench and `work_rest 0.0` -
        // "this player never left the ice" - gets published beside the absent
        // ice_load and stride_coverage that were withheld for exactly that
        // reason.
        //
        // But hadMotion alone is too strict, and the simulator showed it:
        // a bench spell entered BY HAND through the correction menu is a real
        // boundary whatever the accelerometer is doing, so the ratio is
        // measured even though no wrist motion ever was. That run published
        // nothing here while the watch drew `1:1.1` from the same two
        // numbers. A zero ratio is only credible if the detector was running;
        // a non-zero one stands on the bench time itself.
        field = _workRestField;
        if (field != null && hadIce && (_benchMs >= 1000 || hadMotion)) {
            field.setData(workRest());
        }
        field = _iceHrField;
        var iceHr = iceAverageHr();
        if (field != null && hadIce && iceHr > 0) { field.setData(iceHr); }
        field = _hardTimeField;
        // The last field in this function that could still publish a zero it
        // had not measured, and it needs BOTH halves of the measurement.
        //
        // A threshold, because with no maximum to work from
        // refreshHrCeiling() sets _hardThreshold = 0, the per-second test
        // never fires, and _hardSeconds stays 0. And an actual heart rate,
        // because the seed can come from the Garmin profile even on a game
        // where the optical sensor reported nothing at all - which is how the
        // simulator produced `hard_time 0` beside an absent ice_avg_hr and an
        // absent hr_recovery. "Zero seconds above 85% of maximum" is a
        // statement about a player; without a pulse it is a statement about a
        // sensor.
        if (field != null && _hardThreshold > 0 && _hrObservedMax > 0) {
            field.setData(_hardSeconds);
        }
        // One more level in, and the last. hadMotion says the accelerometer
        // delivered; it does not say a STRIDE was ever measured, which is a
        // much narrower thing - the rhythm has to clear the autocorrelation
        // gate, the octave guard and the prominence test. A player whose wrist
        // never produces a readable peak, both hands on the stick or the watch
        // under a cuff, banks motion samples all game and accepts no strides,
        // and that published `stride_avg 0` ppm, `0%` coverage, `0 m` and
        // `0.0 kph` - the same "no rhythm in any of those seconds" claim, now
        // with a healthy sensor. skating_intensity was already safe only
        // because hasSkatingIntensity() separately demands a rate.
        //
        // The two gates differ on purpose. A rate needs a second that was
        // ACCEPTED. Coverage needs only a second that was JUDGED: 0% across
        // forty examined seconds is a finding, and the one number here whose
        // whole job is to say the rate beside it means nothing.
        // A rate built on a handful of seconds is not a rate. The game of
        // 2026-11-09 accepted 6 of 829 judged seconds and this field still
        // published 81 pushes per minute off those six - a number beside
        // which stride_coverage read 0, for anyone who thought to look. The
        // coverage field is the warning; it should not be the only one.
        field = _strideAvgField;
        if (field != null && hadMotion && detector.stride.measuredSeconds() > 0
                && detector.stride.coveragePercent() >= STRIDE_MIN_COVERAGE) {
            field.setData(detector.stride.averageRate());
        }

        field = _benchRecovField;
        if (field != null && _benchRecovCount > 0) {
            var rec = benchRecovery();
            if (rec > 127) { rec = 127; }
            if (rec < -127) { rec = -127; }
            field.setData(rec);
        }
        field = _shiftFadeField;
        if (field != null) {
            var fade = shiftFade();
            if (fade > 0) {
                field.setData(fade > 255 ? 255 : fade);
            }
        }
        field = _hrDriftField;
        if (field != null && _driftN >= 4.0) {
            var drift = hrDrift();
            if (drift > 127) { drift = 127; }
            if (drift < -127) { drift = -127; }
            field.setData(drift);
        }
        field = _strideCovField;
        if (field != null && hadMotion && detector.stride.judgedSeconds() > 0) {
            field.setData(detector.stride.coveragePercent());
        }
        field = _hrRecoveryField;
        if (field != null && _recoveryCount > 0) {
            // Written only when a bench spell was actually measured. Writing
            // 0 otherwise would publish "no drop in a minute", which is a
            // claim about a very unfit player, as though it were the reading
            // from a game where the sensor simply never covered a full
            // window. An absent field is the honest form of "not measured".
            var hrr = heartRateRecovery();
            // 126, not 127. This field is DATA_TYPE_SINT8 and FIT's invalid
            // value for sint8 is 0x7F = 127 - so clamping to 127 would write
            // the exact sentinel that means "not measured", in the one place
            // in this function that is trying hardest to distinguish the two.
            // -128 is a valid sint8, so the floor needs no such adjustment.
            if (hrr > 126) { hrr = 126; }
            if (hrr < -128) { hrr = -128; }
            field.setData(hrr);
        }
        field = _iceLoadField;
        if (field != null && hadMotion) { field.setData(detector.iceLoad); }

        // Distance is pushes times the player's own stride length, so it only
        // covers the seconds the rhythm was actually measured over - which is
        // why stride_coverage sits beside it. Speed divides by those same
        // seconds and no others, hence the label "Speed While Striding": a
        // denominator of total ice time would quietly claim a speed for every
        // second the app could not measure.
        field = _distEstField;
        if (field != null && hadMotion && detector.stride.measuredSeconds() > 0) {
            field.setData(estimatedDistanceM());
        }
        field = _speedEstField;
        if (field != null && hadMotion && detector.stride.measuredSeconds() > 0) {
            field.setData(estimatedSpeedKph());
        }
        field = _strideLenField;
        if (field != null) { field.setData(usedStrideCm); }
        field = _intensityField;
        if (field != null && hadMotion && hasSkatingIntensity()) {
            // Not written when there was too little ice, or no readable
            // rhythm at all, to build it from. A published 0.0 would read as
            // "this player did not move", which is a measurement; silence is
            // the honest form of "not measured".
            field.setData(skatingIntensity());
        }
    }

    //! The stride length stored by an earlier game that had a GPS fix, in
    //! centimetres, or 0 if no game ever has.
    public function learnedStrideCm() as Number {
        try {
            var raw = Application.Storage.getValue(CAL_KEY);
            if (raw instanceof Lang.Number && raw >= CAL_MIN_CM && raw <= CAL_MAX_CM) {
                return raw;
            }
        } catch (ex) {
            // Storage can be unavailable; an absent calibration is not an error.
        }
        return 0;
    }

    //! One second of GPS calibration. Speed from the fix, rhythm from the
    //! wrist; where both exist in the same second, their quotient is a stride
    //! length in metres and needs no calibration skate from the player.
    private function calibrateStride() as Void {
        var speed = freshSpeed();
        if (speed == null || speed < CAL_MIN_SPEED || !onIce()) {
            return;
        }
        // Both halves of the quotient have to be from THIS second. A stale
        // accelerometer leaves detector.stride.rate reporting the last rhythm
        // it managed to measure, and dividing a live speed by an old cadence
        // produces a confident stride length out of two numbers that were
        // never true together.
        if (detector.staleSeconds > 0) {
            return;
        }
        var rate = detector.stride.rate;
        if (rate <= 0) {
            return;       // no rhythm this second: nothing to divide by.
        }
        // metres per second / strides per second = metres per stride.
        var cm = ((speed * 6000.0) / rate.toFloat()).toNumber();
        if (cm < CAL_MIN_CM || cm > CAL_MAX_CM) {
            return;       // outside anything a skating stride can be.
        }
        _calSum += cm;
        _calCount++;
    }

    //! Store what this game learned, if it learned enough to be worth
    //! keeping. Called once, at the end, so a handful of seconds near the
    //! arena door cannot overwrite a calibration built over a whole game
    //! outdoors.
    //!
    //! A later game does not replace what an earlier one learned, it is
    //! averaged into it, three parts old to one part new. Stride length is a
    //! constant of the skater, so every game is another estimate of the same
    //! number rather than news about a changed one - and one windy afternoon
    //! on a pond should not be able to discard a calibration that a dozen
    //! games agreed on. The weighting is deliberately blunt: there is no
    //! sample count stored alongside it to do anything cleverer with, and
    //! storing one would need a migration for the players who already have a
    //! bare number saved.
    private function saveCalibration() as Void {
        if (_calCount < CAL_MIN_SAMPLES) {
            return;
        }
        var cm = (_calSum / _calCount).toNumber();
        if (cm < CAL_MIN_CM || cm > CAL_MAX_CM) {
            return;
        }
        var stored = learnedStrideCm();
        if (stored > 0) {
            cm = ((3 * stored) + cm) / 4;
            if (cm < CAL_MIN_CM || cm > CAL_MAX_CM) {
                return;
            }
        }
        try {
            Application.Storage.setValue(CAL_KEY, cm);
        } catch (ex) {
            // Nothing to do about a storage failure, and nothing is lost that
            // the next game outdoors will not learn again.
        }
    }

    //! How many seconds of GPS and rhythm agreed this game.
    public function calibrationSamples() as Number {
        return _calCount;
    }

    //! Wrist motion times stride rate, averaged over the ice.
    //!
    //! Deliberately unitless. It is amplitude multiplied by cadence, which is
    //! the shape of a mechanical power term, but nothing here is calibrated
    //! in watts and pretending otherwise would be the same mistake as
    //! inventing a stride length. It is comparable with your own past games
    //! and with nobody else's. The two terms are averaged separately rather
    //! than multiplied second by second, so that seconds with no readable
    //! rhythm pull the coverage figure down instead of pulling this to zero.
    public function skatingIntensity() as Float {
        if (_iceMotionSamples < INTENSITY_MIN_SAMPLES) {
            return 0.0;
        }
        var meanMotion = _iceMotionSum.toFloat() / _iceMotionSamples.toFloat();
        return (meanMotion * detector.stride.averageRate().toFloat()) / 1000.0;
    }

    //! True when the index rests on enough ice to mean anything. Checked
    //! before the field is written, so a game that never got going reports
    //! nothing rather than reporting zero intensity.
    public function hasSkatingIntensity() as Boolean {
        return _iceMotionSamples >= INTENSITY_MIN_SAMPLES
            && detector.stride.averageRate() > 0;
    }

    //! Metres, from counted pushes and the player's calibration. 0 when
    //! uncalibrated.
    public function estimatedDistanceM() as Number {
        if (usedStrideCm <= 0) {
            return 0;
        }
        return ((detector.stride.strideCount * usedStrideCm.toFloat()) / 100.0).toNumber();
    }

    //! km/h over the measured seconds only. 0 when uncalibrated or when
    //! nothing was measured.
    public function estimatedSpeedKph() as Float {
        var seconds = detector.stride.measuredSeconds();
        if (usedStrideCm <= 0 || seconds < 1) {
            return 0.0;
        }
        return (estimatedDistanceM().toFloat() / seconds.toFloat()) * 3.6;
    }

    //! Grab heart rate and calories while the activity still has them.
    private function captureSummary() as Void {
        var info = Activity.getActivityInfo();
        if (info.averageHeartRate != null) {
            finalAvgHr = info.averageHeartRate as Number;
        }
        if (info.maxHeartRate != null) {
            finalMaxHr = info.maxHeartRate as Number;
        }
        if (info.calories != null) {
            finalCalories = info.calories as Number;
        }
    }

    //! Current heart rate, or null when the sensor has nothing to say.
    public function currentHeartRate() as Number? {
        return Activity.getActivityInfo().currentHeartRate;
    }

    // ------------------------------------------------------------------
    // Feedback
    // ------------------------------------------------------------------

    //! Buzz and beep, respecting the watch's own tone and vibration settings.
    //!
    //! The patterns are deliberately long and at full strength. A short, gentle
    //! buzz is perfectly clear on a bare wrist and completely undetectable under
    //! a glove, an elbow pad and a jersey sleeve, which is where this app is.
    //! Fire a tone and a vibration, honouring the watch's own settings.
    //!
    //! A caveat that applies to every caller: the multi-element VibeProfile
    //! arrays passed in here do NOT produce distinguishable rhythms on a
    //! Forerunner. Toybox/Attention.html: "Note: Forerunner devices do not
    //! support vibration patterns. Vibration may still be used, but the
    //! vibration will always run at the same duty cycle." Five call sites in
    //! this file pass carefully distinct arrays - game start, game end, the
    //! long-shift alert, the sensor warning and the idle auto-end warning -
    //! and on the device this app is built and tested on they are all one
    //! flat buzz. The arrays are kept because they are correct on the other
    //! products in the manifest that do support patterns.
    //!
    //! Attention.ToneProfile (API 3.1.0, exactly this app's minApiLevel) can
    //! carry the distinction in frequency instead, and is the right fix - but
    //! only for a player who has Alert Tones on, which is the opposite of the
    //! advice for the firmware lap-alert noise.
    private function alert(tone as Attention.Tone, vibe as Array<Attention.VibeProfile>) as Void {
        if (!(Toybox has :Attention)) {
            return;
        }

        var settings = System.getDeviceSettings();

        var vibrateOn = true;
        if (settings has :vibrateOn) {
            vibrateOn = settings.vibrateOn;
        }
        if (vibrateOn && (Attention has :vibrate)) {
            Attention.vibrate(vibe);
        }

        var tonesOn = true;
        if (settings has :tonesOn) {
            tonesOn = settings.tonesOn;
        }
        if (tonesOn && (Attention has :playTone)) {
            Attention.playTone(tone);
        }
    }
}

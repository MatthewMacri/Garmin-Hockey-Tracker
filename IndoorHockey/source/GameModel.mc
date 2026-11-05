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

    // ---- settings, refreshed whenever Garmin Connect pushes a change ----
    public var shiftTargetMs as Number = 60 * 1000;
    public var shiftAlerts as Boolean = true;
    public var autoLap as Boolean = true;
    public var useGps as Boolean = true;
    public var sensitivity as Number = 1;
    public var activityType as Number = ACTIVITY_HOCKEY;

    //! Milliseconds off the ice before the game ends itself. 0 turns it off.
    public var endIdleMs as Number = 25 * 60 * 1000;

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
    private var _iceHrSum as Number = 0;
    private var _iceHrSamples as Number = 0;
    private var _hardSeconds as Number = 0;
    private var _hardThreshold as Number = 0;
    private var _hrCeiling as Number = 0;

    private var _speed as Float? = null;
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

    // Whether the player has already been warned that motion data stopped.
    private var _sensorWarned as Boolean = false;

    //! Constructor.
    public function initialize() {
        detector = new ShiftDetector(1);
        loadSettings();
        detector.start();
        _hrCeiling = profileMaxHeartRate();
        _hardThreshold = (_hrCeiling > 0) ? ((_hrCeiling * 85) / 100).toNumber() : 0;
    }

    // ------------------------------------------------------------------
    // Settings
    // ------------------------------------------------------------------

    //! Re-read the user's settings. Safe to call at any time.
    public function loadSettings() as Void {
        shiftTargetMs = readNumber("shiftSeconds", 60, 15, 600) * 1000;
        sensitivity = readNumber("sensitivity", 1, 0, 2);
        shiftAlerts = readBoolean("shiftAlerts", true);
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

    //! Rest per unit of work, times 100 so it survives integer FIT fields.
    //! 100 means a minute of bench for every minute of ice.
    public function workRestX100() as Number {
        var ice = iceTimeMs();
        if (ice < 1000) {
            return 0;
        }
        // Computed in seconds, not milliseconds: bench * 100 in ms overflows a
        // 32-bit Number after about six minutes of bench time.
        var ratio = ((benchTimeMs() / 1000) * 100) / (ice / 1000);
        // The FIT field is a UINT16. A first shift almost entirely eaten by the
        // detector backdate leaves a tiny ice time and sends this past 65535.
        if (ratio > 65535) {
            ratio = 65535;
        }
        return ratio.toNumber();
    }

    //! Average heart rate counting only the seconds actually spent on the ice.
    public function iceAverageHr() as Number {
        if (_iceHrSamples < 1) {
            return 0;
        }
        return (_iceHrSum / _iceHrSamples).toNumber();
    }

    //! Seconds spent above 85% of maximum heart rate.
    public function hardSeconds() as Number {
        return _hardSeconds;
    }

    //! Elapsed milliseconds since a start marker, or 0 if it is not running.
    private function sinceMs(marker as Number) as Number {
        if (marker < 0) {
            return 0;
        }
        var delta = System.getTimer() - marker;
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
        _pauseArmedAt = -1;

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
    private const PAUSE_ARM_MS = 5000;

    // ...but ignore a second press that lands too soon after the first, which
    // is mechanical bounce or one drag registering twice rather than a person
    // pressing twice.
    private const PAUSE_MIN_GAP_MS = 250;

    //! How long the auto-end warning stays on screen before it saves. Long
    //! enough to notice a buzz, pull a sleeve back and read the screen; short
    //! enough that a watch nobody is wearing is not waiting around.
    private const END_PROMPT_MS = 30000;

    //! The shortest idle setting that is not "off". An intermission is a
    //! normal 15 to 18 minutes of sitting down and a player may well sit
    //! longer, so anything under this would end live games between periods.
    private const END_IDLE_MIN_MINUTES = 20;

    private var _pauseArmedAt as Number = -1;

    //! True while GameView is the screen on top. The app owns the game tick,
    //! so onTick keeps running under a menu; this is how the model knows
    //! whether anything it does could be seen or answered.
    public var viewVisible as Boolean = false;

    //! Continuous milliseconds off the ice. Any on-ice second clears it.
    private var _idleMs as Number = 0;

    //! When the auto-end warning went up, or -1 when it is not showing.
    private var _endArmedAt as Number = -1;

    //! Ask to pause. The first ask only arms; a second ask within
    //! PAUSE_ARM_MS actually pauses. Returns true when the pause happened.
    //!
    //! This exists because one press used to be enough, and this watch has a
    //! touchscreen - WatchUi's SELECT behaviour fires on a screen tap as well
    //! as on the START button, so a glove, a sleeve or a shove against the
    //! boards could stop the recording. On 2026-11-03 the clock stopped twice
    //! mid-period, for 3m40s and 3m26s, neither of them deliberate.
    //!
    //! Two presses within three seconds is not something a jersey cuff does.
    public function requestPause() as Boolean {
        if (state != STATE_RUNNING) {
            return false;
        }
        if (isPauseArmed()) {
            if (sinceMs(_pauseArmedAt) < PAUSE_MIN_GAP_MS) {
                return false;   // Too fast to be two presses.
            }
            _pauseArmedAt = -1;
            pause();
            return true;
        }
        _pauseArmedAt = System.getTimer();
        // The arm is a question, so it has to be the most distinctive cue the
        // app makes - everything else is a single pulse, this is a double one.
        // It used to be the weakest (40% for 120ms), which through a glove and
        // a jersey cuff in a rink is nothing at all: the player never knew they
        // were in an armed window, which defeats the whole point of asking.
        alert(Attention.TONE_KEY, [new Attention.VibeProfile(100, 150),
            new Attention.VibeProfile(0, 100), new Attention.VibeProfile(100, 150)]);
        return false;
    }

    //! True while a first press is still waiting for its second.
    public function isPauseArmed() as Boolean {
        if (_pauseArmedAt < 0 || state != STATE_RUNNING) {
            return false;
        }
        // sinceMs() reports 0 for a clock that has wrapped, and 0 is inside the
        // window - so a wrap mid-window would leave this armed for the rest of
        // the game, and a single press or tap would pause instantly. An arm
        // that cannot be timed has expired.
        var age = System.getTimer() - _pauseArmedAt;
        if (age < 0) {
            return false;
        }
        return age <= PAUSE_ARM_MS;
    }

    //! Milliseconds left to confirm, for the countdown on screen.
    public function pauseArmRemainingMs() as Number {
        if (!isPauseArmed()) {
            return 0;
        }
        return PAUSE_ARM_MS - sinceMs(_pauseArmedAt);
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
        _pauseArmedAt = -1;
        _endArmedAt = -1;
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

        if (wasIce) {
            _iceMs += elapsed;
            bankShift(elapsed);
            if (autoLap) {
                closeLap(elapsed, true);
            }
        } else {
            _benchMs += elapsed;
            if (autoLap && shiftCount > 0) {
                closeLap(elapsed, false);
            }
        }

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
            alert(Attention.TONE_LAP, [new Attention.VibeProfile(100, 250)]);
        } else {
            alert(Attention.TONE_KEY, [new Attention.VibeProfile(70, 150)]);
        }
    }

    //! Manual correction from the menu, for when the detector got it wrong.
    public function markSwitch() as Void {
        if (state != STATE_RUNNING) {
            return;
        }
        switchSegment(!onIce(), 0);
    }

    //! Bank one finished shift. Every caller that ends a shift goes through
    //! here so the count, the total and the maximum can never drift apart.
    private function bankShift(elapsed as Number) as Void {
        if (elapsed <= 0) {
            return;
        }
        _completedShiftMs += elapsed;
        _completedShiftCount++;
        if (elapsed > _longestShiftMs) {
            _longestShiftMs = elapsed;
        }
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
        var seconds = (elapsedMs / 1000).toNumber();
        var shiftField = _lapShiftField;
        if (shiftField != null) {
            shiftField.setData(wasIce ? seconds : 0);
        }
        var benchField = _lapBenchField;
        if (benchField != null) {
            benchField.setData(wasIce ? 0 : seconds);
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
    public function onTick() as Void {
        if (state == STATE_READY) {
            // Keep the detector running before the game starts. The ready
            // screen doubles as a self-test: wave the arm, watch the number
            // move. That is the only way to find out the accelerometer is
            // dead before a game rather than after one.
            detector.observe(currentHeartRate(), _speed);
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

        detector.observe(heartRate, _speed);
        if (detector.tick()) {
            // The detector flipped; it reports the state it has moved to, so
            // the segment that just ended was the other one.
            switchSegment(detector.state == ON_ICE, detector.backtrackMs());
        }

        var onTheIce = onIce();

        if (heartRate != null && heartRate > 0) {
            if (onTheIce) {
                _iceHrSum += heartRate;
                _iceHrSamples++;
            }

            // Self-calibrate the ceiling. The zones on the watch are often
            // never set, or set from a formula, and hockey reaches a genuine
            // maximum: across twelve recorded games this player's own profile
            // ceiling was beaten repeatedly, peaking at 199. A beat that has
            // actually happened is better evidence than an untouched setting,
            // so the higher of the two wins.
            if (heartRate > _hrCeiling) {
                _hrCeiling = heartRate;
                _hardThreshold = ((_hrCeiling * 85) / 100).toNumber();
            }

            if (_hardThreshold > 0 && heartRate >= _hardThreshold) {
                _hardSeconds++;
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
            // Long-short-long-short-long. This has to be unmistakable against
            // the sensor warning in particular, which is the alert most likely
            // to be felt in the same minute and which used to share this
            // array byte for byte: three equal 400ms pulses. A player who
            // cannot tell them apart through a jersey reads "sensor unhappy
            // again", ignores it, and loses the game thirty seconds later.
            // Tone alone is not enough to separate them - tones are routinely
            // silenced, and alert() honours tonesOn and vibrateOn
            // independently - so the rhythm has to carry the difference.
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
        _pauseArmedAt = -1;
        return true;
    }

    //! Maximum heart rate from the top of the user's zone 5. There is no
    //! maximum heart rate field on the user profile, so the zones are the only
    //! place the figure is available at all.
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
    }

    //! Position callback. Only the speed is kept, and only when the fix is good
    //! enough to be worth believing.
    public function onPosition(info as Position.Info) as Void {
        var accuracy = info.accuracy;
        if (accuracy == null || accuracy < Position.QUALITY_POOR) {
            _speed = null;
            return;
        }
        var speed = info.speed;
        _speed = (speed == null) ? null : speed.toFloat();
    }

    //! True when positioning is on and reporting a usable fix.
    public function hasGpsFix() as Boolean {
        return _gpsOn && _speed != null;
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
            bankShift(elapsed);
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
        _pauseArmedAt = -1;
        _endArmedAt = -1;

        detector.stop();
        disableGps();

        captureSummary();
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
    private function createFields() as Void {
        var session = _session;
        if (session == null) {
            return;
        }

        // These names are the file-internal identifiers. They are deliberately
        // fixed ASCII rather than loaded from string resources: tools that read
        // the FIT afterwards match on this name, so it must not change with the
        // watch's language. The human-facing text lives in fitfields.xml.
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
            FitContributor.DATA_TYPE_UINT16, {:mesgType => FitContributor.MESG_TYPE_SESSION});
        _iceHrField = session.createField("ice_avg_hr", FIELD_ICE_HR,
            FitContributor.DATA_TYPE_UINT8,
            {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "bpm"});
        _hardTimeField = session.createField("hard_time", FIELD_HARD_TIME,
            FitContributor.DATA_TYPE_UINT32,
            {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "s"});

        _lapShiftField = session.createField("shift_time", FIELD_LAP_SHIFT,
            FitContributor.DATA_TYPE_UINT16,
            {:mesgType => FitContributor.MESG_TYPE_LAP, :units => "s"});
        _lapBenchField = session.createField("bench_time_lap", FIELD_LAP_BENCH,
            FitContributor.DATA_TYPE_UINT16,
            {:mesgType => FitContributor.MESG_TYPE_LAP, :units => "s"});

        _onIceField = session.createField("on_ice", FIELD_ON_ICE,
            FitContributor.DATA_TYPE_UINT8, {:mesgType => FitContributor.MESG_TYPE_RECORD});
        _curShiftField = session.createField("shift_time_live", FIELD_CUR_SHIFT,
            FitContributor.DATA_TYPE_UINT16,
            {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "s"});
        _motionField = session.createField("motion", FIELD_MOTION,
            FitContributor.DATA_TYPE_UINT16,
            {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "mg"});
        _thresholdField = session.createField("motion_threshold", FIELD_THRESHOLD,
            FitContributor.DATA_TYPE_UINT16,
            {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "mg"});

        writeSessionFields();
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
        field = _workRestField;
        if (field != null) { field.setData(workRestX100()); }
        field = _iceHrField;
        if (field != null) { field.setData(iceAverageHr()); }
        field = _hardTimeField;
        if (field != null) { field.setData(_hardSeconds); }
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

//
// Indoor Hockey - game clock, automatic shift tracking and the FIT session.
//
// All state lives here. Views read it and draw; they keep nothing of their own.
//
// The design assumption is that the watch is not touched once the game starts.
// One press begins the game; after that the periods, the intermissions and
// every shift boundary are worked out by the app. Everything in here that
// would normally be a button is therefore driven from a clock or a sensor.
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
    STATE_BREAK = 3,     //!< Between periods; the intermission is counting down.
    STATE_FINISHED = 4   //!< Session saved or discarded; summary on screen.
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
    public var periodCount as Number = 3;
    public var periodMs as Number = 20 * 60 * 1000;
    public var breakMs as Number = 60 * 1000;
    public var shiftTargetMs as Number = 60 * 1000;
    public var shiftAlerts as Boolean = true;
    public var autoLap as Boolean = true;
    public var countDown as Boolean = true;
    // Whether the app is allowed to save and close the game by itself when the
    // last period's clock runs out. Off by default, and deliberately so: see
    // endOfPeriod(). A game that ends while it is still being played loses the
    // rest of the game, and no setting should have that as its default.
    public var autoEndGame as Boolean = false;
    public var useGps as Boolean = true;
    public var sensitivity as Number = 1;
    public var activityType as Number = ACTIVITY_HOCKEY;

    // ---- live game state ----
    public var state as GameState = STATE_READY;
    public var period as Number = 1;
    public var shiftCount as Number = 0;

    // Summary values, captured before the session is handed back to the system.
    public var finalAvgHr as Number = 0;
    public var finalMaxHr as Number = 0;
    public var finalCalories as Number = 0;

    // Clocks are kept as "time already banked" plus "running since", both in
    // milliseconds from System.getTimer(), which is monotonic.
    private var _periodAccumMs as Number = 0;
    private var _periodSince as Number = -1;
    private var _earlierPeriodsMs as Number = 0;
    private var _breakSince as Number = -1;

    // True once the last period's clock has run out and the game is still
    // going. The period clock keeps counting from there and the activity keeps
    // recording; nothing stops until the player stops it.
    private var _overtime as Boolean = false;

    // Shift and bench clocks run on wall time, not game time. Recovery happens
    // during whistles too, so a bench spell that spans a stoppage is longer
    // than the period clock says it is.
    private var _segmentSince as Number = -1;
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
        periodCount = readNumber("periodCount", 3, 1, 9);
        periodMs = readNumber("periodMinutes", 20, 1, 60) * 60 * 1000;
        breakMs = readNumber("breakSeconds", 60, 0, 1200) * 1000;
        shiftTargetMs = readNumber("shiftSeconds", 60, 15, 600) * 1000;
        sensitivity = readNumber("sensitivity", 1, 0, 2);
        shiftAlerts = readBoolean("shiftAlerts", true);
        autoLap = readBoolean("autoLap", true);
        countDown = readBoolean("countDown", true);
        autoEndGame = readBoolean("autoEndGame", false);
        useGps = readBoolean("useGps", true);
        // Read, but only consulted when a session is created, so changing it
        // mid-game cannot retype an activity that is already recording.
        activityType = readNumber("activityType", ACTIVITY_HOCKEY, 0, 1);

        detector.setSensitivity(sensitivity);

        if (period > periodCount) {
            period = periodCount;
        }
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

    //! Milliseconds the clock has run in the current period.
    public function periodElapsedMs() as Number {
        var ms = _periodAccumMs + sinceMs(_periodSince);
        // Normally the clock stops at the length of a period, because the
        // period is about to end anyway. In overtime there is no end to stop
        // at, so it keeps counting.
        if (ms > periodMs && !_overtime) {
            ms = periodMs;
        }
        return ms;
    }

    //! True when the last period's clock has run out and play has continued.
    public function inOvertime() as Boolean {
        return _overtime;
    }

    //! How long the game has run past the end of regulation.
    public function overtimeMs() as Number {
        if (!_overtime) {
            return 0;
        }
        var over = periodElapsedMs() - periodMs;
        return (over < 0) ? 0 : over;
    }

    //! What the big clock should show: time left, or time played, per settings.
    public function clockMs() as Number {
        if (state == STATE_BREAK) {
            return breakRemainingMs();
        }
        if (_overtime) {
            // Counting down past zero would show a negative clock, and counting
            // the period up would show a number larger than a period. Neither
            // means anything, so overtime shows how long it has been in
            // overtime.
            return overtimeMs();
        }
        if (countDown) {
            return periodMs - periodElapsedMs();
        }
        return periodElapsedMs();
    }

    //! Milliseconds left in the intermission.
    public function breakRemainingMs() as Number {
        var left = breakMs - sinceMs(_breakSince);
        return (left < 0) ? 0 : left;
    }

    //! True when the player is on the ice right now.
    public function onIce() as Boolean {
        return detector.state == ON_ICE;
    }

    //! Length of the segment in progress, whether that is a shift or a spell on
    //! the bench. Runs on wall time.
    public function segmentMs() as Number {
        return sinceMs(_segmentSince);
    }

    //! Total clock time played across every period so far.
    public function totalPlayedMs() as Number {
        return _earlierPeriodsMs + periodElapsedMs();
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
        return ((benchTimeMs() * 100) / ice).toNumber();
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
            // the detector never flips and the player still gets a period
            // clock and a recorded activity rather than a screen that says
            // BENCH for an hour.
            detector.forceState(ON_ICE);
            shiftCount = 1;
            _segmentSince = System.getTimer();
            _shiftAlerted = false;
        }

        var session = _session;
        if (session != null && !session.isRecording()) {
            session.start();
        }

        _periodSince = System.getTimer();
        _breakSince = -1;
        state = STATE_RUNNING;
        alert(Attention.TONE_START, [new Attention.VibeProfile(100, 300)]);
    }

    // How long a first press stays armed, waiting for the second.
    private const PAUSE_ARM_MS = 3000;
    private var _pauseArmedAt as Number = -1;

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
            _pauseArmedAt = -1;
            pause();
            return true;
        }
        _pauseArmedAt = System.getTimer();
        // Distinct from the pause tone: this says "heard you, say it again",
        // so a press that was not meant is audibly not a pause.
        alert(Attention.TONE_KEY, [new Attention.VibeProfile(40, 120)]);
        return false;
    }

    //! True while a first press is still waiting for its second.
    public function isPauseArmed() as Boolean {
        if (_pauseArmedAt < 0 || state != STATE_RUNNING) {
            return false;
        }
        return sinceMs(_pauseArmedAt) <= PAUSE_ARM_MS;
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
        _periodAccumMs += sinceMs(_periodSince);
        _periodSince = -1;
        var session = _session;
        if (session != null && session.isRecording()) {
            session.stop();
        }
        state = STATE_PAUSED;
        _pauseArmedAt = -1;
        alert(Attention.TONE_STOP, [new Attention.VibeProfile(100, 300)]);
    }

    //! One button for both, because that is how the START key behaves.
    public function toggleRun() as Void {
        if (state == STATE_RUNNING) {
            pause();
        } else if (state == STATE_BREAK) {
            beginPeriod();
        } else {
            start();
        }
    }

    //! True when the period on screen is the last one of the game.
    public function isLastPeriod() as Boolean {
        return period >= periodCount;
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
        var elapsed = segmentMs() - backdateMs;
        if (elapsed < 0) {
            elapsed = 0;
        }

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
        _segmentSince = System.getTimer() - backdateMs;
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
    // Periods
    // ------------------------------------------------------------------

    //! The period clock hit zero. Start the intermission; it runs itself.
    private function endOfPeriod() as Void {
        if (_overtime) {
            return;     // Already past regulation; there is no period to end.
        }

        // Decide before touching anything. Everything below this point is
        // destructive end-of-period bookkeeping - it banks the period clock,
        // takes the player off the ice and stops the recording - and none of
        // it should happen to a game that is simply still being played.
        if (isLastPeriod() && !autoEndGame) {
            enterOvertime();
            return;
        }

        _periodAccumMs += sinceMs(_periodSince);
        _periodSince = -1;
        _earlierPeriodsMs += _periodAccumMs;
        _periodAccumMs = 0;

        // The player comes off the ice at the horn whether the detector has
        // noticed or not.
        if (onIce()) {
            switchSegment(false, 0);
        }

        var session = _session;
        if (session != null && session.isRecording()) {
            session.stop();
        }

        if (isLastPeriod()) {
            endGame(true);
            return;
        }

        state = STATE_BREAK;
        _breakSince = System.getTimer();
        alert(Attention.TONE_INTERVAL_ALERT,
            [new Attention.VibeProfile(100, 500), new Attention.VibeProfile(0, 200),
             new Attention.VibeProfile(100, 500)]);
    }

    //! Regulation has run out and the game is still being played.
    //!
    //! This exists because the app used to save and close the activity here.
    //! On 2026-11-03 that ended a recording at exactly 3600.79s of clock time -
    //! three periods of twenty minutes, to the second - while the game was
    //! still going, and the remaining nine minutes of wall-clock play were
    //! simply lost. Nothing recovers a game from that afterwards.
    //!
    //! A real game is always longer than the sum of its periods: stoppages,
    //! overtime, a running clock nobody told the watch about. So the end of
    //! regulation is now an announcement rather than an ending. Deliberately
    //! nothing here stops: not the clock, not the recording, not the shift
    //! detector. The game ends when the player ends it.
    private function enterOvertime() as Void {
        _overtime = true;
        alert(Attention.TONE_INTERVAL_ALERT,
            [new Attention.VibeProfile(100, 400), new Attention.VibeProfile(0, 150),
             new Attention.VibeProfile(100, 400), new Attention.VibeProfile(0, 150),
             new Attention.VibeProfile(100, 400)]);
    }

    //! The intermission ran out, or the player pressed start to skip it.
    private function beginPeriod() as Void {
        if (state != STATE_BREAK) {
            return;
        }
        period++;
        _breakSince = -1;
        _periodAccumMs = 0;
        _periodSince = System.getTimer();
        _overtime = false;

        var session = _session;
        if (session != null && !session.isRecording()) {
            session.start();
        }

        state = STATE_RUNNING;
        alert(Attention.TONE_START,
            [new Attention.VibeProfile(100, 400), new Attention.VibeProfile(0, 150),
             new Attention.VibeProfile(100, 400)]);
    }

    //! Skip the rest of the intermission, or the rest of the period.
    public function skipAhead() as Void {
        if (state == STATE_BREAK) {
            beginPeriod();
        } else if (state == STATE_RUNNING || state == STATE_PAUSED) {
            endOfPeriod();
        }
    }

    // ------------------------------------------------------------------
    // Per-second work
    // ------------------------------------------------------------------

    //! Housekeeping, once a second: run the detector, accumulate the heart rate
    //! statistics, raise alerts and advance the period or the intermission.
    public function onTick() as Void {
        if (state == STATE_BREAK) {
            if (breakRemainingMs() <= 0) {
                beginPeriod();
            }
            return;
        }

        if (state == STATE_READY) {
            // Keep the detector running before the game starts. The ready
            // screen doubles as a self-test: wave the arm, watch the number
            // move. That is the only way to find out the accelerometer is
            // dead before a game rather than after one.
            detector.observe(currentHeartRate(), _speed);
            detector.tick();
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

        if (onTheIce && shiftAlerts && !_shiftAlerted && segmentMs() >= shiftTargetMs) {
            _shiftAlerted = true;
            alert(Attention.TONE_ALERT_HI,
                [new Attention.VibeProfile(100, 500), new Attention.VibeProfile(0, 150),
                 new Attention.VibeProfile(100, 500)]);
        }

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

        // Once in overtime the period clock is permanently past periodMs, so
        // without this guard endOfPeriod() would fire on every tick.
        if (!_overtime && periodElapsedMs() >= periodMs) {
            endOfPeriod();
        }
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

        _periodAccumMs += sinceMs(_periodSince);
        _periodSince = -1;
        if (state != STATE_BREAK) {
            _earlierPeriodsMs += _periodAccumMs;
        }
        _periodAccumMs = 0;

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
        _segmentSince = -1;

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
            _session = null;
        }
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

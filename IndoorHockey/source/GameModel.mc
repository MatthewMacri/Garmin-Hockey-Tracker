//
// Indoor Hockey - game clock, shift clock, stat counters and the FIT session.
//
// All state lives here. Views read it and draw; they keep nothing of their own.
//

import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Application;
import Toybox.Attention;
import Toybox.FitContributor;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! Where the game currently is.
enum GameState {
    STATE_READY = 0,     //!< Nothing started; no FIT session yet.
    STATE_RUNNING = 1,   //!< Clock moving, session recording.
    STATE_PAUSED = 2,    //!< Whistle, timeout, injury.
    STATE_BREAK = 3,     //!< A period just ran out; waiting for the next one.
    STATE_FINISHED = 4   //!< Session saved or discarded; summary on screen.
}

//! The things worth tapping a button for during a game.
enum StatKind {
    STAT_GOAL = 0,
    STAT_ASSIST = 1,
    STAT_SHOT = 2,
    STAT_SAVE = 3
}

//! Owns the whole game.
class GameModel {

    // Developer FIT field ids. These end up in the FIT file, so they are stable:
    // changing one changes how previously recorded games are read.
    private const FIELD_GOALS     = 0;
    private const FIELD_ASSISTS   = 1;
    private const FIELD_SHOTS     = 2;
    private const FIELD_SAVES     = 3;
    private const FIELD_SHIFTS    = 4;
    private const FIELD_LAP_SHIFT = 5;
    private const FIELD_CUR_SHIFT = 6;

    // How many stats we remember for undo. Bounded so a long game cannot grow
    // memory without limit on small-memory watches.
    private const UNDO_DEPTH = 64;

    // ---- settings, refreshed whenever Garmin Connect pushes a change ----
    public var periodCount as Number = 3;
    public var periodMs as Number = 15 * 60 * 1000;
    public var shiftTargetMs as Number = 60 * 1000;
    public var shiftAlerts as Boolean = true;
    public var autoLap as Boolean = true;
    public var countDown as Boolean = true;

    // ---- live game state ----
    public var state as GameState = STATE_READY;
    public var period as Number = 1;
    public var goals as Number = 0;
    public var assists as Number = 0;
    public var shots as Number = 0;
    public var saves as Number = 0;
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
    private var _shiftAccumMs as Number = 0;
    private var _shiftSince as Number = -1;
    private var _completedShiftMs as Number = 0;
    private var _shiftAlerted as Boolean = false;
    private var _statLog as Array<Number> = [] as Array<Number>;

    private var _session as ActivityRecording.Session? = null;
    private var _goalsField as FitContributor.Field? = null;
    private var _assistsField as FitContributor.Field? = null;
    private var _shotsField as FitContributor.Field? = null;
    private var _savesField as FitContributor.Field? = null;
    private var _shiftsField as FitContributor.Field? = null;
    private var _lapShiftField as FitContributor.Field? = null;
    private var _curShiftField as FitContributor.Field? = null;

    //! Constructor.
    public function initialize() {
        loadSettings();
    }

    // ------------------------------------------------------------------
    // Settings
    // ------------------------------------------------------------------

    //! Re-read the user's settings. Safe to call at any time.
    public function loadSettings() as Void {
        periodCount = readNumber("periodCount", 3, 1, 9);
        periodMs = readNumber("periodMinutes", 15, 1, 60) * 60 * 1000;
        shiftTargetMs = readNumber("shiftSeconds", 60, 15, 600) * 1000;
        shiftAlerts = readBoolean("shiftAlerts", true);
        autoLap = readBoolean("autoLap", true);
        countDown = readBoolean("countDown", true);

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
        if (ms > periodMs) {
            ms = periodMs;
        }
        return ms;
    }

    //! What the big clock should show: time left, or time played, per settings.
    public function clockMs() as Number {
        if (countDown) {
            return periodMs - periodElapsedMs();
        }
        return periodElapsedMs();
    }

    //! Milliseconds in the shift currently on the ice/court.
    public function shiftMs() as Number {
        return _shiftAccumMs + sinceMs(_shiftSince);
    }

    //! Total clock time played across every period so far.
    public function totalPlayedMs() as Number {
        return _earlierPeriodsMs + periodElapsedMs();
    }

    //! Average length of the shifts that have been completed.
    public function averageShiftMs() as Number {
        var completed = shiftCount - 1;
        if (completed < 1) {
            return 0;
        }
        return (_completedShiftMs / completed).toNumber();
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

    //! Bank whatever the running clocks have accrued and stop them.
    private function freezeClocks() as Void {
        _periodAccumMs += sinceMs(_periodSince);
        _periodSince = -1;
        _shiftAccumMs += sinceMs(_shiftSince);
        _shiftSince = -1;
    }

    // ------------------------------------------------------------------
    // Game control
    // ------------------------------------------------------------------

    //! Start, or resume after a whistle.
    public function start() as Void {
        if (state == STATE_RUNNING || state == STATE_FINISHED) {
            return;
        }

        if (state == STATE_READY) {
            beginSession();
            shiftCount = 1;
            _shiftAlerted = false;
        }

        var session = _session;
        if (session != null && !session.isRecording()) {
            session.start();
        }

        var now = System.getTimer();
        _periodSince = now;
        if (_shiftSince < 0) {
            _shiftSince = now;
        }
        state = STATE_RUNNING;
        alert(Attention.TONE_START, [new Attention.VibeProfile(60, 200)]);
    }

    //! Stop the clock without ending the game.
    public function pause() as Void {
        if (state != STATE_RUNNING) {
            return;
        }
        freezeClocks();
        var session = _session;
        if (session != null && session.isRecording()) {
            session.stop();
        }
        state = STATE_PAUSED;
        alert(Attention.TONE_STOP, [new Attention.VibeProfile(60, 200)]);
    }

    //! One button for both, because that is how the START key behaves.
    public function toggleRun() as Void {
        if (state == STATE_RUNNING) {
            pause();
        } else {
            start();
        }
    }

    //! Close the current shift and open a new one. Also marks a FIT lap.
    public function newShift() as Void {
        if (state == STATE_READY || state == STATE_FINISHED) {
            return;
        }

        var elapsed = shiftMs();
        _completedShiftMs += elapsed;

        var lapField = _lapShiftField;
        if (lapField != null) {
            lapField.setData((elapsed / 1000).toNumber());
        }

        var session = _session;
        if (autoLap && session != null && session.isRecording()) {
            session.addLap();
        }

        _shiftAccumMs = 0;
        _shiftSince = (state == STATE_RUNNING) ? System.getTimer() : -1;
        _shiftAlerted = false;
        shiftCount++;

        var shiftsField = _shiftsField;
        if (shiftsField != null) {
            shiftsField.setData(shiftCount);
        }

        alert(Attention.TONE_LAP, [new Attention.VibeProfile(50, 150)]);
    }

    //! True when the period on screen is the last one of the game.
    public function isLastPeriod() as Boolean {
        return period >= periodCount;
    }

    //! Move to the next period. The clock starts stopped, as at a real faceoff.
    public function nextPeriod() as Void {
        if (state == STATE_FINISHED || isLastPeriod()) {
            return;
        }

        freezeClocks();
        var session = _session;
        if (session != null) {
            if (session.isRecording()) {
                session.addLap();
                session.stop();
            }
        }

        _earlierPeriodsMs += _periodAccumMs;
        _periodAccumMs = 0;
        _completedShiftMs += _shiftAccumMs;
        _shiftAccumMs = 0;
        _shiftAlerted = false;
        period++;

        // A game that has not been started yet stays unstarted.
        state = (state == STATE_READY) ? STATE_READY : STATE_PAUSED;
    }

    //! Count something that just happened on court.
    public function addStat(kind as StatKind) as Void {
        if (state == STATE_READY || state == STATE_FINISHED) {
            return;
        }

        if (kind == STAT_GOAL) {
            goals++;
        } else if (kind == STAT_ASSIST) {
            assists++;
        } else if (kind == STAT_SHOT) {
            shots++;
        } else if (kind == STAT_SAVE) {
            saves++;
        } else {
            return;
        }

        _statLog.add(kind);
        if (_statLog.size() > UNDO_DEPTH) {
            _statLog = _statLog.slice(1, null);
        }
        alert(Attention.TONE_KEY, [new Attention.VibeProfile(40, 80)]);
    }

    //! True when there is a stat that undo would remove.
    public function canUndo() as Boolean {
        return _statLog.size() > 0;
    }

    //! Take back the most recent stat. Fat fingers happen mid-game.
    public function undoStat() as Void {
        var count = _statLog.size();
        if (count == 0) {
            return;
        }

        var kind = _statLog[count - 1];
        _statLog = _statLog.slice(0, count - 1);

        if (kind == STAT_GOAL && goals > 0) {
            goals--;
        } else if (kind == STAT_ASSIST && assists > 0) {
            assists--;
        } else if (kind == STAT_SHOT && shots > 0) {
            shots--;
        } else if (kind == STAT_SAVE && saves > 0) {
            saves--;
        }
        alert(Attention.TONE_RESET, [new Attention.VibeProfile(40, 80)]);
    }

    //! Per-second housekeeping: alerts and the per-record FIT field.
    public function onTick() as Void {
        if (state != STATE_RUNNING) {
            return;
        }

        var shiftSeconds = (shiftMs() / 1000).toNumber();
        var curShiftField = _curShiftField;
        if (curShiftField != null) {
            curShiftField.setData(shiftSeconds);
        }

        if (shiftAlerts && !_shiftAlerted && shiftMs() >= shiftTargetMs) {
            _shiftAlerted = true;
            alert(Attention.TONE_ALERT_HI,
                [new Attention.VibeProfile(80, 250), new Attention.VibeProfile(0, 100), new Attention.VibeProfile(80, 250)]);
        }

        if (periodElapsedMs() >= periodMs) {
            endOfPeriod();
        }
    }

    //! The period clock hit zero.
    private function endOfPeriod() as Void {
        freezeClocks();
        var session = _session;
        if (session != null && session.isRecording()) {
            session.addLap();
            session.stop();
        }
        state = STATE_BREAK;
        alert(Attention.TONE_INTERVAL_ALERT,
            [new Attention.VibeProfile(100, 400), new Attention.VibeProfile(0, 150), new Attention.VibeProfile(100, 400)]);
    }

    //! Finish the game. Saving writes the activity to Garmin Connect.
    public function endGame(keep as Boolean) as Void {
        freezeClocks();
        _earlierPeriodsMs += _periodAccumMs;
        _periodAccumMs = 0;
        _completedShiftMs += _shiftAccumMs;
        _shiftAccumMs = 0;

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
        alert(Attention.TONE_STOP, [new Attention.VibeProfile(80, 400)]);
    }

    //! If the app is being killed mid-game, keep the activity rather than lose it.
    public function saveIfRecording() as Void {
        var session = _session;
        if (session == null) {
            return;
        }
        captureSummary();
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
                :sport => Activity.SPORT_HOCKEY,
                :subSport => Activity.SUB_SPORT_GENERIC
            });
            createFields();
        } catch (ex) {
            // Without a session the app still works as a scoreboard and clock.
            _session = null;
        }
    }

    //! Developer fields, so the counts travel with the activity into Connect.
    private function createFields() as Void {
        var session = _session;
        if (session == null) {
            return;
        }

        var seconds = WatchUi.loadResource($.Rez.Strings.UnitSeconds) as String;

        _goalsField = session.createField(
            WatchUi.loadResource($.Rez.Strings.FitGoals) as String,
            FIELD_GOALS, FitContributor.DATA_TYPE_UINT16,
            {:mesgType => FitContributor.MESG_TYPE_SESSION});
        _assistsField = session.createField(
            WatchUi.loadResource($.Rez.Strings.FitAssists) as String,
            FIELD_ASSISTS, FitContributor.DATA_TYPE_UINT16,
            {:mesgType => FitContributor.MESG_TYPE_SESSION});
        _shotsField = session.createField(
            WatchUi.loadResource($.Rez.Strings.FitShots) as String,
            FIELD_SHOTS, FitContributor.DATA_TYPE_UINT16,
            {:mesgType => FitContributor.MESG_TYPE_SESSION});
        _savesField = session.createField(
            WatchUi.loadResource($.Rez.Strings.FitSaves) as String,
            FIELD_SAVES, FitContributor.DATA_TYPE_UINT16,
            {:mesgType => FitContributor.MESG_TYPE_SESSION});
        _shiftsField = session.createField(
            WatchUi.loadResource($.Rez.Strings.FitShifts) as String,
            FIELD_SHIFTS, FitContributor.DATA_TYPE_UINT16,
            {:mesgType => FitContributor.MESG_TYPE_SESSION});
        _lapShiftField = session.createField(
            WatchUi.loadResource($.Rez.Strings.FitShiftTime) as String,
            FIELD_LAP_SHIFT, FitContributor.DATA_TYPE_UINT16,
            {:mesgType => FitContributor.MESG_TYPE_LAP, :units => seconds});
        _curShiftField = session.createField(
            WatchUi.loadResource($.Rez.Strings.FitShiftTime) as String,
            FIELD_CUR_SHIFT, FitContributor.DATA_TYPE_UINT16,
            {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => seconds});

        writeSessionFields();
    }

    //! Push the running totals into the session-level FIT fields.
    private function writeSessionFields() as Void {
        var field = _goalsField;
        if (field != null) { field.setData(goals); }
        field = _assistsField;
        if (field != null) { field.setData(assists); }
        field = _shotsField;
        if (field != null) { field.setData(shots); }
        field = _savesField;
        if (field != null) { field.setData(saves); }
        field = _shiftsField;
        if (field != null) { field.setData(shiftCount); }
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

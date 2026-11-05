//
// Automatic on-ice / on-bench detection.
//
// The watch is never touched during a game, so every shift boundary has to be
// inferred. Three signals are available and they are not equally good:
//
//   Wrist motion  - the only signal that responds within a second or two, and
//                   the only one that separates "skating" from "standing on the
//                   bench". It is also noisy, so it is never trusted instantly:
//                   a change has to persist before it is believed.
//   Heart rate    - reliable but slow. HR keeps climbing for 10-20 seconds after
//                   a shift ends and falls for a minute afterwards, so it can
//                   never open or close a shift on its own. It is used only to
//                   corroborate what motion already suspects, which lets the
//                   confirmation window be shortened.
//   GPS speed     - unambiguous when it exists (nobody reaches 3 m/s on a bench)
//                   but indoors it usually does not exist at all. Treated as a
//                   bonus vote, never a requirement.
//
// Thresholds are learned during the game rather than hard-coded, because the
// absolute numbers depend on the player, the watch's position on the wrist and
// how tight the strap is. The detector tracks a slow estimate of "this player's
// resting level" and "this player's working level" and puts the decision
// boundary between them.
//
// Because a boundary is only confirmed after it has persisted, the transition
// is reported as having happened in the past: backtrackMs() says how far back.
// The caller uses that to give the shift its true start time instead of the
// moment the detector made up its mind.
//

import Toybox.Lang;
import Toybox.Math;
import Toybox.Sensor;
import Toybox.System;

//! Where the player is right now.
enum IceState {
    OFF_ICE = 0,
    ON_ICE = 1
}

class ShiftDetector {

    // Nobody is skating below this much wrist motion, whatever the learned
    // levels say. Guards against the learned band collapsing during a long
    // stretch of stillness and then treating a fidget as a shift.
    private const MOTION_FLOOR = 85;        // milli-g

    // How wide the dead band around the decision boundary is. Motion has to
    // clear the upper edge to start a shift and drop below the lower edge to
    // end one, so noise sitting right on the boundary cannot flap the state.
    private const HYSTERESIS = 0.18;

    // Seconds a change must persist before it is believed.
    private const CONFIRM_ICE = 6;
    private const CONFIRM_BENCH = 10;

    // Shortened windows, used when heart rate or GPS agrees with motion.
    private const CONFIRM_ICE_FAST = 3;
    private const CONFIRM_BENCH_FAST = 5;

    // Heart rate samples kept for the slope estimate.
    private const HR_WINDOW = 20;

    // How fast heart rate has to be moving to count as agreeing with motion.
    //
    // Measured against twelve recorded games: at a shift change the median
    // slope is only about +0.2 bpm/s going on and -0.1 coming off, against a
    // background where half of all random 20-second windows already show
    // 0.23 bpm/s of drift. The separation is genuinely weak, which is the
    // evidence for keeping heart rate as corroboration only and never letting
    // it open or close a shift by itself.
    private const HR_SLOPE = 0.25;

    // Heart rate's distance from its own slow baseline is a much better signal
    // than its slope: across those games the swing between a shift and the
    // bench that follows it is 42-62 bpm, so the phase of the oscillation is
    // unmistakable even when the derivative is buried in noise.
    private const HR_OFFSET = 4.0;

    // A shift shorter than this is noise, not a line change.
    private const MIN_SHIFT_SEC = 8;
    private const MIN_BENCH_SEC = 8;

    public var state as IceState = OFF_ICE;

    // Last motion index, exposed so the UI can show a detection bar.
    public var motion as Number = 0;
    public var threshold as Number = MOTION_FLOOR;
    public var hasMotionSensor as Boolean = false;

    // Seconds since the accelerometer last delivered anything. The listener
    // can fail to register, or stop delivering, without raising an error -
    // so silence has to be treated as a fault in its own right rather than
    // as a player who is standing very still.
    public var staleSeconds as Number = 0;

    //! Sample magnitudes from a batch too short to measure, held over for the
    //! next batch. See onSensorData().
    private var _carry as Array<Float> = [] as Array<Float>;

    //! The fewest samples a mean absolute deviation is worth taking over.
    //! Below this the figure is dominated by whichever one sample happened to
    //! sit furthest from the mean.
    private const MIN_SAMPLES = 4;

    //! And the most to take one over. Accelerometer rates on supported devices
    //! top out at 25 Hz, so a window past this is a backlog, not a second.
    private const MAX_WINDOW = 32;

    private var _rest as Float = 40.0;
    private var _work as Float = 400.0;
    private var _band as Float = 0.45;

    private var _iceStreak as Number = 0;
    private var _benchStreak as Number = 0;
    private var _secondsInState as Number = 0;
    private var _backtrackMs as Number = 0;

    private var _hr as Array<Number> = [] as Array<Number>;
    private var _hrBaseline as Float = 0.0;
    private var _speed as Float? = null;

    private var _listening as Boolean = false;
    // Samples delivered since the last tick, kept as a running total rather
    // than a single slot.
    //
    // The sensor callback and the tick that consumes it are two independent
    // 1 Hz clocks, and they drift against each other: in the game of
    // 2026-11-03 the phase slipped far enough to miss a second every five or
    // six seconds, 501 times in all. A missed second is survivable - tick()
    // holds the state, which measurement shows is the right thing to do - but
    // the same slip hands two callbacks to some other second, and this used to
    // be one slot that the second callback overwrote. That silently threw away
    // a second of real wrist motion, roughly one second in seven, and the
    // learner never saw any of it.
    private var _pendingSum as Number = 0;
    private var _pendingCount as Number = 0;

    //! Constructor. sensitivity: 0 low (fewer, longer shifts), 1 normal, 2 high.
    public function initialize(sensitivity as Number) {
        setSensitivity(sensitivity);
    }

    //! Move the decision boundary within the learned band. A high sensitivity
    //! puts it closer to the resting level, so less movement counts as a shift.
    //!
    //! Fitted to the game of 2026-11-03 with tools/replay_detector.py, which
    //! replays a recorded game through this state machine offline. The band
    //! used to sit at 0.45 on normal, which was a guess and was wrong: the
    //! working level is dragged up by collisions and board contact - that game
    //! peaked at 2450 mg against a median of 75 - so a boundary 45% of the way
    //! up the band landed at the 82nd percentile of the player's own motion.
    //! At most 18% of the game could be counted as ice time whatever happened
    //! on it, and the shifts that were found had their beginnings and ends
    //! clipped off: 25 shifts, but a median of 17 seconds each.
    //!
    //! 0.27 was chosen because four independent checks agree on it at once:
    //! ice time 34% against the ~33% a three-line bench implies, 23 shifts
    //! against the 22 cycles heart rate shows by itself, a 45-second median
    //! shift, and a 147-second shift cycle against 141 from heart rate and the
    //! ~160 this player actually plays. It is one game, so it is a first fit
    //! rather than a final one - but the motion and threshold are written into
    //! every FIT file, so the next game can re-check it without a rink.
    public function setSensitivity(sensitivity as Number) as Void {
        if (sensitivity <= 0) {
            _band = 0.35;
        } else if (sensitivity >= 2) {
            _band = 0.21;
        } else {
            _band = 0.27;
        }
    }

    // ------------------------------------------------------------------
    // Sensor plumbing
    // ------------------------------------------------------------------

    //! Start sampling the accelerometer. Safe on watches that have none.
    public function start() as Void {
        if (_listening) {
            return;
        }
        if (!(Toybox has :Sensor) || !(Sensor has :registerSensorDataListener)) {
            return;
        }
        try {
            Sensor.registerSensorDataListener(method(:onSensorData), {
                :period => 1,
                :accelerometer => {
                    :enabled => true,
                    :sampleRate => pickSampleRate()
                }
            });
            _listening = true;
        } catch (ex) {
            // No accelerometer access. The app still runs; the player just has
            // to mark shift changes from the menu.
            _listening = false;
        }
    }

    //! Stop sampling. Called when the game ends or the activity is paused for
    //! long enough that sampling is only costing battery.
    public function stop() as Void {
        if (!_listening) {
            return;
        }
        try {
            Sensor.unregisterSensorDataListener();
        } catch (ex) {
            // Nothing useful to do; the listener is going away either way.
        }
        _listening = false;
    }

    //! Throw away samples collected but not yet judged.
    //!
    //! Used on resume. Samples that arrived before a pause describe a player
    //! standing on the bench with the clock stopped; averaged into the first
    //! second of play they would describe neither that nor this.
    public function flushPending() as Void {
        _pendingSum = 0;
        _pendingCount = 0;
        // Including the carried leftovers, which are stale for the same
        // reason and would otherwise be the oldest part of the first window
        // measured after the resume.
        _carry = [] as Array<Float>;
        staleSeconds = 0;
    }

    //! The fastest rate this watch will give us, capped: the decision only
    //! needs gross limb movement, and a high rate costs battery for nothing.
    private function pickSampleRate() as Number {
        var rate = 25;
        if (Sensor has :getMaxSampleRateForSensorType) {
            try {
                var maximum = Sensor.getMaxSampleRateForSensorType(:accelerometer);
                if (maximum != null && maximum instanceof Lang.Number && maximum > 0) {
                    rate = (maximum < 25) ? maximum : 25;
                }
            } catch (ex) {
                rate = 25;
            }
        }
        return rate;
    }

    //! Accelerometer callback, once a second with a second's worth of samples.
    //!
    //! The measure used is the mean absolute deviation of the acceleration
    //! magnitude. Taking the magnitude removes the watch's orientation from the
    //! answer, and taking the deviation about the mean removes gravity, so what
    //! is left is how much the arm actually moved - which is what separates a
    //! stride from a forearm resting on the boards.
    public function onSensorData(data as Sensor.SensorData) as Void {
        var accel = data.accelerometerData;
        if (accel == null) {
            return;
        }
        var xs = accel.x;
        var ys = accel.y;
        var zs = accel.z;
        if (xs == null || ys == null || zs == null) {
            return;
        }

        var count = xs.size();
        if (count > ys.size()) { count = ys.size(); }
        if (count > zs.size()) { count = zs.size(); }
        if (count < 1) {
            return;
        }

        // Magnitudes first, and only then the deviation. A magnitude depends
        // on nothing but its own sample, which is what makes it safe to carry
        // leftovers across callbacks; the deviation is taken about the mean of
        // its window, so it has to wait until there is a window to take it
        // over.
        var i;
        var magnitudes = _carry;
        for (i = 0; i < count; i++) {
            var x = xs[i].toFloat();
            var y = ys[i].toFloat();
            var z = zs[i].toFloat();
            magnitudes.add(Math.sqrt((x * x) + (y * y) + (z * z)).toFloat());
        }

        var n = magnitudes.size();
        if (n < MIN_SAMPLES) {
            // Too few to take a deviation over, so hold them for the next
            // callback instead of dropping them. Dropping them was the old
            // behaviour and it had a nasty failure: a device that delivers
            // samples in twos would discard every batch, never touch
            // _pendingCount, and so register as an accelerometer that is not
            // delivering at all. staleSeconds would climb past 10 and stay
            // there, isHealthy() would be false for the whole game, the
            // sensor-failure buzz would fire, the shift detector would hold
            // one state from the opening faceoff - and the auto-end would be
            // disabled too, since it refuses to run on an unhealthy detector.
            // A whole game lost to a batch size, on hardware that was working.
            _carry = magnitudes;
            return;
        }

        if (n > MAX_WINDOW) {
            // A backlog this long means the callbacks bunched up, and the
            // oldest samples in it describe a second that has already been
            // reported. Keep the newest window and let the rest go.
            magnitudes = magnitudes.slice(n - MAX_WINDOW, null);
            n = MAX_WINDOW;
        }
        _carry = [] as Array<Float>;

        var sum = 0.0;
        for (i = 0; i < n; i++) {
            sum += magnitudes[i];
        }
        var mean = sum / n;
        var deviation = 0.0;
        for (i = 0; i < n; i++) {
            var d = magnitudes[i] - mean;
            deviation += (d < 0) ? -d : d;
        }

        // Add rather than replace. Two callbacks between ticks both count.
        _pendingSum += (deviation / n).toNumber();
        _pendingCount++;
    }

    // ------------------------------------------------------------------
    // Decision
    // ------------------------------------------------------------------

    //! Feed in the current heart rate and GPS speed. Both may be null.
    public function observe(heartRate as Number?, speedMps as Float?) as Void {
        if (heartRate != null && heartRate > 0) {
            _hr.add(heartRate);
            if (_hr.size() > HR_WINDOW) {
                _hr = _hr.slice(1, null);
            }
            // A slow baseline, around a three-minute time constant, so it
            // tracks the drift of the game rather than the swing of a shift.
            if (_hrBaseline <= 0.0) {
                _hrBaseline = heartRate.toFloat();
            } else {
                _hrBaseline += (heartRate.toFloat() - _hrBaseline) * 0.0055;
            }
        }
        _speed = speedMps;
    }

    //! Run one second of the state machine. Returns true when the state just
    //! changed, in which case backtrackMs() says how long ago it really changed.
    public function tick() as Boolean {
        _secondsInState++;

        if (_pendingCount < 1) {
            // No accelerometer data this second. Hold the current state rather
            // than guess: a dropped callback is not evidence of anything.
            //
            // Carrying the previous sample forward instead was tried against
            // the 2026-11-03 recording and is worse. It repeats whatever the
            // last value was, which advances the confirmation streaks on
            // evidence that was already counted, and the shift count went from
            // 23 to 29 against the 22 heart rate shows on its own - a 81-second
            // cycle where the player actually plays about 160.
            staleSeconds++;
            return false;
        }
        var sample = _pendingSum / _pendingCount;
        _pendingSum = 0;
        _pendingCount = 0;
        hasMotionSensor = true;
        staleSeconds = 0;
        motion = sample;

        learn(sample);

        var upper = (threshold * (1.0 + HYSTERESIS)).toNumber();
        var lower = (threshold * (1.0 - HYSTERESIS)).toNumber();

        if (sample >= upper) {
            _iceStreak++;
            _benchStreak = 0;
        } else if (sample <= lower) {
            _benchStreak++;
            _iceStreak = 0;
        } else {
            // In the dead band: let both streaks decay rather than reset, so a
            // single ambiguous second does not throw away nine good ones.
            if (_iceStreak > 0) { _iceStreak--; }
            if (_benchStreak > 0) { _benchStreak--; }
        }

        if (state == OFF_ICE) {
            var needed = corroboratesIce() ? CONFIRM_ICE_FAST : CONFIRM_ICE;
            if (_iceStreak >= needed && _secondsInState >= MIN_BENCH_SEC) {
                return transition(ON_ICE, needed);
            }
        } else {
            var wanted = corroboratesBench() ? CONFIRM_BENCH_FAST : CONFIRM_BENCH;
            if (_benchStreak >= wanted && _secondsInState >= MIN_SHIFT_SEC) {
                return transition(OFF_ICE, wanted);
            }
        }

        return false;
    }

    //! Update the learned resting and working levels. Both chase the sample,
    //! but each moves quickly only in its own direction: the resting estimate
    //! drops fast and rises slowly, the working estimate the other way round.
    //! That keeps the band anchored to the extremes the player actually reaches
    //! instead of drifting towards whatever they did most recently.
    private function learn(sample as Number) as Void {
        var value = sample.toFloat();

        if (value < _rest) {
            _rest += (value - _rest) * 0.15;
        } else {
            _rest += (value - _rest) * 0.01;
        }

        if (value > _work) {
            _work += (value - _work) * 0.15;
        } else {
            _work += (value - _work) * 0.01;
        }

        // Keep a sane gap: if the band collapses, every twitch looks decisive.
        if (_work < _rest + 60.0) {
            _work = _rest + 60.0;
        }

        var boundary = _rest + ((_work - _rest) * _band);
        threshold = (boundary < MOTION_FLOOR) ? MOTION_FLOOR : boundary.toNumber();
    }

    //! Heart rate agreeing that work is starting, or GPS saying the player is
    //! moving at skating speed.
    private function corroboratesIce() as Boolean {
        var speed = _speed;
        if (speed != null && speed >= 2.5) {
            return true;
        }
        return hrSlope() >= HR_SLOPE || hrOffset() >= HR_OFFSET;
    }

    //! Heart rate agreeing that work has stopped, or GPS saying the player has.
    private function corroboratesBench() as Boolean {
        var speed = _speed;
        if (speed != null && speed <= 0.6) {
            return true;
        }
        return hrSlope() <= -HR_SLOPE || hrOffset() <= -HR_OFFSET;
    }

    //! How far the current heart rate sits above or below its slow baseline.
    private function hrOffset() as Float {
        var size = _hr.size();
        if (size < 8 || _hrBaseline <= 0.0) {
            return 0.0;
        }
        return _hr[size - 1].toFloat() - _hrBaseline;
    }

    //! Change in heart rate in beats per second across the window.
    private function hrSlope() as Float {
        var size = _hr.size();
        if (size < 8) {
            return 0.0;
        }
        var first = _hr[0].toFloat();
        var last = _hr[size - 1].toFloat();
        return (last - first) / (size - 1).toFloat();
    }

    //! Commit a state change and record how far back it really started.
    private function transition(next as IceState, confirmSeconds as Number) as Boolean {
        state = next;
        _backtrackMs = confirmSeconds * 1000;
        _iceStreak = 0;
        _benchStreak = 0;
        _secondsInState = 0;
        return true;
    }

    //! How long before the detector made up its mind the change actually
    //! happened. Shift boundaries are dated back by this much.
    public function backtrackMs() as Number {
        return _backtrackMs;
    }

    //! Force the state, for the manual correction in the menu.
    public function forceState(next as IceState) as Void {
        state = next;
        _backtrackMs = 0;
        _iceStreak = 0;
        _benchStreak = 0;
        _secondsInState = 0;
    }

    //! True when the accelerometer is actually delivering. Everything the
    //! detector does depends on this, and nothing else in the app will fail
    //! visibly if it is false - the game would simply record as one very long
    //! shift - so it is surfaced on screen rather than left to be discovered
    //! afterwards.
    public function isHealthy() as Boolean {
        return hasMotionSensor && staleSeconds < 10;
    }

    //! Reset the learned levels. Used when a new game starts.
    public function reset() as Void {
        _rest = 40.0;
        _work = 400.0;
        _hr = [] as Array<Number>;
        _hrBaseline = 0.0;
        _speed = null;
        _pendingSum = 0;
        _pendingCount = 0;
        _carry = [] as Array<Float>;
        motion = 0;
        threshold = MOTION_FLOOR;
        staleSeconds = 0;
        forceState(OFF_ICE);
    }
}

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
//                   never open or close a shift on its own. It is used mostly to
//                   corroborate what motion already suspects, which lets the
//                   confirmation window be shortened - and in one place to
//                   contradict it: see HR_VETO, which refuses a shift outright
//                   while the rate sits far below its own baseline.
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
    //
    // Ending a shift takes longer to believe than starting one, and the gap
    // widened after the game of 2026-11-05. Ten seconds was not enough: a
    // defenceman standing at the point, gliding, or waiting out a stoppage
    // drops below the boundary for long enough to end the shift, and the
    // detector then started a fresh one when he moved again. That game came
    // back with 48 shifts of a median 21 seconds against the 31 cycles its
    // own heart rate trace shows. At fourteen seconds the same game reads 32
    // shifts of a median 41 seconds.
    //
    // (48 and 21s are the watch's own recorded session figures. An earlier
    // comment here said 45 of a median 18s, which was a replay at a band the
    // file was not recorded at.)
    // Entry stays at SIX seconds. It was raised to ten on 2026-11-07 to answer
    // the complaint that moving a wrist on the bench collects shifts nobody
    // played, and it was reverted the same day. The reasoning was sound and
    // the measurement was not; keeping the record here so nobody re-runs it.
    //
    // Three things killed it:
    //
    //  - Ten seconds is unreachable by motion alone. ice_streak resets to
    //    zero on any second at or below the lower hysteresis band, and real
    //    skating dips below it. With the fast path disabled, 0 of 232 off-ice
    //    motion bursts on 2026-11-03 ever reach a ten-second streak, and only
    //    12 of 459 on 2026-11-05.
    //
    //  - The sweep that chose it measured almost nothing. corroboratesIce()
    //    is true on roughly half of all judgeable seconds, so nearly every
    //    real entry takes CONFIRM_ICE_FAST: 29 fast against 3 slow on
    //    2026-11-05, and 16 against 0 on 2026-11-03. The 6/10/12/15 table
    //    that justified the change turned on three slow-path entries on one
    //    game and none at all on the other, and it left every one of the
    //    fast path's false positives in place (5 and 3, unchanged).
    //
    //    That second point has since been fixed at its source rather than by
    //    moving CONFIRM_ICE. corroboratesIce() no longer consults hrOffset()
    //    - see the note where HR_OFFSET used to be - and now fires on 0.185
    //    of bench seconds instead of 0.424. The fast path is selective at
    //    last and CONFIRM_ICE is load-bearing again, so the entry window is
    //    the one knob here that has NOT been re-swept against the games.
    //
    //  - With no heart rate it fails hard, which is the case that matters:
    //    wrist optical only, no strap, and 0 position fixes in 5,122 records
    //    at this player's rink. At the shipped band, motion alone:
    //
    //      2026-11-05   6s -> 21 shifts, max bench  297s
    //                  10s -> 13 shifts, max bench 1221s
    //      2026-11-03   6s -> 15 shifts, max bench  387s
    //                  10s ->  8 shifts, max bench  808s
    //
    //    A twenty-minute single bench block on a game where the longest real
    //    one is five minutes, and nothing warns, because isHealthy() only
    //    watches the accelerometer.
    //
    // Two claims made for the change were simply false and are withdrawn: it
    // cost 1.4 points of recorded ice on 11-03 and 2.3 on 11-05, not none,
    // because removing a shift removes all of its seconds rather than only
    // the confirmation window; and shifts the heart rate supports were lost.
    // Both held only while heart rate was present, which was the unstated
    // premise of the entire result.
    //
    // The diagnosis still stands: this is an ENTRY-edge problem and no
    // amplitude cut separates it, because the spurious shifts carry HIGHER
    // wrist motion than a defenceman's glide. What does not stand is that
    // duration separates it. Also ruled out by measurement since: a longer
    // fast window (removes good shifts twice as fast as bad), a
    // preceding-bench-length rule (no separation - long benches are normal
    // for a defenceman), and a retroactive minimum shift length (removes real
    // shifts at the same rate). And the below-median-heart-rate proxy used to
    // score all of it is partly a WARM-UP detector: on 11-05 those shifts sit
    // at 112-134 bpm against a 136 median, concentrated in the first quarter
    // of a file that started seventeen minutes before the opening faceoff.
    // Warm-up skating is real skating.
    //
    // Fixing this needs ground truth for line changes, which no FIT file
    // supplies. See docs/detector-tuning.md.
    private const CONFIRM_ICE = 6;
    private const CONFIRM_BENCH = 14;

    // Shortened windows, used when heart rate or GPS agrees with motion.
    private const CONFIRM_ICE_FAST = 3;
    private const CONFIRM_BENCH_FAST = 7;

    // Heart rate samples kept for the slope estimate.
    private const HR_WINDOW = 20;

    // How fast heart rate has to be moving to count as agreeing with motion.
    //
    // Measured against twelve recorded games: at a shift change the median
    // slope is only about +0.2 bpm/s going on and -0.1 coming off, against a
    // background where half of all random 20-second windows already show
    // 0.23 bpm/s of drift. The separation is genuinely weak, which is the
    // evidence for keeping heart rate as corroboration and never letting it
    // open or close a shift by itself. It may still REFUSE one - see HR_VETO,
    // which needs no slope and reads a level instead.
    private const HR_SLOPE = 0.25;

    // There is no HR_OFFSET any more, and the reason is measured rather than
    // argued. An earlier version read `hrSlope() >= HR_SLOPE || hrOffset() >=
    // HR_OFFSET` with HR_OFFSET = 4.0, on the theory that distance from the
    // slow baseline is a better signal than slope because the peak-to-trough
    // swing of one shift-plus-bench cycle is 42-62 bpm.
    //
    // That theory confused a within-cycle range with the separation available
    // in any one second. Scored against the three recorded games, 9179
    // seconds carrying both a heart rate and a verdict:
    //
    //   test                                  P(+|ice)  P(+|bench)    LR
    //   slope >= 0.25 OR offset >= 4.0 (old)     0.694       0.424   1.64
    //   slope >= 0.25 alone            (now)     0.444       0.185   2.40
    //
    // The offset arm is close to pure noise: sweeping its threshold across
    // the entire observed range of hrOffset moves the likelihood ratio only
    // between 1.0 and 1.7, with no peak to aim at. Slope has a real peak, and
    // 0.25 already sits on it - the LR-optimal 0.29 scores 2.46 against
    // 2.40, which is not worth moving for. OR-ing the two did what OR-ing a
    // noisy test with a good one always does: it more than doubled the false
    // positive rate, 0.185 to 0.424, to buy 0.25 of true positive rate.
    //
    // That mattered more than a corroboration signal usually would, because
    // corroboration picks the confirmation window. At P(+|bench) = 0.424 the
    // three-second fast path was effectively always open, CONFIRM_ICE was
    // very nearly dead code, and a bench fidget needed only three seconds of
    // motion to become a shift. Replaying the recorded motion through the
    // detector, dropping the arm removes 7 shifts and 112 s of ice from
    // 2026-11-03 and 7 shifts and 255 s from 2026-11-05, and halves the
    // shifts that never lift the rate above 130 bpm - the bench-fidget
    // signature - from 4 to 2.
    //
    // hrOffset() itself stays. It is still the right instrument for HR_VETO
    // below, which reads a level and not a derivative, and which scores an LR
    // of 3.06 at -12.0 precisely because it asks a much deeper question than
    // four beats.

    // A shift shorter than this is noise, not a line change - and so is a
    // bench shorter than this.
    //
    // These were both 8 until 2.5.4, which made a complete on-ice/bench/
    // on-ice cycle legal in 16 seconds. On 2026-11-09 a player reported the
    // app "vibrating every ten seconds switching between on ice and bench"
    // while he sat on the bench, which is that number being spent.
    //
    // 20 is cheap. Swept through tools/replay_detector.py over the two full
    // recorded games at 8/12/16/20/25/30, the ice share moves by less than a
    // point anywhere in that range and the shift count by at most two,
    // because real shifts and real benches are far longer than any of these:
    // the median shift is 49-96 s. All these constants really bound is how
    // fast the detector is allowed to change its mind, and 8 s was far
    // faster than hockey happens.
    private const MIN_SHIFT_SEC = 20;
    private const MIN_BENCH_SEC = 20;

    // How far below its own baseline the heart rate has to sit before a shift
    // is refused outright, however convincing the motion looks.
    //
    // Everything else here uses heart rate only to agree with motion, never to
    // contradict it - the slope separation is too weak to be trusted on its
    // own. This is the one exception, and it is not a slope: a rate sitting a
    // dozen beats under its drifting baseline is a player at rest, and no
    // amount of wrist movement makes that a shift. Eighteen of the 48 shifts
    // found in the game of 2026-11-05 never lifted the rate out of zone 2 at
    // all - one of them ran 53 seconds with a peak of 119 bpm - which is what
    // sitting between periods and shifting around looks like to an
    // accelerometer. On its own the veto removes six of them and costs nothing
    // on the game of 2026-11-03, which had none to begin with. An earlier
    // version of this comment credited it with nine, which was the combined
    // effect of the band change, the confirmation window and the veto
    // together - an easy and flattering mistake to make when three things
    // change in one commit.
    private const HR_VETO = 12.0;

    public var state as IceState = OFF_ICE;

    // Last motion index, exposed so the UI can show a detection bar.
    public var motion as Number = 0;
    public var threshold as Number = MOTION_FLOOR;
    public var hasMotionSensor as Boolean = false;

    //! Accumulated on-ice load, in the units the team-sport literature calls
    //! PlayerLoad: the sample-to-sample change in the acceleration vector,
    //! root-sum-squared across the three axes, summed, and divided by 100.
    //!
    //! It is accumulated ON ICE ONLY, which departs from the published metric
    //! deliberately. Catapult's version runs over a whole session; ours would
    //! then count a player fidgeting on the bench as work done, and this
    //! detector's own history says bench motion is not small - it measures
    //! HIGHER than a defenceman's glide. A load figure that rises while you
    //! sit down is worse than no load figure, so the field is named for what
    //! it actually counts.
    //!
    //! Treat it as comparable to your own past games and to nothing else.
    //! Reliability in men's collegiate hockey is moderate-to-large, but a 2026
    //! review reports its construct validity is still unverified.
    public var iceLoad as Float = 0.0;

    // Previous sample, for the difference the load is taken over. Held across
    // callbacks for the same reason magnitudes are: a difference spanning two
    // batches is a real difference, and dropping it would under-count by one
    // sample in every batch.
    private var _lastX as Float = 0.0;
    private var _lastY as Float = 0.0;
    private var _lastZ as Float = 0.0;
    private var _lastPrimed as Boolean = false;

    //! Stride rate, measured from the same samples the motion index is taken
    //! over. Kept as its own object because it is a different question with
    //! a different confidence: the motion index decides where a shift starts
    //! and is trusted, this counts strides and is on trial.
    public var stride as StrideMeter = new StrideMeter();

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

    // Seconds since observe() last had a heart rate, and since it last had a
    // speed. Without these a sensor that stops reporting keeps its final
    // reading on the books forever: hrOffset() would go on answering from a
    // window whose newest sample is minutes old, latching HR_VETO or a fast
    // path; and _speed, which GameModel caches from onPosition() and re-feeds
    // every single second, would latch corroboratesBench() true for the rest
    // of the game off ONE fix that happened to read near zero.
    private var _hrAge as Number = 0;
    private var _speedAge as Number = 0;

    // How old a reading may be and still vote. Heart rate gets a generous
    // window because optical dropouts of a few seconds are routine and the
    // baseline moves slowly; speed gets a tight one because a position fix is
    // a point in time and a stale one is simply wrong.
    private const HR_MAX_AGE = 10;
    private const SPEED_MAX_AGE = 4;
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
    //! Fitted with tools/replay_detector.py, which replays a recorded game
    //! through this state machine offline. The history matters, because each
    //! value was wrong for a different reason.
    //!
    //! 0.45 was a guess. The working level is dragged up by collisions and
    //! board contact - the game of 2026-11-03 peaked at 2450 mg against a
    //! median of 75 - so a boundary 45% of the way up the band landed at the
    //! 82nd percentile of the player's own motion. At most 18% of a game could
    //! count as ice time whatever happened on it.
    //!
    //! 0.27 was fitted, and still wrong, because one of the four checks it was
    //! fitted against was not this player's to hit. That check was ice time
    //! against "the ~33% a three-line bench implies", which is the share of a
    //! forward. He plays defence, where the share is two spots divided by the
    //! number of defencemen dressed: 50% with two pairs, 40% with five, 33%
    //! only with six. Scoring a detector against a target 7 to 17 points too
    //! low pushed the boundary correspondingly too high, in the same direction
    //! and by the same amount on both games on file. Worse, 0.22 was rejected
    //! at the time despite having the best agreement with the heart-rate phase
    //! reference of anything tried, on the grounds that its ice time
    //! "overshoots" - it did not; it was still short.
    //!
    //! 0.18 is fitted against checks that do not need to know the bench size,
    //! because that is the quantity the old fit got wrong and no file records
    //! it. Shift count and cycle length both come from the heart rate trace
    //! with motion never consulted, and on that score every band from 0.14 to
    //! 0.20 beats 0.27 by a wide margin on both recorded games. Within that
    //! window the one game whose bench is actually known - 2026-11-05, five
    //! defencemen, so two of five spots and a 40% share - picks 0.18: it reads
    //! 42.9% ice, 32 shifts against 31 heart-rate cycles, and a 125-second
    //! cycle against 127. 0.14 reads 46.3% and overshoots a number we know.
    //!
    //! Still two games, and only one of them with a verified ice-time target.
    //! The motion index and the learned threshold are written into every FIT
    //! file, so the next game re-checks this without a trip to a rink.
    public function setSensitivity(sensitivity as Number) as Void {
        if (sensitivity <= 0) {
            _band = 0.24;
        } else if (sensitivity >= 2) {
            _band = 0.14;
        } else {
            _band = 0.18;
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

        // Drop the confirmation streaks. They are evidence about seconds that
        // are now on the far side of a pause, and counting them toward a
        // change confirmed after the resume would let an intermission supply
        // most of a window that play is then credited with filling.
        _iceStreak = 0;
        _benchStreak = 0;

        // Drop the PlayerLoad anchor too, or the first sample after the
        // resume is differenced against the last one before the pause and a
        // whole intermission's worth of arm movement lands in iceLoad as a
        // single lurch.
        _lastPrimed = false;

        // And age the sensor readings out by hand, because nothing else will.
        // GameModel.onTick() returns before observe() while the game is
        // paused, so _hrAge and _speedAge are FROZEN for the whole
        // intermission and resume holding whatever they held when play
        // stopped. Without this, the first seconds of the second period are
        // judged against a fifteen-minute-old heart rate and a
        // fifteen-minute-old position fix - the exact latch these counters
        // were added to close, re-opened by the one event that guarantees the
        // readings are stale. A pause means the sensors have told us nothing
        // since, so say so.
        _hrAge = HR_MAX_AGE + 1;
        _speedAge = SPEED_MAX_AGE + 1;
        _speed = null;
        // The rolling heart-rate window is evidence about the same vanished
        // seconds. restingHeartRate() compares its last entry against the
        // baseline, and a pre-pause rate below that baseline would refuse
        // entry to the ice for the first seconds back on.
        _hr = [] as Array<Number>;
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
        stride.reset();
        // A difference taken across a pause is not a difference: the two
        // samples either side of it can be minutes apart, and the load would
        // collect one large spurious step per resume.
        _lastPrimed = false;
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
            var magnitude = Math.sqrt((x * x) + (y * y) + (z * z)).toFloat();
            magnitudes.add(magnitude);

            // PlayerLoad, on ice only. The axes arrive in milli-g and the
            // published formula is in g, hence the 1000; the further 100 is
            // the divisor Catapult uses to keep the number human-sized.
            if (_lastPrimed && state == ON_ICE) {
                var dx = (x - _lastX) / 1000.0;
                var dy = (y - _lastY) / 1000.0;
                var dz = (z - _lastZ) / 1000.0;
                iceLoad += Math.sqrt((dx * dx) + (dy * dy) + (dz * dz)).toFloat() / 100.0;
            }
            _lastX = x;
            _lastY = y;
            _lastZ = z;
            _lastPrimed = true;
            // Every sample, exactly once, whatever happens to the window
            // below - the stride meter keeps its own six-second history and
            // must not see a sample twice or miss one.
            stride.push(magnitude);
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
        if (heartRate == null || heartRate <= 0) {
            _hrAge++;
        } else {
            _hrAge = 0;
        }
        if (speedMps == null) {
            _speedAge++;
        } else {
            _speedAge = 0;
        }
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
        if (speedMps != null) {
            _speed = speedMps;
        } else {
            // Dropped on the FIRST null, not after SPEED_MAX_AGE more of
            // them. The model already ages its own cache and stops supplying
            // a fix once it is SPEED_STALE_AFTER seconds old; holding that
            // same fix here for a further SPEED_MAX_AGE seconds does not
            // reinforce the guard, it COMPOSES with it, and the two together
            // let a fix vote for about nine seconds while both constants and
            // both comments claimed four. One authority on freshness, at the
            // place that knows when the reading arrived.
            _speed = null;
        }
    }

    //! Heart rate recent enough to be allowed a vote.
    private function hrIsFresh() as Boolean {
        return _hrAge <= HR_MAX_AGE;
    }

    //! Speed recent enough to be allowed a vote.
    private function speedIsFresh() as Boolean {
        return _speed != null && _speedAge <= SPEED_MAX_AGE;
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

        // Only judge a stride while the player is on the ice and actually
        // moving. The shift detector's own verdict is a free pre-gate: it
        // removes every bench and standing second before any of the
        // autocorrelation arithmetic runs, which keeps the average cost far
        // below the worst case on a device whose watchdog is a bytecode
        // budget rather than a clock.
        stride.update(state == ON_ICE && sample >= threshold);

        if (state == OFF_ICE) {
            var needed = corroboratesIce() ? CONFIRM_ICE_FAST : CONFIRM_ICE;
            if (_iceStreak >= needed && _secondsInState >= MIN_BENCH_SEC
                    && !restingHeartRate()) {
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
        if (speedIsFresh() && speed != null && speed >= 2.5) {
            return true;
        }
        if (!hrIsFresh()) {
            return false;
        }
        return hrSlope() >= HR_SLOPE;
    }

    //! Heart rate agreeing that work has stopped, or GPS saying the player has.
    private function corroboratesBench() as Boolean {
        var speed = _speed;
        if (speedIsFresh() && speed != null && speed <= 0.6) {
            return true;
        }
        if (!hrIsFresh()) {
            return false;
        }
        return hrSlope() <= -HR_SLOPE;
    }

    //! Heart rate low enough to rule a shift out regardless of motion.
    //!
    //! hrOffset() returns 0.0 before the window has filled or while there is
    //! no baseline yet, so this is false until there is something to judge -
    //! which is what the start of a game needs.
    private function restingHeartRate() as Boolean {
        // A stale rate may not veto. This is the only place heart rate is
        // allowed to CONTRADICT motion rather than agree with it, so a dead
        // sensor latching it here does not merely lose corroboration - it
        // refuses shifts the player really skated, for the rest of the game.
        if (!hrIsFresh()) {
            return false;
        }
        return hrOffset() <= -HR_VETO;
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
        iceLoad = 0.0;
        _lastPrimed = false;
        stride.reset();
        forceState(OFF_ICE);
    }
}

import Toybox.Lang;
import Toybox.Math;

//! Stride rate from the wrist, by autocorrelation.
//!
//! The shift detector already reduces every accelerometer batch to one number
//! a second and throws the samples away. This keeps them: band-passed into a
//! six-second ring, they carry the rhythm of the skating stride, and the lag
//! at which that ring best matches itself is the stride period.
//!
//! WHY AUTOCORRELATION AND NOT AN FFT. A skating stride is a low duty-cycle
//! pulse train - a push, then a long glide - and an FFT spreads that energy
//! into harmonics, so the fundamental bin is often not the largest one. The
//! autocorrelation of a pulse train peaks cleanly at the period. It also
//! needs no power-of-two window, no bit reversal and no twiddle table, its
//! lag grid is finer than an equal-length FFT's bins across the band that
//! matters (0.063 Hz at 1.2 Hz against a uniform 0.167 Hz), and - the reason
//! that settles it - the height of the peak is a confidence number in 0..1,
//! which is exactly what the glide problem needs.
//!
//! WHAT THIS IS NOT. No study has ever measured wrist accelerometry during
//! skating. The hockey biomechanics literature models the lower limb, trunk
//! and ankle; across six papers read for this work the word "arm" does not
//! appear once. The nearest analogue that has been measured is wrist step
//! counting with a hand fixed to a shopping cart or a stroller, which errs by
//! 24% to 94%. A stick is a hand fixed to an object. So the rate this
//! produces is a hypothesis under test, which is why it ships alongside the
//! three diagnostics that let a recorded game settle it - see GameModel's
//! stride fields - rather than as a number the app asserts.
class StrideMeter {

    //! Six seconds at the ~21.4 Hz the watch actually delivers. Three cycles
    //! of the slowest stride worth looking for, which is the least an
    //! autocorrelation can judge a period from.
    public static const WINDOW = 128;

    //! Lags 7 to 27 are 3.06 Hz down to 0.79 Hz. The published range for a
    //! full skating cycle is 0.9 to 2.1 Hz, and per-leg pushes are twice
    //! that; this band spans the cycle rate and the lower half of the push
    //! rate, which is as much as 21 Hz can resolve.
    private const MIN_LAG = 7;
    private const MAX_LAG = 27;

    //! Below this the window is not periodic enough to call a stride. Sized
    //! against synthetic pulse trains: coasting, standing, impacts, 25%
    //! period jitter and half the pushes missing are all refused by it.
    private const GATE = 0.45;

    //! An autocorrelation peaks at the period AND at every multiple of it, so
    //! the half-lag has to be preferred when it is nearly as strong, or the
    //! answer silently halves. This is the dominant error in the whole method
    //! and this constant is the only thing standing against it.
    private const OCTAVE = 0.80;

    //! How far the winning lag must stand above the average of the whole lag
    //! curve. A peak height on its own is not enough: a single stick impact
    //! in an otherwise quiet window produces a correlation of 0.91, which
    //! sails through the gate above and reports a stride that never happened.
    //! What separates them is shape. A real stride lifts one lag clear of a
    //! low surround; an impact lifts the whole curve.
    //!
    //! Measured on synthetic pulse trains: real strides score 0.76 to 1.09,
    //! including badly asymmetric and noisy ones, and impacts score 0.47.
    //! 0.60 sits in the middle of that gap. Taken against the mean of the
    //! curve rather than its median purely to avoid sorting twenty-one
    //! floats every second; the two separate equally well.
    private const PROMINENCE = 0.60;

    //! One-pole corners, as alphas. 0.65 is 3.96 Hz and 0.10 is 0.36 Hz, so
    //! the pair passes the stride band and rejects gravity, body sway and the
    //! sharp content of a stick impact.
    //!
    //! The cutoff of a one-pole EMA is fs*acos(1 - a*a/(2*(1-a)))/2pi, which
    //! is worth stating because guessing it is how this went wrong the first
    //! time: 0.45 looks like a reasonable "fast" alpha and is a 2.10 Hz low
    //! pass, sitting right on top of the signal it is meant to pass.
    private const A_FAST = 0.65;
    private const A_SLOW = 0.10;

    private var _ring as Array<Float> = [] as Array<Float>;
    private var _at as Number = 0;
    private var _filled as Boolean = false;
    private var _fast as Float = 0.0;
    private var _slow as Float = 0.0;
    private var _primed as Boolean = false;

    // Scratch, allocated once. Allocating 128-element arrays every second
    // would hand the garbage collector work during a game for no reason.
    private var _d as Array<Float> = [] as Array<Float>;
    private var _p as Array<Float> = [] as Array<Float>;
    private var _r as Array<Float> = [] as Array<Float>;

    //! Samples actually delivered per second, measured rather than assumed.
    //!
    //! The watch is asked for 25 Hz and a recorded game works out at about
    //! 21.4. The device says it can do 100, so the deficit is not a rate cap
    //! and its cause is not established - which is exactly why this is not a
    //! constant. A period in samples means nothing without the rate that
    //! produced it, and a hard-coded 25 would have reported every stride 17%
    //! fast.
    private var _hz as Float = 21.0;
    private var _sinceUpdate as Number = 0;

    //! Pushes per minute from the last accepted window, or 0 for "unknown".
    public var rate as Number = 0;
    //! Peak height times 100, the confidence that went with it.
    public var strength as Number = 0;
    //! The winning lag in samples, before interpolation. Diagnostic.
    public var lag as Number = 0;

    //! Strides counted, as a running total of rate-per-second over accepted
    //! seconds only. Every unaccepted second contributes nothing, so any
    //! distance built on this is short by whatever coverage misses - which is
    //! the single reason this app does not publish a distance unless the
    //! player has set a stride length themselves.
    public var strideCount as Float = 0.0;

    private var _acceptedSeconds as Number = 0;
    private var _judgedSeconds as Number = 0;
    private var _rateSum as Number = 0;

    public function initialize() {
        var i;
        for (i = 0; i < WINDOW; i++) {
            _ring.add(0.0);
            _d.add(0.0);
        }
        for (i = 0; i <= WINDOW; i++) {
            _p.add(0.0);
        }
        for (i = 0; i <= MAX_LAG + 1; i++) {
            _r.add(0.0);
        }
    }

    //! Feed one acceleration magnitude, in milli-g, straight from the sensor
    //! callback. Cheap on purpose: two multiplies and a store, because this
    //! runs twenty-one times a second inside a callback that already has a
    //! mean absolute deviation to compute.
    public function push(magnitude as Float) as Void {
        if (!_primed) {
            _fast = magnitude;
            _slow = magnitude;
            _primed = true;
        }
        _fast += (magnitude - _fast) * A_FAST;
        _slow += (magnitude - _slow) * A_SLOW;
        _ring[_at] = _fast - _slow;
        _sinceUpdate++;
        _at++;
        if (_at >= WINDOW) {
            _at = 0;
            _filled = true;
        }
    }

    //! Throw the window away. Used on resume, for the same reason the shift
    //! detector drops its pending samples: six seconds that straddle a pause
    //! describe neither the play before it nor the play after.
    public function reset() as Void {
        var i;
        for (i = 0; i < WINDOW; i++) {
            _ring[i] = 0.0;
        }
        _at = 0;
        _filled = false;
        _primed = false;
        _sinceUpdate = 0;
        rate = 0;
        strength = 0;
        lag = 0;
    }

    //! Session coverage: the share of judged seconds that produced a rate.
    //! This is the number that says whether the rate means anything, and no
    //! other hockey app reports it.
    public function coveragePercent() as Number {
        if (_judgedSeconds < 1) {
            return 0;
        }
        return (_acceptedSeconds * 100) / _judgedSeconds;
    }

    //! The seconds that actually produced a rate. This is the only honest
    //! denominator for a speed built out of strideCount: the numerator counts
    //! pushes over these seconds and no others, so dividing by total ice time
    //! would report a speed for seconds that were never measured.
    public function measuredSeconds() as Number {
        return _acceptedSeconds;
    }

    //! Mean of the accepted windows, in pushes per minute.
    public function averageRate() as Number {
        if (_acceptedSeconds < 1) {
            return 0;
        }
        return _rateSum / _acceptedSeconds;
    }

    //! Judge the current window. Call once a second, and only while the
    //! player is on the ice and moving - the shift detector's own state is a
    //! free pre-gate that removes every bench and standing second before any
    //! of this arithmetic runs.
    public function update(active as Boolean) as Void {
        rate = 0;
        strength = 0;
        lag = 0;
        if (!active || !_filled) {
            // Not a judged second. Coverage is a share of the seconds this
            // was actually asked about, so counting bench seconds in the
            // denominator would make it a measure of bench time.
            _sinceUpdate = 0;
            return;
        }
        _judgedSeconds++;

        // Fold this second's delivery into the rate estimate before using it.
        if (_sinceUpdate > 0) {
            _hz += (_sinceUpdate.toFloat() - _hz) * 0.05;
        }
        _sinceUpdate = 0;

        var n = WINDOW;
        var i;
        var sum = 0.0;
        // Unwrap the ring into _d, oldest first, and take the mean out: an
        // autocorrelation of a signal with a DC offset finds the offset.
        for (i = 0; i < n; i++) {
            var v = _ring[(_at + i) % n];
            _d[i] = v;
            sum += v;
        }
        var mean = sum / n;
        for (i = 0; i < n; i++) {
            _d[i] = _d[i] - mean;
        }

        // Prefix sums of squares, so each lag's normalisation is a lookup
        // rather than its own pass. Without this the cost triples, and the
        // watchdog on this device is a bytecode budget of 240,000 per call.
        _p[0] = 0.0;
        for (i = 0; i < n; i++) {
            _p[i + 1] = _p[i] + (_d[i] * _d[i]);
        }
        if (_p[n] <= 0.0) {
            return;
        }

        var bestLag = 0;
        var bestR = 0.0;
        var rSum = 0.0;
        var rCount = 0;
        var L;
        for (L = MIN_LAG; L <= MAX_LAG; L++) {
            var m = n - L;
            var num = 0.0;
            for (i = 0; i < m; i++) {
                num += _d[i] * _d[i + L];
            }
            var denom = _p[m] * (_p[L + m] - _p[L]);
            var r = 0.0;
            if (denom > 0.0) {
                r = (num / Math.sqrt(denom)).toFloat();
            }
            _r[L] = r;
            rSum += r;
            rCount++;
            if (r > bestR) {
                bestR = r;
                bestLag = L;
            }
        }

        if (bestLag < MIN_LAG || bestR < GATE) {
            return;
        }
        if (rCount > 0 && (bestR - (rSum / rCount)) < PROMINENCE) {
            return;
        }

        // Prefer the faster octave when it is nearly as strong. A pulse train
        // correlates with itself at twice its period just as well as at its
        // period, and taking the longer lag reports half the real rate.
        var half = bestLag / 2;
        if (half >= MIN_LAG && _r[half] >= (bestR * OCTAVE)) {
            bestLag = half;
            bestR = _r[half];
        }

        // Parabolic interpolation across the peak, which recovers most of the
        // resolution the integer lag grid costs at the fast end of the band.
        var refined = bestLag.toFloat();
        if (bestLag > MIN_LAG && bestLag < MAX_LAG) {
            var y0 = _r[bestLag - 1];
            var y1 = _r[bestLag];
            var y2 = _r[bestLag + 1];
            var below = (y0 - (2.0 * y1)) + y2;
            if (below != 0.0) {
                var shift = (0.5 * (y0 - y2)) / below;
                if (shift > -1.0 && shift < 1.0) {
                    refined = bestLag + shift;
                }
            }
        }
        if (refined <= 0.0) {
            return;
        }

        var hz = _hz / refined;
        rate = (hz * 60.0).toNumber();
        strength = (bestR * 100.0).toNumber();
        lag = bestLag;
        _acceptedSeconds++;
        _rateSum += rate;
        strideCount += hz;
    }
}

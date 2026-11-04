//
// The one screen the player sees during a game.
//
// Everything is on a single page on purpose: the watch is under a glove and
// behind a jersey sleeve, and there is no realistic way to change pages while
// skating. What is on screen is chosen so it can be read in the half second
// available while looking down between strides.
//
// Round screens are the hard case. The usable width at any given height is the
// chord of the circle at that height, not the width of the display, so text
// placed near the top or the bottom has far less room than it looks like it
// has. Every line here is measured against its own chord and shrunk to fit.
//

import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

class GameView extends WatchUi.View {

    // Vertical anchors, as a fraction of screen height.
    private const Y_HEADER = 0.150;
    private const Y_CLOCK  = 0.400;
    private const Y_SHIFT  = 0.645;
    private const Y_FOOT   = 0.830;

    // How much of the available chord a line may occupy.
    private const WIDTH_MARGIN = 0.94;

    private var _model as GameModel;
    private var _timer as Timer.Timer?;
    private var _isRound as Boolean = true;

    // Strings that never change, loaded once. Loading a resource is expensive
    // and this view redraws every second for an hour and a half.
    private var _txtReady as String = "READY";
    private var _txtPaused as String = "PAUSED";
    private var _txtBreak as String = "BREAK";
    private var _txtFinal as String = "FINAL";
    private var _txtOnIce as String = "ON";
    private var _txtBench as String = "BENCH";
    private var _txtShifts as String = "Shifts";
    private var _txtIce as String = "Ice";
    private var _txtAvg as String = "Avg Shift";
    private var _txtIceHr as String = "On-Ice HR";
    private var _txtWorkRest as String = "Work:Rest";
    private var _txtMotion as String = "MOTION";
    private var _txtNoSensor as String = "NO MOTION DATA";
    private var _txtOvertime as String = "OT";
    private var _txtPressAgain as String = "PRESS AGAIN";

    //! Constructor.
    public function initialize(model as GameModel) {
        View.initialize();
        _model = model;
    }

    //! Cache everything that does not change, once.
    public function onLayout(dc as Graphics.Dc) as Void {
        var settings = System.getDeviceSettings();
        _isRound = (settings.screenShape == System.SCREEN_SHAPE_ROUND);

        _txtReady = WatchUi.loadResource($.Rez.Strings.LabelReady) as String;
        _txtPaused = WatchUi.loadResource($.Rez.Strings.LabelPaused) as String;
        _txtBreak = WatchUi.loadResource($.Rez.Strings.LabelBreak) as String;
        _txtFinal = WatchUi.loadResource($.Rez.Strings.LabelFinal) as String;
        _txtOnIce = WatchUi.loadResource($.Rez.Strings.LabelOnIce) as String;
        _txtBench = WatchUi.loadResource($.Rez.Strings.LabelBench) as String;
        _txtShifts = WatchUi.loadResource($.Rez.Strings.SummaryShifts) as String;
        _txtIce = WatchUi.loadResource($.Rez.Strings.SummaryIce) as String;
        _txtAvg = WatchUi.loadResource($.Rez.Strings.SummaryAvgShift) as String;
        _txtIceHr = WatchUi.loadResource($.Rez.Strings.SummaryIceHr) as String;
        _txtWorkRest = WatchUi.loadResource($.Rez.Strings.SummaryWorkRest) as String;
        _txtMotion = WatchUi.loadResource($.Rez.Strings.LabelMotion) as String;
        _txtNoSensor = WatchUi.loadResource($.Rez.Strings.LabelNoSensor) as String;
        _txtOvertime = WatchUi.loadResource($.Rez.Strings.LabelOvertime) as String;
        _txtPressAgain = WatchUi.loadResource($.Rez.Strings.LabelPressAgain) as String;
    }

    //! Start the once-a-second redraw.
    public function onShow() as Void {
        if (_timer == null) {
            _timer = new Timer.Timer();
        }
        (_timer as Timer.Timer).start(method(:onTick), 1000, true);
    }

    //! Stop redrawing while the view is off screen. The game clock itself is
    //! driven from the app, not from here, so it keeps running regardless.
    public function onHide() as Void {
        var timer = _timer;
        if (timer != null) {
            timer.stop();
        }
    }

    //! Once a second: ask for a redraw.
    public function onTick() as Void {
        WatchUi.requestUpdate();
    }

    // ------------------------------------------------------------------
    // Drawing
    // ------------------------------------------------------------------

    //! Draw the whole screen.
    public function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        if (_model.state == STATE_FINISHED) {
            drawSummary(dc, w, h);
            return;
        }

        drawPeriodArc(dc, w, h);
        drawHeader(dc, w, h);
        drawClock(dc, w, h);
        drawSegment(dc, w, h);
        drawFooter(dc, w, h);
    }

    //! Period number, and the state when it is not simply running.
    private function drawHeader(dc as Graphics.Dc, w as Number, h as Number) as Void {
        // A pause waiting for its second press is the most important thing on
        // the screen: the player needs to know the watch heard the press, and
        // that it has not paused yet.
        if (_model.isPauseArmed()) {
            drawFitted(dc, _txtPressAgain, Y_HEADER, w, h, Graphics.COLOR_YELLOW,
                [Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY,
                 Graphics.FONT_XTINY]);
            return;
        }

        var text = "P" + _model.period + "/" + _model.periodCount;
        var colour = Graphics.COLOR_LT_GRAY;

        if (_model.inOvertime()) {
            // Regulation is over and the game is not. Say so, rather than
            // showing "P3/3" next to a clock that no longer means that.
            text = _txtOvertime;
            colour = Graphics.COLOR_ORANGE;
        } else if (_model.state == STATE_READY) {
            text = text + " " + _txtReady;
        } else if (_model.state == STATE_PAUSED) {
            text = text + " " + _txtPaused;
            colour = Graphics.COLOR_YELLOW;
        } else if (_model.state == STATE_BREAK) {
            text = _txtBreak;
            colour = Graphics.COLOR_YELLOW;
        } else {
            colour = Graphics.COLOR_BLUE;
        }

        if (_model.inOvertime() && _model.state == STATE_PAUSED) {
            text = _txtOvertime + " " + _txtPaused;
            colour = Graphics.COLOR_YELLOW;
        }

        drawFitted(dc, text, Y_HEADER, w, h, colour,
            [Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY]);
    }

    //! The big clock: time left in the period, or left in the intermission.
    private function drawClock(dc as Graphics.Dc, w as Number, h as Number) as Void {
        var text = Fmt.clock(_model.clockMs());
        var colour = Graphics.COLOR_WHITE;
        if (_model.state == STATE_BREAK) {
            colour = Graphics.COLOR_YELLOW;
        } else if (_model.inOvertime()) {
            // Counting up from the end of regulation, not down to it.
            colour = Graphics.COLOR_ORANGE;
        }
        drawFitted(dc, text, Y_CLOCK, w, h, colour,
            [Graphics.FONT_NUMBER_HOT, Graphics.FONT_NUMBER_MEDIUM,
             Graphics.FONT_NUMBER_MILD, Graphics.FONT_LARGE, Graphics.FONT_MEDIUM]);
    }

    //! On the ice, or on the bench, and for how long.
    //!
    //! The colour carries the message: green while the shift is within target,
    //! amber once it is over, red once it is well over. Blue means the bench,
    //! which is deliberately a different hue family so there is no chance of
    //! mistaking a long rest for a long shift at a glance.
    private function drawSegment(dc as Graphics.Dc, w as Number, h as Number) as Void {
        if (_model.state == STATE_READY) {
            // Before the game this line is a live sensor check rather than a
            // placeholder: the number tracks wrist movement, so a few seconds
            // of waving confirms the one thing that silently breaks.
            var detector = _model.detector;
            var text = _txtMotion + " " + detector.motion;
            var colour = Graphics.COLOR_LT_GRAY;
            if (!detector.hasMotionSensor) {
                text = _txtNoSensor;
                colour = Graphics.COLOR_RED;
            } else if (detector.motion >= detector.threshold) {
                colour = Graphics.COLOR_GREEN;
            }
            drawFitted(dc, text, Y_SHIFT, w, h, colour,
                [Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY]);
            return;
        }

        var elapsed = _model.segmentMs();
        var label = _model.onIce() ? _txtOnIce : _txtBench;
        var colour = Graphics.COLOR_BLUE;

        if (_model.onIce()) {
            var target = _model.shiftTargetMs;
            if (elapsed >= (target * 13) / 10) {
                colour = Graphics.COLOR_RED;
            } else if (elapsed >= target) {
                colour = Graphics.COLOR_ORANGE;
            } else {
                colour = Graphics.COLOR_GREEN;
            }
        }

        drawFitted(dc, label + " " + Fmt.clock(elapsed), Y_SHIFT, w, h, colour,
            [Graphics.FONT_LARGE, Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY]);
    }

    //! Heart rate and shift count, the two numbers worth a glance mid-game.
    private function drawFooter(dc as Graphics.Dc, w as Number, h as Number) as Void {
        if (_model.state == STATE_RUNNING && !_model.detector.isHealthy()) {
            drawFitted(dc, _txtNoSensor, Y_FOOT, w, h, Graphics.COLOR_RED,
                [Graphics.FONT_TINY, Graphics.FONT_XTINY]);
            return;
        }

        var heartRate = _model.currentHeartRate();
        var hrText = (heartRate == null || heartRate <= 0) ? "--" : heartRate.toString();
        var text = hrText + " bpm   " + _model.shiftCount + " sh";

        drawFitted(dc, text, Y_FOOT, w, h, Graphics.COLOR_LT_GRAY,
            [Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY]);
    }

    //! A ring around the edge showing how much of the period is gone.
    private function drawPeriodArc(dc as Graphics.Dc, w as Number, h as Number) as Void {
        if (!_isRound || _model.state == STATE_READY) {
            return;
        }

        var total = (_model.state == STATE_BREAK) ? _model.breakMs : _model.periodMs;
        if (total <= 0) {
            return;
        }
        var done = (_model.state == STATE_BREAK)
            ? (_model.breakMs - _model.breakRemainingMs())
            : _model.periodElapsedMs();

        var fraction = done.toFloat() / total.toFloat();
        if (fraction < 0.0) { fraction = 0.0; }
        if (fraction > 1.0) { fraction = 1.0; }
        if (_model.inOvertime()) {
            fraction = 1.0;     // Regulation is spent; the ring stays closed.
        }

        var centreX = w / 2;
        var centreY = h / 2;
        var radius = ((w < h ? w : h) / 2) - 3;

        dc.setPenWidth(5);
        dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(centreX, centreY, radius);

        if (fraction <= 0.0) {
            return;
        }

        var sweep = 360.0 * fraction;
        var end = 90.0 - sweep;
        var arcColour = Graphics.COLOR_BLUE;
        if (_model.state == STATE_BREAK) {
            arcColour = Graphics.COLOR_YELLOW;
        } else if (_model.inOvertime()) {
            arcColour = Graphics.COLOR_ORANGE;
        }
        dc.setColor(arcColour, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(centreX, centreY, radius, Graphics.ARC_CLOCKWISE, 90, end.toNumber());
        dc.setPenWidth(1);
    }

    //! The post-game card, drawn in place rather than as a separate view so
    //! that nothing has to be pushed from inside a confirmation callback.
    private function drawSummary(dc as Graphics.Dc, w as Number, h as Number) as Void {
        drawFitted(dc, _txtFinal, 0.115, w, h, Graphics.COLOR_LT_GRAY,
            [Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY]);

        var rows = [
            [_txtShifts, _model.shiftCount.toString()],
            [_txtIce, Fmt.clock(_model.iceTimeMs())],
            [_txtAvg, Fmt.clock(_model.averageShiftMs())],
            [_txtWorkRest, workRestText()],
            [_txtIceHr, hrText()]
        ];

        var top = 0.270;
        var step = 0.128;
        for (var i = 0; i < rows.size(); i++) {
            var row = rows[i] as Array<String>;
            drawFitted(dc, row[0] + "  " + row[1], top + (step * i), w, h,
                Graphics.COLOR_WHITE,
                [Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY]);
        }
    }

    //! Rest per unit of work, as "1:2.4".
    private function workRestText() as String {
        var ratio = _model.workRestX100();
        if (ratio <= 0) {
            return "--";
        }
        var whole = ratio / 100;
        var tenths = (ratio % 100) / 10;
        return "1:" + whole + "." + tenths;
    }

    //! On-ice average heart rate next to the whole-game average, because the
    //! gap between the two is the point: a game average is diluted by every
    //! minute spent on the bench.
    private function hrText() as String {
        var ice = _model.iceAverageHr();
        if (ice <= 0) {
            return "--";
        }
        if (_model.finalAvgHr > 0) {
            return ice + " / " + _model.finalAvgHr;
        }
        return ice.toString();
    }

    // ------------------------------------------------------------------
    // Text fitting
    // ------------------------------------------------------------------

    //! Draw one centred line at the largest font that actually fits.
    private function drawFitted(dc as Graphics.Dc, text as String, yFraction as Float,
                                w as Number, h as Number, colour as Number,
                                candidates as Array<Graphics.FontDefinition>) as Void {
        var centreY = (h * yFraction).toNumber();
        var font = fittingFont(dc, text, centreY, w, h, candidates);
        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, centreY, font, text, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! The largest candidate font whose rendering of this text fits the width
    //! available at this height. Falls back to the smallest candidate.
    private function fittingFont(dc as Graphics.Dc, text as String, centreY as Number,
                                 w as Number, h as Number,
                                 candidates as Array<Graphics.FontDefinition>) as Graphics.FontDefinition {
        for (var i = 0; i < candidates.size(); i++) {
            var font = candidates[i];
            var height = dc.getFontHeight(font);
            var available = usableWidth(centreY, height, w, h);
            if (available > 0 && dc.getTextWidthInPixels(text, font) <= available) {
                return font;
            }
        }
        return candidates[candidates.size() - 1];
    }

    //! How wide a line may be at a given height.
    //!
    //! On a round screen the display is a circle, so the room available at a
    //! given height is the chord at that height, which narrows sharply towards
    //! the top and bottom. Measuring against the full screen width is what
    //! makes text run off the edge of a round watch.
    private function usableWidth(centreY as Number, textHeight as Number,
                                 w as Number, h as Number) as Number {
        if (!_isRound) {
            return (w * WIDTH_MARGIN).toNumber();
        }
        var radius = (w < h ? w : h) / 2.0;
        var dy = (centreY - (h / 2.0)).abs() + (textHeight / 2.0);
        if (dy >= radius) {
            return 0;
        }
        var halfChord = Math.sqrt((radius * radius) - (dy * dy));
        return (halfChord * 2.0 * WIDTH_MARGIN).toNumber();
    }
}

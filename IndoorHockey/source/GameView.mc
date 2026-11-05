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
    // and this view redraws every second for as long as the game runs, which
    // now has no upper bound.
    private var _txtReady as String = "READY";
    private var _txtPaused as String = "PAUSED";
    private var _txtFinal as String = "FINAL";
    private var _txtOnIce as String = "ON";
    private var _txtBench as String = "BENCH";
    private var _txtGame as String = "Game";
    private var _txtShifts as String = "Shifts";
    private var _txtIce as String = "Ice";
    private var _txtAvg as String = "Avg Shift";
    private var _txtIceHr as String = "On-Ice HR";
    private var _txtWorkRest as String = "Work:Rest";
    private var _txtMotion as String = "MOTION";
    private var _txtNoSensor as String = "NO MOTION DATA";
    private var _txtPressAgain as String = "PRESS AGAIN";
    private var _txtEndingGame as String = "ENDING GAME";

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
        _txtFinal = WatchUi.loadResource($.Rez.Strings.LabelFinal) as String;
        _txtOnIce = WatchUi.loadResource($.Rez.Strings.LabelOnIce) as String;
        _txtBench = WatchUi.loadResource($.Rez.Strings.LabelBench) as String;
        _txtGame = WatchUi.loadResource($.Rez.Strings.SummaryGame) as String;
        _txtShifts = WatchUi.loadResource($.Rez.Strings.SummaryShifts) as String;
        _txtIce = WatchUi.loadResource($.Rez.Strings.SummaryIce) as String;
        _txtAvg = WatchUi.loadResource($.Rez.Strings.SummaryAvgShift) as String;
        _txtIceHr = WatchUi.loadResource($.Rez.Strings.SummaryIceHr) as String;
        _txtWorkRest = WatchUi.loadResource($.Rez.Strings.SummaryWorkRest) as String;
        _txtMotion = WatchUi.loadResource($.Rez.Strings.LabelMotion) as String;
        _txtNoSensor = WatchUi.loadResource($.Rez.Strings.LabelNoSensor) as String;
        _txtPressAgain = WatchUi.loadResource($.Rez.Strings.LabelPressAgain) as String;
        _txtEndingGame = WatchUi.loadResource($.Rez.Strings.LabelEndingGame) as String;
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

        drawShiftRing(dc, w, h);
        drawHeader(dc, w, h);
        drawClock(dc, w, h);
        drawSegment(dc, w, h);
        drawFooter(dc, w, h);
    }

    //! Total ice time, and the state when it is not simply running.
    //!
    //! This slot used to hold the period number. With no periods there is a
    //! better use for it: total time on the ice, which is the number this whole
    //! app exists to produce and which otherwise only appeared on the summary
    //! after the game. Paired with the segment line below it the screen now
    //! reads "this shift, and the game so far".
    private function drawHeader(dc as Graphics.Dc, w as Number, h as Number) as Void {
        // Outranks everything else here: it is the only message on this screen
        // that says the watch is about to act without being asked. Red,
        // because yellow is already the colour of "waiting for you".
        if (_model.isEndArmed()) {
            // With the countdown, because a message that something will happen
            // by itself is only useful if it says how long there is to stop it.
            // Built every second, as the running header already is.
            var left = (_model.endArmRemainingMs() + 999) / 1000;
            drawFitted(dc, _txtEndingGame + " " + left.toString(),
                Y_HEADER, w, h, Graphics.COLOR_RED,
                [Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY,
                 Graphics.FONT_XTINY]);
            return;
        }

        // A pause waiting for its second press: the player needs to know the
        // watch heard the press, and that it has not paused yet.
        if (_model.isPauseArmed()) {
            drawFitted(dc, _txtPressAgain, Y_HEADER, w, h, Graphics.COLOR_YELLOW,
                [Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY,
                 Graphics.FONT_XTINY]);
            return;
        }

        var text = "";
        var colour = Graphics.COLOR_LT_GRAY;

        if (_model.state == STATE_READY) {
            text = _txtReady;
        } else if (_model.state == STATE_PAUSED) {
            text = _txtPaused;
            colour = Graphics.COLOR_YELLOW;
        } else {
            // Built only here: the other states replace it, and formatting a
            // clock every second to throw it away is the cost this file's
            // string caching exists to avoid.
            text = _txtIce + " " + Fmt.clock(_model.iceTimeMs());
            colour = Graphics.COLOR_BLUE;
        }

        drawFitted(dc, text, Y_HEADER, w, h, colour,
            [Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY]);
    }

    //! The big clock: how long the game has been running, counting up.
    private function drawClock(dc as Graphics.Dc, w as Number, h as Number) as Void {
        var text = Fmt.clock(_model.clockMs());
        var colour = (_model.state == STATE_PAUSED)
            ? Graphics.COLOR_YELLOW : Graphics.COLOR_WHITE;
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
            colour = shiftColour(elapsed, _model.shiftTargetMs);
        }

        drawFitted(dc, label + " " + Fmt.clock(elapsed), Y_SHIFT, w, h, colour,
            [Graphics.FONT_LARGE, Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY]);
    }

    // Ring stroke widths: the normal one, and the heavier one used past the
    // shift target so that being over is visible without relying on colour.
    private const PEN_RING = 5;
    private const PEN_OVER = 11;

    //! How a shift of this length against this target should be coloured.
    //!
    //! Read by both the shift line and the ring around it. They used to carry
    //! their own copies of the thresholds and the copies had drifted apart -
    //! the ring turned red at twice the target while the number turned red at
    //! 1.3x, so a 90-second shift against a 60-second target showed a red
    //! number inside an orange ring. One function, one answer.
    private function shiftColour(elapsed as Number, target as Number) as Graphics.ColorValue {
        if (target <= 0) {
            return Graphics.COLOR_GREEN;
        }
        if (elapsed >= (target * 13) / 10) {
            return Graphics.COLOR_RED;
        }
        if (elapsed >= target) {
            return Graphics.COLOR_ORANGE;
        }
        return Graphics.COLOR_GREEN;
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

    //! A ring around the edge showing the shift in progress against the target.
    //!
    //! This used to show how much of the period was gone. With no periods it
    //! shows the thing that actually wants watching from across the ice: how
    //! long the current shift has run against the shift target. It fills as the
    //! shift goes on and changes colour with it, so the ring says "get off" at
    //! a glance, without reading a number.
    //!
    //! On the bench it is left as a bare track. A bench spell has no target to
    //! fill against, and inventing one would make the ring mean two different
    //! things depending on a state the player cannot see from the ring itself.
    private function drawShiftRing(dc as Graphics.Dc, w as Number, h as Number) as Void {
        if (!_isRound || _model.state == STATE_READY) {
            return;
        }

        var centreX = w / 2;
        var centreY = h / 2;
        // Leave room for the widest pen used below, measured from the centre of
        // the stroke, so the outer edge stays inside the glass on a display
        // that crops its outermost row.
        var radius = ((w < h ? w : h) / 2) - (PEN_OVER / 2) - 2;

        // The empty track. Brighter than it was: at 0x555555 this was a 2.9:1
        // stroke at the very edge of the screen, which through rink glare at
        // arm's length read as no ring at all - the same as the bench.
        dc.setPenWidth(PEN_RING);
        dc.setColor(0x999999, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(centreX, centreY, radius);

        var target = _model.shiftTargetMs;
        var elapsed = _model.segmentMs();
        if (!_model.onIce() || target <= 0 || elapsed <= 0) {
            dc.setPenWidth(1);
            return;
        }

        dc.setColor(shiftColour(elapsed, target), Graphics.COLOR_TRANSPARENT);

        if (elapsed >= target) {
            // Past the target the ring is full, so it cannot grow any further
            // and colour alone would carry the whole "get off" signal - no use
            // to a red-green colour-blind player. A thicker stroke says it
            // again without relying on hue.
            //
            // Drawn as a circle rather than a 360-degree arc deliberately: a
            // full turn asks drawArc for an arc whose start equals its end, and
            // what it does with that is undocumented. A circle is the same
            // shape with defined behaviour.
            dc.setPenWidth(PEN_OVER);
            dc.drawCircle(centreX, centreY, radius);
            dc.setPenWidth(1);
            return;
        }

        var sweep = 360.0 * (elapsed.toFloat() / target.toFloat());
        dc.drawArc(centreX, centreY, radius, Graphics.ARC_CLOCKWISE, 90, 90.0 - sweep);
        dc.setPenWidth(1);
    }

    //! The post-game card, drawn in place rather than as a separate view so
    //! that nothing has to be pushed from inside a confirmation callback.
    private function drawSummary(dc as Graphics.Dc, w as Number, h as Number) as Void {
        drawFitted(dc, _txtFinal, 0.115, w, h, Graphics.COLOR_LT_GRAY,
            [Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY]);

        var rows = [
            [_txtGame, Fmt.clock(_model.totalPlayedMs())],
            [_txtShifts, _model.shiftCount.toString()],
            [_txtIce, Fmt.clock(_model.iceTimeMs())],
            [_txtAvg, Fmt.clock(_model.averageShiftMs())],
            [_txtWorkRest, workRestText()],
            [_txtIceHr, hrText()]
        ];

        // Six rows rather than five, so the spacing is tighter than it was.
        var top = 0.255;
        var step = 0.112;
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

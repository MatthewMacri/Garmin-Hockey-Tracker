//
// The one screen you look at during a game.
//
// Nothing here is measured in fixed pixels: every position is a fraction of the
// screen and every font is the largest one that still fits. That is what makes
// the same code look right on a 208 px Instinct and a 454 px fenix.
//
// "Fits" has to account for the screen being round. The usable width near the
// top and bottom of a circular display is a chord, not the diameter, so a line
// measured against the full width will run off the edge.
//

import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

//! Regions of the screen that respond to a tap.
enum TouchZone {
    ZONE_CLOCK = 0,
    ZONE_SHIFT = 1,
    ZONE_STATS = 2
}

class GameView extends WatchUi.View {

    // Vertical anchors, as a fraction of screen height.
    private const Y_HEADER = 0.150;
    private const Y_CLOCK  = 0.400;
    private const Y_SHIFT  = 0.645;
    private const Y_STATS  = 0.830;

    // Tap boundaries, same units.
    private const TAP_SHIFT_TOP = 0.520;
    private const TAP_STATS_TOP = 0.755;

    // Fraction of the available width a line is allowed to occupy.
    private const WIDTH_MARGIN = 0.94;

    private var _model as GameModel;
    private var _timer as Timer.Timer? = null;
    private var _isRound as Boolean = false;

    //! Constructor.
    //! @param model The game to display
    public function initialize(model as GameModel) {
        View.initialize();
        _model = model;
    }

    //! Work out once what kind of screen this is.
    public function onLayout(dc as Dc) as Void {
        var settings = System.getDeviceSettings();
        _isRound = (settings.screenShape == System.SCREEN_SHAPE_ROUND);
    }

    //! Start the once-a-second refresh.
    public function onShow() as Void {
        if (_timer == null) {
            var timer = new Timer.Timer();
            timer.start(method(:onTick), 1000, true);
            _timer = timer;
        }
    }

    //! Stop refreshing while a menu or dialog is on top.
    public function onHide() as Void {
        var timer = _timer;
        if (timer != null) {
            timer.stop();
            _timer = null;
        }
    }

    //! Drive the model's clock checks, then redraw.
    public function onTick() as Void {
        _model.onTick();
        WatchUi.requestUpdate();
    }

    //! Which tappable region a y coordinate falls in.
    //! @param y Screen y of the tap
    //! @param height Screen height
    //! @return The zone that was tapped
    public function zoneAt(y as Number, height as Number) as TouchZone {
        if (y >= (height * TAP_STATS_TOP)) {
            return ZONE_STATS;
        }
        if (y >= (height * TAP_SHIFT_TOP)) {
            return ZONE_SHIFT;
        }
        return ZONE_CLOCK;
    }

    //! Draw the game.
    public function onUpdate(dc as Dc) as Void {
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
        drawShift(dc, w, h);
        drawStats(dc, w, h);
    }

    //! A ring around the edge showing how much of the period is gone.
    private function drawPeriodArc(dc as Dc, w as Number, h as Number) as Void {
        if (!_isRound || !(dc has :drawArc)) {
            return;
        }

        var pen = w / 40;
        if (pen < 3) {
            pen = 3;
        }
        var radius = (w < h ? w : h) / 2 - pen - 2;
        var cx = w / 2;
        var cy = h / 2;

        dc.setPenWidth(pen);
        dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, 0, 360);

        var periodMs = _model.periodMs;
        if (periodMs > 0) {
            var fraction = _model.periodElapsedMs().toFloat() / periodMs.toFloat();
            if (fraction > 0.0) {
                if (fraction > 1.0) {
                    fraction = 1.0;
                }
                // Angles run counter-clockwise from 3 o'clock, so sweeping
                // clockwise from 12 o'clock means counting down from 90.
                var endAngle = 90.0 - (360.0 * fraction);
                if (endAngle <= -270.0) {
                    endAngle = -269.9;
                }
                dc.setColor(stateColor(), Graphics.COLOR_TRANSPARENT);
                dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, 90, endAngle.toNumber());
            }
        }

        dc.setPenWidth(1);
    }

    //! Period number, plus either heart rate or what the game is waiting for.
    private function drawHeader(dc as Dc, w as Number, h as Number) as Void {
        var text = "P" + _model.period.toString() + "/" + _model.periodCount.toString();
        var state = _model.state;

        if (state == STATE_RUNNING) {
            var hr = _model.currentHeartRate();
            if (hr != null && hr > 0) {
                text = text + "  " + hr.toString();
            }
        } else {
            text = text + "  " + stateLabel();
        }

        var y = (h * Y_HEADER).toNumber();
        var font = fittingFont(dc, text, y, w, h,
            [Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY] as Array<FontDefinition>);

        dc.setColor(stateColor(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, y, font, text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! The big period clock.
    private function drawClock(dc as Dc, w as Number, h as Number) as Void {
        var text = Fmt.clock(_model.clockMs());
        var y = (h * Y_CLOCK).toNumber();
        var font = fittingFont(dc, text, y, w, h,
            [Graphics.FONT_NUMBER_HOT, Graphics.FONT_NUMBER_MEDIUM, Graphics.FONT_NUMBER_MILD,
             Graphics.FONT_LARGE, Graphics.FONT_MEDIUM] as Array<FontDefinition>);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, y, font, text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Shift timer, coloured by how long this shift has run.
    private function drawShift(dc as Dc, w as Number, h as Number) as Void {
        var label = WatchUi.loadResource($.Rez.Strings.LabelShift) as String;
        var text;
        var color;

        if (_model.state == STATE_READY) {
            text = label + " --:--";
            color = Graphics.COLOR_DK_GRAY;
        } else {
            var shiftMs = _model.shiftMs();
            text = label + " " + Fmt.clock(shiftMs);
            color = shiftColor(shiftMs);
        }

        var y = (h * Y_SHIFT).toNumber();
        var font = fittingFont(dc, text, y, w, h,
            [Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY] as Array<FontDefinition>);

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, y, font, text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Goals, assists, shots, saves on one line.
    private function drawStats(dc as Dc, w as Number, h as Number) as Void {
        var text = Lang.format("$1$ $2$  $3$ $4$  $5$ $6$  $7$ $8$", [
            WatchUi.loadResource($.Rez.Strings.LabelGoals) as String, _model.goals,
            WatchUi.loadResource($.Rez.Strings.LabelAssists) as String, _model.assists,
            WatchUi.loadResource($.Rez.Strings.LabelShots) as String, _model.shots,
            WatchUi.loadResource($.Rez.Strings.LabelSaves) as String, _model.saves
        ]);

        var y = (h * Y_STATS).toNumber();
        var font = fittingFont(dc, text, y, w, h,
            [Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY] as Array<FontDefinition>);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, y, font, text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! The post-game card. Shown in place of the live screen once the
    //! activity has been saved, so there is no second view to push.
    private function drawSummary(dc as Dc, w as Number, h as Number) as Void {
        var hrText = "--";
        if (_model.finalAvgHr > 0 || _model.finalMaxHr > 0) {
            hrText = _model.finalAvgHr.toString() + " / " + _model.finalMaxHr.toString();
        }

        var lines = [
            WatchUi.loadResource($.Rez.Strings.LabelFinal) as String,
            (WatchUi.loadResource($.Rez.Strings.SummaryPlayed) as String) + " " + Fmt.clock(_model.totalPlayedMs()),
            Lang.format("$1$ $2$  $3$ $4$  $5$ $6$  $7$ $8$", [
                WatchUi.loadResource($.Rez.Strings.LabelGoals) as String, _model.goals,
                WatchUi.loadResource($.Rez.Strings.LabelAssists) as String, _model.assists,
                WatchUi.loadResource($.Rez.Strings.LabelShots) as String, _model.shots,
                WatchUi.loadResource($.Rez.Strings.LabelSaves) as String, _model.saves
            ]),
            Lang.format("$1$ $2$  $3$ $4$", [
                WatchUi.loadResource($.Rez.Strings.SummaryShifts) as String, _model.shiftCount,
                WatchUi.loadResource($.Rez.Strings.SummaryAvgShift) as String, Fmt.clock(_model.averageShiftMs())
            ]),
            (WatchUi.loadResource($.Rez.Strings.LabelHr) as String) + " " + hrText,
            (WatchUi.loadResource($.Rez.Strings.SummaryCalories) as String) + " " + _model.finalCalories.toString()
        ] as Array<String>;

        // Spread the rows evenly down the usable middle of the screen.
        var top = 0.17;
        var step = 0.66 / (lines.size() - 1).toFloat();

        for (var i = 0; i < lines.size(); i++) {
            var text = lines[i];
            var y = (h * (top + step * i)).toNumber();
            var font = fittingFont(dc, text, y, w, h,
                [Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY] as Array<FontDefinition>);
            dc.setColor(i == 0 ? Graphics.COLOR_RED : Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, y, font, text,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    //! Largest font from the list whose rendering fits the screen at this height.
    private function fittingFont(dc as Dc, text as String, centerY as Number,
                                 w as Number, h as Number,
                                 candidates as Array<FontDefinition>) as FontDefinition {
        for (var i = 0; i < candidates.size(); i++) {
            var font = candidates[i];
            var allowed = usableWidth(centerY, dc.getFontHeight(font), w, h);
            if (dc.getTextWidthInPixels(text, font) <= allowed) {
                return font;
            }
        }
        return candidates[candidates.size() - 1];
    }

    //! How wide a line of this height may be when centred at this y.
    private function usableWidth(centerY as Number, textHeight as Number,
                                 w as Number, h as Number) as Number {
        if (!_isRound) {
            return (w * WIDTH_MARGIN).toNumber();
        }

        var radius = (w < h ? w : h) / 2.0;
        // Measure at whichever edge of the text sits furthest from the centre:
        // that is where the circle is narrowest and where text would spill out.
        var dy = (centerY - (h / 2.0)).abs() + (textHeight / 2.0);
        if (dy >= radius) {
            return 0;
        }

        var halfChord = Math.sqrt((radius * radius) - (dy * dy));
        return (halfChord * 2.0 * WIDTH_MARGIN).toNumber();
    }

    //! Green while the shift is short, amber as it nears the target, red past it.
    private function shiftColor(shiftMs as Number) as Number {
        var target = _model.shiftTargetMs;
        if (target <= 0) {
            return Graphics.COLOR_GREEN;
        }
        var ratio = shiftMs.toFloat() / target.toFloat();
        if (ratio >= 1.0) {
            return Graphics.COLOR_RED;
        }
        if (ratio >= 0.8) {
            return Graphics.COLOR_YELLOW;
        }
        return Graphics.COLOR_GREEN;
    }

    //! Colour that matches the current game state.
    private function stateColor() as Number {
        var state = _model.state;
        if (state == STATE_RUNNING) {
            return Graphics.COLOR_BLUE;
        }
        if (state == STATE_PAUSED) {
            return Graphics.COLOR_YELLOW;
        }
        if (state == STATE_BREAK) {
            return Graphics.COLOR_ORANGE;
        }
        if (state == STATE_FINISHED) {
            return Graphics.COLOR_RED;
        }
        return Graphics.COLOR_LT_GRAY;
    }

    //! Word describing the current game state.
    private function stateLabel() as String {
        var state = _model.state;
        if (state == STATE_PAUSED) {
            return WatchUi.loadResource($.Rez.Strings.LabelPaused) as String;
        }
        if (state == STATE_BREAK) {
            return WatchUi.loadResource($.Rez.Strings.LabelBreak) as String;
        }
        if (state == STATE_FINISHED) {
            return WatchUi.loadResource($.Rez.Strings.LabelFinal) as String;
        }
        return WatchUi.loadResource($.Rez.Strings.LabelReady) as String;
    }
}

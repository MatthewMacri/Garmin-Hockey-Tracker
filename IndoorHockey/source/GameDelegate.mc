//
// Buttons and taps for the main game screen.
//
// Button map, chosen so the two things you do constantly need no menu:
//   START/SELECT  start, pause, or face off the next period
//   UP            new shift (also marks a FIT lap)
//   DOWN          log a shot
//   MENU          everything else
//   BACK          end the game (asks first), or leave if nothing is recorded
//
// On touch screens: tap the clock to start/pause, the shift line for a new
// shift, the stat line to open the menu.
//

import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class GameDelegate extends WatchUi.BehaviorDelegate {

    private var _model as GameModel;
    private var _view as GameView;

    //! Constructor.
    //! @param model The game being played
    //! @param view The view to ask about tap regions
    public function initialize(model as GameModel, view as GameView) {
        BehaviorDelegate.initialize();
        _model = model;
        _view = view;
    }

    //! START/SELECT.
    public function onSelect() as Boolean {
        primaryAction();
        WatchUi.requestUpdate();
        return true;
    }

    //! UP: close this shift and start the next one.
    public function onPreviousPage() as Boolean {
        _model.newShift();
        WatchUi.requestUpdate();
        return true;
    }

    //! DOWN: the most common thing worth counting.
    public function onNextPage() as Boolean {
        _model.addStat(STAT_SHOT);
        WatchUi.requestUpdate();
        return true;
    }

    //! MENU: stats, periods, ending the game.
    public function onMenu() as Boolean {
        WatchUi.pushView(GameMenus.build(_model), new $.GameMenuDelegate(_model), WatchUi.SLIDE_UP);
        return true;
    }

    //! BACK: leave, but never throw away a game in progress without asking.
    public function onBack() as Boolean {
        var state = _model.state;
        if (state == STATE_READY || state == STATE_FINISHED) {
            // Nothing to lose: let the system close the app.
            return false;
        }

        var text = WatchUi.loadResource($.Rez.Strings.ConfirmEnd) as String;
        WatchUi.pushView(new WatchUi.Confirmation(text), new $.EndGameConfirmDelegate(_model), WatchUi.SLIDE_UP);
        return true;
    }

    //! Touch screens: act on where the finger landed.
    public function onTap(clickEvent as WatchUi.ClickEvent) as Boolean {
        var coordinates = clickEvent.getCoordinates();
        var settings = System.getDeviceSettings();
        var zone = _view.zoneAt(coordinates[1], settings.screenHeight);

        if (zone == ZONE_SHIFT) {
            _model.newShift();
        } else if (zone == ZONE_STATS) {
            WatchUi.pushView(GameMenus.build(_model), new $.GameMenuDelegate(_model), WatchUi.SLIDE_UP);
            return true;
        } else {
            primaryAction();
        }

        WatchUi.requestUpdate();
        return true;
    }

    //! What START does depends on where the game is.
    private function primaryAction() as Void {
        var state = _model.state;

        if (state == STATE_FINISHED) {
            return;
        }

        if (state == STATE_BREAK) {
            if (_model.isLastPeriod()) {
                // Last period is over: the only thing left is to finish.
                var text = WatchUi.loadResource($.Rez.Strings.ConfirmEnd) as String;
                WatchUi.pushView(new WatchUi.Confirmation(text), new $.EndGameConfirmDelegate(_model), WatchUi.SLIDE_UP);
            } else {
                _model.nextPeriod();
                _model.start();
            }
            return;
        }

        _model.toggleRun();
    }
}

//! Yes/no for ending the game. Answering yes saves the activity; the main
//! screen then redraws itself as the post-game summary.
class EndGameConfirmDelegate extends WatchUi.ConfirmationDelegate {

    private var _model as GameModel;

    //! Constructor.
    //! @param model The game to end
    public function initialize(model as GameModel) {
        ConfirmationDelegate.initialize();
        _model = model;
    }

    //! Handle the answer.
    //! @param value What the user chose
    //! @return true, the response is handled here
    public function onResponse(value as WatchUi.Confirm) as Boolean {
        if (value == WatchUi.CONFIRM_YES) {
            _model.endGame(true);
        }
        WatchUi.requestUpdate();
        return true;
    }
}

//
// Buttons.
//
// The app is built to be left alone once the game starts, so every button here
// is a correction or an escape hatch rather than part of normal play. Nothing
// in a game requires a press after the first one.
//

import Toybox.Lang;
import Toybox.WatchUi;

class GameDelegate extends WatchUi.BehaviorDelegate {

    private var _model as GameModel;

    //! Constructor.
    public function initialize(model as GameModel) {
        BehaviorDelegate.initialize();
        _model = model;
    }

    //! START/STOP: begin the game, pause it, resume it, or skip an intermission.
    public function onSelect() as Boolean {
        _model.toggleRun();
        WatchUi.requestUpdate();
        return true;
    }

    //! UP: tell the app it got the shift wrong and flip the state by hand.
    public function onPreviousPage() as Boolean {
        _model.markSwitch();
        WatchUi.requestUpdate();
        return true;
    }

    //! DOWN: end the period early, or skip the rest of an intermission.
    public function onNextPage() as Boolean {
        _model.skipAhead();
        WatchUi.requestUpdate();
        return true;
    }

    //! MENU: everything else.
    public function onMenu() as Boolean {
        WatchUi.pushView(GameMenus.build(_model), new $.GameMenuDelegate(_model), WatchUi.SLIDE_UP);
        return true;
    }

    //! BACK: end the game, with a confirmation so a knock cannot do it.
    public function onBack() as Boolean {
        if (_model.state == STATE_FINISHED || _model.state == STATE_READY) {
            return false;
        }
        var prompt = WatchUi.loadResource($.Rez.Strings.ConfirmEnd) as String;
        WatchUi.pushView(new WatchUi.Confirmation(prompt),
            new $.EndGameConfirmDelegate(_model), WatchUi.SLIDE_UP);
        return true;
    }
}

//! Yes/no on ending the game.
class EndGameConfirmDelegate extends WatchUi.ConfirmationDelegate {

    private var _model as GameModel;

    //! Constructor.
    public function initialize(model as GameModel) {
        ConfirmationDelegate.initialize();
        _model = model;
    }

    //! Save and finish on yes; do nothing on no. The summary is drawn by the
    //! view that is already on screen, so there is no view to push from here.
    public function onResponse(response as WatchUi.Confirm) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            _model.endGame(true);
            WatchUi.requestUpdate();
        }
        return true;
    }
}

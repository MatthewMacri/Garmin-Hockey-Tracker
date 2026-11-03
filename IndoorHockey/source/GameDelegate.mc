//
// Buttons.
//
// Laid out the way Garmin's own activities are laid out, so that muscle memory
// built on the stock Run or Bike app transfers to this one:
//
//   START/STOP   start the game; press again to stop and get the stop menu
//   BACK (LAP)   mark a lap - here, a line change
//   UP / DOWN    nothing during play, as on a profile with one data screen
//   hold UP      the menu
//
// Two things follow from that and are worth stating, because both are
// departures from where this app started.
//
// BACK no longer ends the game. In every Garmin activity BACK is the lap key,
// never the exit, and a hockey lap is a shift - so BACK is the one button whose
// traditional meaning the app already had a use for. It also means a knock
// against the boards can no longer end a game, which the old binding allowed
// behind a confirmation.
//
// Ending a game now goes through the stop menu, the way stopping a run does:
// START, then Save or Discard. DOWN no longer ends the period, because a
// mis-press in a pocket or a glove should not be able to burn a period.
// Everything it used to do is still in the menu.
//
// None of this is needed during normal play. The app is built to be left alone
// once the game starts.
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

    //! START/STOP, as on a stock activity: start, then stop into the stop menu,
    //! then resume. During an intermission it skips the rest of the break.
    public function onSelect() as Boolean {
        var state = _model.state;

        if (state == STATE_RUNNING) {
            // Garmin's behaviour: STOP pauses and immediately offers resume,
            // save and discard rather than making you hunt for them.
            _model.pause();
            pushStopMenu();
        } else if (state == STATE_BREAK) {
            _model.skipAhead();
        } else if (state == STATE_PAUSED || state == STATE_READY) {
            _model.toggleRun();
        } else {
            return false;   // FINISHED: nothing left to start.
        }

        WatchUi.requestUpdate();
        return true;
    }

    //! BACK is the LAP key during an activity, and a lap in this app is a line
    //! change - so it corrects the detector when it has the shift state wrong.
    //! On the READY and FINISHED screens there is no activity, so it falls
    //! through and leaves the app as BACK normally would.
    public function onBack() as Boolean {
        var state = _model.state;

        if (state == STATE_RUNNING) {
            _model.markSwitch();
            WatchUi.requestUpdate();
            return true;
        }
        if (state == STATE_PAUSED || state == STATE_BREAK) {
            // A game is still open. Offer the way out rather than dropping out
            // of the app with it unsaved.
            pushStopMenu();
            return true;
        }
        return false;
    }

    //! UP: no data pages to move through - the single screen is deliberate, as
    //! there is no realistic way to page through one while skating. Swallowed
    //! rather than passed on so a stray press does nothing at all.
    public function onPreviousPage() as Boolean {
        return _model.state == STATE_READY ? false : true;
    }

    //! DOWN: as UP.
    public function onNextPage() as Boolean {
        return _model.state == STATE_READY ? false : true;
    }

    //! MENU (hold UP): everything the buttons no longer do.
    public function onMenu() as Boolean {
        WatchUi.pushView(GameMenus.build(_model), new $.GameMenuDelegate(_model), WatchUi.SLIDE_UP);
        return true;
    }

    //! The stop menu: resume, save, discard - Garmin's own post-STOP menu.
    private function pushStopMenu() as Void {
        WatchUi.pushView(GameMenus.stopMenu(_model), new $.GameMenuDelegate(_model), WatchUi.SLIDE_UP);
    }
}

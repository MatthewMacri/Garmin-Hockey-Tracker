//
// Buttons.
//
// Laid out the way Garmin's own activities are laid out, so that muscle memory
// built on the stock Run or Bike app transfers to this one:
//
//   START/STOP   start the game; press TWICE to stop and get the stop menu
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
// Pausing takes two presses rather than one, and screen taps do nothing at all
// while a game is live. Both are there because a single press was too easy to
// make by accident: SELECT fires on a touchscreen tap as well as on the button,
// and a game on 2026-11-03 lost seven minutes to two pauses nobody meant to
// make.
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
            // Two presses, not one. The first arms and buzzes; the second,
            // within three seconds, pauses. See GameModel.requestPause() for
            // why - in short, this watch has a touchscreen and SELECT fires on
            // a tap, so one press was never only a press.
            if (_model.requestPause()) {
                // Garmin's behaviour: STOP pauses and immediately offers
                // resume, save and discard rather than making you hunt.
                pushStopMenu();
            }
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

    //! Screen taps, swallowed while a game is live.
    //!
    //! On a touchscreen watch WatchUi turns a tap into the SELECT behaviour,
    //! which is the same path as the START button - so without this, brushing
    //! the display with a glove runs the pause code. There is nothing on this
    //! screen to tap: one data page, no paging, no on-screen controls. So a tap
    //! during a game can only be an accident, and the cheapest way to honour
    //! "I never touch the watch during a game" is to make the glass inert.
    //!
    //! The menus are their own delegates and still take touch normally, so
    //! this costs nothing once a menu is actually open and deliberate.
    public function onTap(clickEvent as WatchUi.ClickEvent) as Boolean {
        var state = _model.state;
        if (state == STATE_RUNNING || state == STATE_PAUSED || state == STATE_BREAK) {
            return true;    // Handled, meaning: ignored.
        }
        return false;
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

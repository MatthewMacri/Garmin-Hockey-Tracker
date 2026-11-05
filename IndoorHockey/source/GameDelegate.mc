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
// Ending a game goes through the stop menu, the way stopping a run does:
// START twice, then Save or Discard.
//
// DOWN used to end the period. There are no periods any more - a game is one
// continuous recording - so there is nothing for it to end.
//
// Pausing takes two presses rather than one, and touch does nothing at all
// while a game is live. Both are there because a single press was too easy to
// make by accident: a game on 2026-11-03 lost seven minutes to two pauses
// nobody meant to make.
//
// How touch is told apart from the buttons, since this is the part that is easy
// to get wrong: on this watch the touchscreen does NOT deliver onTap() to an
// app that handles behaviours. Garmin's own device definition maps the gestures
// straight onto behaviours -
//
//   tap        -> onSelect      (the same entry point as the START button)
//   swipeRight -> onBack        (the same entry point as the BACK button)
//
// so overriding onTap() swallows nothing, and a glove on the glass runs the
// same code a deliberate press does. Confirmed in the simulator rather than
// inferred: a tap produces onSelect with no key event of any kind, while the
// START button produces onKeyPressed(KEY_ENTER) immediately before onSelect.
//
// That ordering is the whole discriminator. onKeyPressed() fires only for
// physical buttons, so a behaviour arriving without one just before it came
// from the glass.
//
// None of this is needed during normal play. The app is built to be left alone
// once the game starts.
//

import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class GameDelegate extends WatchUi.BehaviorDelegate {

    private var _model as GameModel;

    // When a physical button was last pressed, and whether one ever has been.
    private var _lastKeyAt as Number = -1;
    private var _sawRealKey as Boolean = false;

    // A behaviour follows its key event in the same input dispatch, so the gap
    // is reliably zero. A whole second is far more slack than that needs.
    private const KEY_GRACE_MS = 1000;

    //! Constructor.
    public function initialize(model as GameModel) {
        BehaviorDelegate.initialize();
        _model = model;
    }

    //! Physical buttons, and only physical buttons, come through here.
    public function onKeyPressed(keyEvent as WatchUi.KeyEvent) as Boolean {
        _lastKeyAt = System.getTimer();
        _sawRealKey = true;
        return false;   // Let the behaviour mapping run as usual.
    }

    //! True when the behaviour being handled came from a button rather than
    //! from the glass.
    //!
    //! Fails open deliberately. If a watch never delivers onKeyPressed() at
    //! all, every press would otherwise look like a tap and the app would stop
    //! responding to its own START button - unusable, and unusable in a way
    //! that only shows up on hardware nobody tested. So touch is only ever
    //! rejected once a real key event has been seen at least once, which on
    //! this app is always: the press that starts the game is a button press.
    private function fromButton() as Boolean {
        if (!_sawRealKey) {
            return true;
        }
        if (_lastKeyAt < 0) {
            return false;
        }
        var age = System.getTimer() - _lastKeyAt;
        if (age < 0) {
            return false;   // System.getTimer() wrapped; treat it as stale.
        }
        return age <= KEY_GRACE_MS;
    }

    //! START/STOP, as on a stock activity: start, then stop into the stop
    //! menu, then resume. Pausing takes two presses - see requestPause().
    public function onSelect() as Boolean {
        var state = _model.state;

        // A tap while a game is live can only be an accident: one data page, no
        // paging, no on-screen controls, and the player is wearing gloves.
        if ((state == STATE_RUNNING || state == STATE_PAUSED) && !fromButton()) {
            return true;    // Handled, meaning: ignored.
        }

        // A pending auto-end is a question, and this is an answer to it. The
        // press cancels and does nothing else: a player who grabs the watch to
        // stop it ending should not find they have paused the game instead.
        if (_model.cancelAutoEnd()) {
            WatchUi.requestUpdate();
            return true;
        }

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

        // A swipe right arrives here exactly as the BACK button does. Letting
        // it through is worse than an accidental pause: markSwitch() flips the
        // detector, so the player carries on skating while the app records
        // bench, and the on-ice heart rate split - the thing the app exists to
        // produce - is quietly wrong for the rest of the shift. An accidental
        // pause at least shows on the screen.
        if ((state == STATE_RUNNING || state == STATE_PAUSED) && !fromButton()) {
            return true;    // Handled, meaning: ignored.
        }

        // As in onSelect(): cancelling the auto-end is all this press does, so
        // it cannot also flip the shift state by accident.
        if (_model.cancelAutoEnd()) {
            WatchUi.requestUpdate();
            return true;
        }

        if (state == STATE_RUNNING) {
            _model.markSwitch();
            WatchUi.requestUpdate();
            return true;
        }
        if (state == STATE_PAUSED) {
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
        return swallow();
    }

    //! DOWN: as UP.
    public function onNextPage() as Boolean {
        return swallow();
    }

    //! Swallow the press, but let a real button cancel a pending auto-end.
    //!
    //! The fromButton() guard matters more here than anywhere else in this
    //! file. On any variant that maps a vertical swipe onto these behaviours,
    //! cloth brushing the glass in a gear bag would reach cancelAutoEnd() and
    //! reset the idle clock - over and over, indefinitely - which is exactly
    //! the forgotten recording the auto-end exists to stop. A press has to be
    //! a press before it can count as somebody answering the question.
    private function swallow() as Boolean {
        if (fromButton() && _model.cancelAutoEnd()) {
            WatchUi.requestUpdate();
            return true;
        }
        return _model.state == STATE_READY ? false : true;
    }

    //! Screen taps, swallowed while a game is live.
    //!
    //! Belt and braces. This watch never calls it - it turns a tap into the
    //! SELECT behaviour instead, which is why onSelect() carries the real guard
    //! - but the app ships to 202 device variants and the gesture mapping is
    //! per-device. On any of them that does deliver a tap here, this stops it
    //! before it becomes a behaviour at all.
    //!
    //! The menus are their own delegates and still take touch normally, so
    //! this costs nothing once a menu is actually open and deliberate.
    public function onTap(clickEvent as WatchUi.ClickEvent) as Boolean {
        var state = _model.state;
        if (state == STATE_RUNNING || state == STATE_PAUSED) {
            return true;    // Handled, meaning: ignored.
        }
        return false;
    }

    //! MENU (hold UP): everything the buttons no longer do.
    //!
    //! Only while a game is open. On READY and FINISHED every item the menu
    //! builds is gated on a running or paused game, so it would push a titled
    //! menu with nothing in it - a screen whose only way out is BACK.
    public function onMenu() as Boolean {
        var state = _model.state;
        if (state != STATE_RUNNING && state != STATE_PAUSED) {
            return false;
        }
        // Opening the menu answers a pending auto-end rather than hiding it.
        // Someone who feels the buzz and holds UP to reach Discard is reaching
        // for the opposite of what the countdown would do, and the countdown
        // cannot follow them onto the menu screen.
        _model.cancelAutoEnd();
        WatchUi.pushView(GameMenus.build(_model), new $.GameMenuDelegate(_model), WatchUi.SLIDE_UP);
        return true;
    }

    //! The stop menu: resume, save, discard - Garmin's own post-STOP menu.
    private function pushStopMenu() as Void {
        WatchUi.pushView(GameMenus.stopMenu(_model), new $.GameMenuDelegate(_model), WatchUi.SLIDE_UP);
    }
}

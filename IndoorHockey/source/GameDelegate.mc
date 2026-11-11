//
// Buttons.
//
// Laid out the way Garmin's own activities are laid out, so that muscle memory
// built on the stock Run or Bike app transfers to this one:
//
//   START/STOP   start the game; HOLD to stop and get the stop menu
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
// hold START, then Save or Discard.
//
// DOWN used to end the period. There are no periods any more - a game is one
// continuous recording - so there is nothing for it to end.
//
// Pausing is a one-second HOLD that takes effect when the button comes back
// UP, and touch does nothing at all while a game is live. Both are there
// because a press is too easy to make by accident: a game on 2026-11-03 lost
// seven minutes to two pauses nobody meant to make, and on 2026-11-09 a player
// lost a whole game to a button rubbing inside a glove. Two presses within a
// window was the first answer and it was not enough - a rubbing button
// produces the second press by itself.
//
// Acting on the release rather than at the threshold is 2.5.7, and it is there
// because on the 34 products with no LIGHT key the system's own lock gesture is
// a hold of this very button. See GameModel.beginPauseHold().
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
import Toybox.Timer;
import Toybox.WatchUi;

class GameDelegate extends WatchUi.BehaviorDelegate {

    private var _model as GameModel;

    // When a physical button was last pressed, and whether one ever has been.
    private var _lastKeyAt as Number = -1;
    private var _sawRealKey as Boolean = false;

    // A behaviour follows its key event in the same input dispatch, so the gap
    // is reliably zero. A whole second is far more slack than that needs.
    private const KEY_GRACE_MS = 1000;

    // Why a hold at all, rather than a press:
    //
    // Pausing was two presses within a window until 2.5.5, and a player lost
    // a game to it on 2026-11-09: a button rubbing inside a glove produced
    // the second press on its own. Narrowing the window only narrowed the
    // odds - any press-twice scheme is one a rubbing button can satisfy.
    //
    // A hold cannot be produced by accident. Contact has to be made AND
    // maintained for a second, which a glove brushing past does not do, and
    // which a touchscreen tap cannot do at all: a tap arrives as a behaviour
    // with no key event, and this path is driven entirely by key events.
    //
    // The threshold itself is $.PAUSE_HOLD_MS, and the hold is timed by
    // GameModel so that the view can abandon one.

    // Fires once at the threshold, only to redraw the hint. It decides
    // nothing, which is the point - see onHoldThreshold().
    private var _holdHint as Timer.Timer?;

    //! Constructor.
    public function initialize(model as GameModel) {
        BehaviorDelegate.initialize();
        _model = model;
    }

    //! Physical buttons, and only physical buttons, come through here.
    public function onKeyPressed(keyEvent as WatchUi.KeyEvent) as Boolean {
        _lastKeyAt = System.getTimer();
        _sawRealKey = true;

        // START going down during a game starts timing a hold. It does not
        // schedule a pause: nothing here can pause the game, and nothing on a
        // timer can either. See GameModel.beginPauseHold().
        if (keyEvent.getKey() == WatchUi.KEY_ENTER
                && _model.state == STATE_RUNNING) {
            _model.beginPauseHold();
            armHoldHint();
            WatchUi.requestUpdate();
        }
        return false;   // Let the behaviour mapping run as usual.
    }

    //! START coming back up is where the pause is decided. Held for the full
    //! second, the game pauses and the stop menu opens; released early, the
    //! hold is dropped and nothing happens at all - which is what a short
    //! press on START does during a game.
    //!
    //! This is the only place a hold can turn into a pause. If the release
    //! never arrives - because the system controls menu took the app's screen
    //! and the overlay got the key up instead - then the game simply carries
    //! on recording, which on a watch nobody is going to touch again is the
    //! only acceptable way for this to fail.
    public function onKeyReleased(keyEvent as WatchUi.KeyEvent) as Boolean {
        cancelHoldHint();
        if (keyEvent.getKey() != WatchUi.KEY_ENTER) {
            // Some other button came up mid-hold. Whatever that was, it was
            // not a clean hold of START; drop it rather than credit it.
            if (_model.pauseHoldArmed()) {
                _model.cancelPauseHold();
                WatchUi.requestUpdate();
            }
            return false;
        }
        if (_model.endPauseHold()) {
            _model.pause();
            pushStopMenu();
        }
        WatchUi.requestUpdate();
        return false;
    }

    //! One redraw at the threshold, so the hint can change from "keep holding"
    //! to "let go". It changes no state and takes no decision, which is why it
    //! is safe for it to fire after the app has lost the screen: the worst it
    //! can do there is ask for a repaint nobody sees.
    public function onHoldThreshold() as Void {
        _holdHint = null;
        WatchUi.requestUpdate();
    }

    //! Arm that one redraw.
    private function armHoldHint() as Void {
        cancelHoldHint();
        var timer = new Timer.Timer();
        timer.start(method(:onHoldThreshold), $.PAUSE_HOLD_MS, false);
        _holdHint = timer;
    }

    //! Drop it.
    private function cancelHoldHint() as Void {
        var timer = _holdHint;
        if (timer != null) {
            timer.stop();
            _holdHint = null;
        }
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

    //! START/STOP: start a game, or resume a paused one. Pausing a RUNNING
    //! game is not here - it is a hold, see onKeyPressed().
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
            // Nothing. Pausing is a HOLD, decided in onKeyReleased, and a
            // short press during a game is exactly the event a glove
            // produces - so it has to do nothing at all.
            //
            // This is also why the pause cannot live here even in part:
            // onSelect fires on the key going DOWN, about a millisecond
            // after onKeyPressed and long before the button comes back up.
            // Measured in the simulator, a 2,010 ms hold and a 74 ms tap
            // both reach this function at the same point. Nothing here can
            // tell them apart.
            return true;
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

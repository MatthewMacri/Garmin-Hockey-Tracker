//
// The menus: corrections, and the way out.
//
// There are two. The stop menu is what STOP raises mid-game, and it mirrors the
// menu a stock Garmin activity shows after you stop a run - resume, save,
// discard. The in-game menu is what holding UP raises, and it holds the same
// plus the corrections that no longer have a button of their own.
//

import Toybox.Lang;
import Toybox.WatchUi;

module GameMenus {

    //! Add the ways out of a game. `withDiscard` is false for the stop menu:
    //! see stopMenu() for why throwing a game away is not offered there.
    function addExits(menu as WatchUi.Menu2, model as $.GameModel,
                      withDiscard as Boolean) as Void {
        if (model.state == $.STATE_FINISHED || model.state == $.STATE_READY) {
            return;
        }
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource($.Rez.Strings.MenuEndGame) as String, null, :end, null));
        if (withDiscard) {
            menu.addItem(new WatchUi.MenuItem(
                WatchUi.loadResource($.Rez.Strings.MenuDiscard) as String, null, :discard, null));
        }
    }

    //! What STOP raises: resume at the top, as on a stock activity, so the most
    //! likely intention is one press away and saving is never accidental.
    //!
    //! Discard is deliberately NOT here. This menu is where an accidental
    //! press chain lands - and a player reported exactly that on 2026-11-09:
    //! a button rubbing inside a glove paused the game repeatedly and
    //! eventually ended AND discarded it. The two-press guard on STOP stops
    //! one stray press; it does nothing about a button being rubbed, which
    //! produces two presses inside three seconds every time.
    //!
    //! So the only destructive item in the app is now reachable only from
    //! the menu raised by HOLDING UP, which is a gesture a glove against a
    //! button cannot produce. Everything this menu offers either continues
    //! the game or saves it.
    function stopMenu(model as $.GameModel) as WatchUi.Menu2 {
        var menu = new WatchUi.Menu2({
            :title => WatchUi.loadResource($.Rez.Strings.MenuStoppedTitle) as String
        });
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource($.Rez.Strings.MenuResume) as String, null, :resume, null));
        addExits(menu, model, false);
        return menu;
    }

    //! What holding UP raises: the corrections as well as the exits.
    function build(model as $.GameModel) as WatchUi.Menu2 {
        var menu = new WatchUi.Menu2({
            :title => WatchUi.loadResource($.Rez.Strings.MenuTitle) as String
        });

        if (model.state == $.STATE_RUNNING) {
            // The id carries the DIRECTION, not "flip whatever you are now".
            // The label is chosen here, at build time; :mark used to call
            // markSwitch(), which re-read onIce() when the item was selected.
            // Leave the menu open for half a minute, let the detector bench
            // the player behind it, and the item then did the opposite of
            // what it said - corrupting the ice/bench split and adding a
            // phantom shift. A correction has to mean what it said when the
            // player read it.
            var onIceNow = model.onIce();
            menu.addItem(new WatchUi.MenuItem(
                WatchUi.loadResource(onIceNow
                    ? $.Rez.Strings.MenuMarkBench
                    : $.Rez.Strings.MenuMarkIce) as String, null,
                onIceNow ? :markBench : :markIce, null));
            menu.addItem(new WatchUi.MenuItem(
                WatchUi.loadResource($.Rez.Strings.MenuPause) as String, null, :pause, null));
        } else if (model.state == $.STATE_PAUSED) {
            menu.addItem(new WatchUi.MenuItem(
                WatchUi.loadResource($.Rez.Strings.MenuResume) as String, null, :resume, null));
        }

        addExits(menu, model, true);
        return menu;
    }

    //! Yes/no on an irreversible item, as a MENU rather than a dialog.
    //!
    //! It was a WatchUi.Confirmation until 2.5.4. The problem with that is
    //! documented in SDK 9.3.0 by omission: Confirmation takes a prompt and
    //! nothing else - no :defaultResponse, no setDefaultResponse() - so the
    //! app cannot ask for the safe answer to be preselected and has to trust
    //! the firmware to do it. In the simulator the prompt draws no highlight
    //! on either option and a bare START press through it ends or discards
    //! the game.
    //!
    //! On 2026-11-09 a player reported losing a game to exactly that: a
    //! button rubbing inside a glove pressed its way through to discard. So
    //! the firmware does not reliably preselect no, and the guard was one
    //! extra press rather than a decision.
    //!
    //! A Menu2 opens on its first item and the app chooses the order, which
    //! is the only way to be certain. The safe answer is first, so the press
    //! that opens this screen cannot also answer it destructively.
    function confirmMenu(keep as Boolean) as WatchUi.Menu2 {
        var menu = new WatchUi.Menu2({
            :title => WatchUi.loadResource(keep
                ? $.Rez.Strings.ConfirmEnd
                : $.Rez.Strings.ConfirmDiscard) as String
        });
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource($.Rez.Strings.ConfirmNo) as String, null, :no, null));
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(keep
                ? $.Rez.Strings.ConfirmYesEnd
                : $.Rez.Strings.ConfirmYesDiscard) as String, null, :yes, null));
        return menu;
    }
}

//! Acts on whatever was chosen.
class GameMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _model as GameModel;

    //! Constructor.
    public function initialize(model as GameModel) {
        Menu2InputDelegate.initialize();
        _model = model;
    }

    //! Dispatch on the item's id.
    public function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();

        // The two items that cannot be taken back both ask first.
        //
        // Ending used to go straight through. On a touchscreen watch that put
        // a finished, saved game three taps from a running one with nothing in
        // the way - and because the stop menu is where an accidental pause
        // lands you, those three taps are reachable without ever meaning to
        // press anything. STATE_FINISHED is terminal, so there is no way back
        // from it mid-game.
        if (id == :discard || id == :end) {
            var keep = (id == :end);
            // Drop the menu before raising the question, so answering it
            // lands back on the game rather than on a menu describing a game
            // that has just been ended.
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            WatchUi.pushView(GameMenus.confirmMenu(keep),
                new $.EndConfirmDelegate(_model, keep), WatchUi.SLIDE_UP);
            return;
        }

        if (id == :pause) {
            _model.pause();
        } else if (id == :resume) {
            _model.toggleRun();
        } else if (id == :markIce) {
            _model.markSwitchTo(true);
        } else if (id == :markBench) {
            _model.markSwitchTo(false);
        }

        WatchUi.popView(WatchUi.SLIDE_DOWN);
        WatchUi.requestUpdate();
    }
}

//! Yes/no on throwing the game away.
class EndConfirmDelegate extends WatchUi.Menu2InputDelegate {

    private var _model as GameModel;
    private var _keep as Boolean;

    //! keep is what endGame() is told: true saves the game, false throws it
    //! away. One delegate for both so the two irreversible items cannot drift
    //! apart in how they confirm.
    public function initialize(model as GameModel, keep as Boolean) {
        Menu2InputDelegate.initialize();
        _model = model;
        _keep = keep;
    }

    //! Act on yes, nothing on no.
    public function onSelect(item as WatchUi.MenuItem) as Void {
        var yes = (item.getId() == :yes);
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        if (yes) {
            _model.endGame(_keep);
        }
        WatchUi.requestUpdate();
    }

    //! BACK out of the question is a "no", which is what BACK means
    //! everywhere else on this watch.
    public function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        WatchUi.requestUpdate();
    }
}

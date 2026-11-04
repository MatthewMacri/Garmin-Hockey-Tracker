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

    //! Add save and discard to a menu. Shared by both menus so the two cannot
    //! drift apart.
    function addExits(menu as WatchUi.Menu2, model as $.GameModel) as Void {
        if (model.state == $.STATE_FINISHED || model.state == $.STATE_READY) {
            return;
        }
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource($.Rez.Strings.MenuEndGame) as String, null, :end, null));
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource($.Rez.Strings.MenuDiscard) as String, null, :discard, null));
    }

    //! What STOP raises: resume at the top, as on a stock activity, so the most
    //! likely intention is one press away and saving is never accidental.
    function stopMenu(model as $.GameModel) as WatchUi.Menu2 {
        var menu = new WatchUi.Menu2({
            :title => WatchUi.loadResource($.Rez.Strings.MenuStoppedTitle) as String
        });
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource($.Rez.Strings.MenuResume) as String, null, :resume, null));
        addExits(menu, model);
        return menu;
    }

    //! What holding UP raises: the corrections as well as the exits.
    function build(model as $.GameModel) as WatchUi.Menu2 {
        var menu = new WatchUi.Menu2({
            :title => WatchUi.loadResource($.Rez.Strings.MenuTitle) as String
        });

        if (model.state == $.STATE_RUNNING) {
            menu.addItem(new WatchUi.MenuItem(
                WatchUi.loadResource(model.onIce()
                    ? $.Rez.Strings.MenuMarkBench
                    : $.Rez.Strings.MenuMarkIce) as String, null, :mark, null));
            menu.addItem(new WatchUi.MenuItem(
                WatchUi.loadResource($.Rez.Strings.MenuPause) as String, null, :pause, null));
        } else if (model.state == $.STATE_PAUSED) {
            menu.addItem(new WatchUi.MenuItem(
                WatchUi.loadResource($.Rez.Strings.MenuResume) as String, null, :resume, null));
        }

        addExits(menu, model);
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
            var prompt = WatchUi.loadResource(
                keep ? $.Rez.Strings.ConfirmEnd : $.Rez.Strings.ConfirmDiscard) as String;
            // Drop the menu before raising the prompt, so answering it lands
            // back on the game rather than on a menu describing a game that
            // has just been ended.
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            WatchUi.pushView(new WatchUi.Confirmation(prompt),
                new $.EndConfirmDelegate(_model, keep), WatchUi.SLIDE_UP);
            return;
        }

        if (id == :pause) {
            _model.pause();
        } else if (id == :resume) {
            _model.toggleRun();
        } else if (id == :mark) {
            _model.markSwitch();
        }

        WatchUi.popView(WatchUi.SLIDE_DOWN);
        WatchUi.requestUpdate();
    }
}

//! Yes/no on throwing the game away.
class EndConfirmDelegate extends WatchUi.ConfirmationDelegate {

    private var _model as GameModel;
    private var _keep as Boolean;

    //! keep is what endGame() is told: true saves the game, false throws it
    //! away. One delegate for both so the two irreversible items cannot drift
    //! apart in how they confirm.
    public function initialize(model as GameModel, keep as Boolean) {
        ConfirmationDelegate.initialize();
        _model = model;
        _keep = keep;
    }

    //! Act on yes, nothing on no. The system pops the prompt either way,
    //! which lands back on the game screen.
    public function onResponse(response as WatchUi.Confirm) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            _model.endGame(_keep);
        }
        WatchUi.requestUpdate();
        return true;
    }
}

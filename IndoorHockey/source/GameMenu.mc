//
// The in-game menu: everything that is not a clock or a shift change.
//
// The menu is rebuilt each time it opens so it only ever offers actions that
// make sense right now.
//

import Toybox.Lang;
import Toybox.WatchUi;

module GameMenus {

//! Build the menu for the game's current state.
//! @param model The game being played
//! @return A menu ready to push
function build(model as $.GameModel) as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => WatchUi.loadResource($.Rez.Strings.MenuTitle) as String});

    if (model.state != $.STATE_READY && model.state != $.STATE_FINISHED) {
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource($.Rez.Strings.MenuGoal) as String, model.goals.toString(), :goal, null));
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource($.Rez.Strings.MenuAssist) as String, model.assists.toString(), :assist, null));
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource($.Rez.Strings.MenuShot) as String, model.shots.toString(), :shot, null));
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource($.Rez.Strings.MenuSave) as String, model.saves.toString(), :save, null));
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource($.Rez.Strings.MenuNewShift) as String, model.shiftCount.toString(), :newShift, null));

        if (model.canUndo()) {
            menu.addItem(new WatchUi.MenuItem(
                WatchUi.loadResource($.Rez.Strings.MenuUndo) as String, null, :undo, null));
        }

        if (!model.isLastPeriod()) {
            menu.addItem(new WatchUi.MenuItem(
                WatchUi.loadResource($.Rez.Strings.MenuNextPeriod) as String, null, :nextPeriod, null));
        }

        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource($.Rez.Strings.MenuEndGame) as String, null, :endGame, null));
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource($.Rez.Strings.MenuDiscard) as String, null, :discardGame, null));
    } else {
        // Before kickoff and after the final whistle there is nothing to log.
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource($.Rez.Strings.MenuResume) as String, null, :back, null));
    }

    return menu;
}

}

class GameMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _model as GameModel;

    //! Constructor.
    //! @param model The game to act on
    public function initialize(model as GameModel) {
        Menu2InputDelegate.initialize();
        _model = model;
    }

    //! Apply the chosen action and close the menu.
    //! @param item The menu item that was picked
    public function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();

        if (id == :goal) {
            _model.addStat(STAT_GOAL);
        } else if (id == :assist) {
            _model.addStat(STAT_ASSIST);
        } else if (id == :shot) {
            _model.addStat(STAT_SHOT);
        } else if (id == :save) {
            _model.addStat(STAT_SAVE);
        } else if (id == :newShift) {
            _model.newShift();
        } else if (id == :undo) {
            _model.undoStat();
        } else if (id == :nextPeriod) {
            _model.nextPeriod();
        } else if (id == :endGame) {
            _model.endGame(true);
        } else if (id == :discardGame) {
            _model.endGame(false);
        }

        WatchUi.popView(WatchUi.SLIDE_DOWN);
        WatchUi.requestUpdate();
    }
}

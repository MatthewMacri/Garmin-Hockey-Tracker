//
// The in-game menu: corrections and the way out.
//

import Toybox.Lang;
import Toybox.WatchUi;

module GameMenus {

    //! Build the menu for the state the game is currently in.
    function build(model as $.GameModel) as WatchUi.Menu2 {
        var menu = new WatchUi.Menu2({
            :title => WatchUi.loadResource($.Rez.Strings.MenuTitle) as String
        });

        if (model.state == $.STATE_RUNNING) {
            menu.addItem(new WatchUi.MenuItem(
                WatchUi.loadResource($.Rez.Strings.MenuPause) as String, null, :pause, null));
            menu.addItem(new WatchUi.MenuItem(
                WatchUi.loadResource(model.onIce()
                    ? $.Rez.Strings.MenuMarkBench
                    : $.Rez.Strings.MenuMarkIce) as String, null, :mark, null));
        } else if (model.state == $.STATE_PAUSED || model.state == $.STATE_BREAK) {
            menu.addItem(new WatchUi.MenuItem(
                WatchUi.loadResource($.Rez.Strings.MenuResume) as String, null, :resume, null));
        }

        if (model.state != $.STATE_FINISHED && model.state != $.STATE_READY) {
            if (!model.isLastPeriod()) {
                menu.addItem(new WatchUi.MenuItem(
                    WatchUi.loadResource($.Rez.Strings.MenuNextPeriod) as String, null, :next, null));
            }
            menu.addItem(new WatchUi.MenuItem(
                WatchUi.loadResource($.Rez.Strings.MenuEndGame) as String, null, :end, null));
            menu.addItem(new WatchUi.MenuItem(
                WatchUi.loadResource($.Rez.Strings.MenuDiscard) as String, null, :discard, null));
        }

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

        if (id == :pause) {
            _model.pause();
        } else if (id == :resume) {
            _model.toggleRun();
        } else if (id == :mark) {
            _model.markSwitch();
        } else if (id == :next) {
            _model.skipAhead();
        } else if (id == :end) {
            _model.endGame(true);
        } else if (id == :discard) {
            _model.endGame(false);
        }

        WatchUi.popView(WatchUi.SLIDE_DOWN);
        WatchUi.requestUpdate();
    }
}

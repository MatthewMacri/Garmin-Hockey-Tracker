//
// Ice Hockey Shifts - a hands-free game tracker for Garmin watches.
//
// Records a hockey activity to Garmin Connect, timing the whole session and
// working out every shift and every spell on the bench by itself. One press
// starts the game; nothing else needs to be touched until it ends.
//

import Toybox.Application;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

class IndoorHockeyApp extends Application.AppBase {

    private var _model as GameModel?;
    private var _timer as Timer.Timer?;

    //! Constructor.
    public function initialize() {
        AppBase.initialize();
    }

    //! Handle app startup. The game clock is owned here, not by the view, so
    //! that shift detection, alerts and the per-second FIT fields keep running
    //! while a menu or a confirmation is covering the screen.
    //! @param state Startup arguments
    public function onStart(state as Dictionary?) as Void {
        var timer = new Timer.Timer();
        timer.start(method(:onTick), 1000, true);
        _timer = timer;
    }

    //! Handle app shutdown. A game in progress is saved rather than lost.
    //! @param state Shutdown arguments
    public function onStop(state as Dictionary?) as Void {
        var timer = _timer;
        if (timer != null) {
            timer.stop();
            _timer = null;
        }
        var model = _model;
        if (model != null) {
            model.saveIfRecording();
        }
    }

    //! One second of game time.
    public function onTick() as Void {
        var model = _model;
        if (model != null) {
            model.onTick();
        }
    }

    //! The only screen the app has.
    //! @return The initial view and its input delegate
    public function getInitialView() as [Views] or [Views, InputDelegates] {
        var model = new $.GameModel();
        _model = model;
        return [new $.GameView(model), new $.GameDelegate(model)];
    }

    //! Pick up changes made in Garmin Connect without restarting the app.
    public function onSettingsChanged() as Void {
        var model = _model;
        if (model != null) {
            model.loadSettings();
            WatchUi.requestUpdate();
        }
    }
}

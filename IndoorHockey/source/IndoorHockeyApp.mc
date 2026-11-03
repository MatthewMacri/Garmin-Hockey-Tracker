//
// Indoor Hockey - a game tracker for Garmin watches.
//
// Records a hockey activity to Garmin Connect while keeping the period clock,
// the shift clock and your goals, assists, shots and saves on one screen.
//

import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class IndoorHockeyApp extends Application.AppBase {

    private var _model as GameModel?;

    //! Constructor.
    public function initialize() {
        AppBase.initialize();
    }

    //! Handle app startup.
    //! @param state Startup arguments
    public function onStart(state as Dictionary?) as Void {
    }

    //! Handle app shutdown. A game in progress is saved rather than lost.
    //! @param state Shutdown arguments
    public function onStop(state as Dictionary?) as Void {
        var model = _model;
        if (model != null) {
            model.saveIfRecording();
        }
    }

    //! The only screen the app has.
    //! @return The initial view and its input delegate
    public function getInitialView() as [Views] or [Views, InputDelegates] {
        var model = new $.GameModel();
        _model = model;
        var view = new $.GameView(model);
        return [view, new $.GameDelegate(model, view)];
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

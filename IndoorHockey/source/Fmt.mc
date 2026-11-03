//
// Small formatting helpers shared by the views.
//

import Toybox.Lang;
import Toybox.Math;

module Fmt {

    //! Format milliseconds as m:ss, or h:mm:ss once a game runs past an hour.
    function clock(ms as Number) as String {
        var total = ms / 1000;
        if (total < 0) {
            total = 0;
        }
        var hours = total / 3600;
        var minutes = (total / 60) % 60;
        var seconds = total % 60;

        if (hours > 0) {
            return Lang.format("$1$:$2$:$3$", [hours, pad(minutes), pad(seconds)]);
        }
        return Lang.format("$1$:$2$", [minutes, pad(seconds)]);
    }

    //! Two-digit zero padding.
    function pad(value as Number) as String {
        if (value < 10) {
            return "0" + value.toString();
        }
        return value.toString();
    }
}

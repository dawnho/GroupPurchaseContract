var _ = require("lodash");
var Promise = require("bluebird");

module.exports = {
    assertEvent: function(contract, eventName, filter) {
        return new Promise((resolve, reject) => {
            var event = contract[eventName]();
            event.watch();
            event.get((error, logs) => {
                var log = _.filter(logs, filter);
                if (!_.isEmpty(log)) {
                    resolve(log);
                } else {
                    throw Error("Failed to find filtered event for " + eventName);
                }
            });
            event.stopWatching();
        });
    },

    collectEvents: function(contract, eventName) {
        return new Promise((resolve, reject) => {
            var event = contract[eventName]();
            event.watch();
            event.get((error, logs) => {
                resolve(_.map(logs, l => l.args));
            });
            event.stopWatching();
        });
    }
}

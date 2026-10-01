import QtQuick
import "../code/wallhaven.js" as Wallhaven

// Opt-in watchers that feed the slideshow pause rules and reactive effects:
// battery level, session idle time, music playback and local weather. Each
// one only runs while its setting is enabled.
Item {
    id: monitors

    required property var host   // wallpaper root (main.qml)
    required property var dbus   // DBusHelper
    readonly property var cfg: host.cfg
    readonly property bool active: host._configured

    property int batteryPercent: 100
    property bool sessionIdle: false
    property bool musicPlaying: false
    property string _weatherLastLocation: ""

    // --- battery (pause when low)

    readonly property var batteryPaths: [
        "/sys/class/power_supply/BAT0/capacity",
        "/sys/class/power_supply/BAT1/capacity",
    ]

    function readBattery(index) {
        if (index >= batteryPaths.length) {
            return;
        }
        dbus.readFile(batteryPaths[index], function(text) {
            var pct = parseInt(String(text || "").trim(), 10);
            if (!isNaN(pct)) {
                monitors.batteryPercent = pct;
                host.evaluateSlideshowRules();
                return;
            }
            readBattery(index + 1);
        });
    }

    Timer {
        interval: 60000
        running: monitors.active && monitors.cfg.PauseOnBatteryLow
        repeat: true
        triggeredOnStart: true
        onTriggered: monitors.readBattery(0)
    }

    // --- idle (pause after N minutes without input)

    function pollIdle() {
        dbus.screenSaverCall("GetSessionIdleTime", function(seconds) {
            var idleSec = Number(Wallhaven.dbusReplyAsString(seconds)) || 0;
            var threshold = Math.max(1, cfg.IdlePauseMinutes || 5) * 60;
            monitors.sessionIdle = idleSec >= threshold;
            host.evaluateSlideshowRules();
        }, function() {
            monitors.sessionIdle = false;
        });
    }

    Timer {
        interval: 15000
        running: monitors.active && monitors.cfg.PauseOnIdleEnabled
        repeat: true
        triggeredOnStart: true
        onTriggered: monitors.pollIdle()
    }

    // --- music (Ken Burns speeds up while a player is playing)

    function pollMusic() {
        if (!cfg.MusicReactiveEnabled) {
            monitors.musicPlaying = false;
            return;
        }
        dbus.listBusNames(function(names) {
            var found = "";
            for (var i = 0; names && i < names.length; i++) {
                var name = String(names[i]);
                if (name.indexOf("org.mpris.MediaPlayer2.") === 0 && name !== "org.mpris.MediaPlayer2.wallhaven") {
                    found = name;
                    break;
                }
            }
            if (!found) {
                monitors.musicPlaying = false;
                return;
            }
            dbus.mprisPlaybackStatus(found, function(status) {
                monitors.musicPlaying = Wallhaven.dbusReplyAsString(status) === "Playing";
            }, function() {
                monitors.musicPlaying = false;
            });
        }, function() {
            monitors.musicPlaying = false;
        });
    }

    Timer {
        interval: 4000
        running: monitors.active && monitors.cfg.MusicReactiveEnabled
        repeat: true
        triggeredOnStart: true
        onTriggered: monitors.pollMusic()
    }

    // --- weather (adds a weather tag to searches)

    function fetchJson(url, onSuccess, onError) {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", url);
        xhr.setRequestHeader("Accept", "application/json");
        xhr.timeout = 10000;
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) {
                return;
            }
            if (xhr.status === 200) {
                try {
                    onSuccess(JSON.parse(xhr.responseText));
                } catch (e) {
                    onError();
                }
            } else {
                onError();
            }
        };
        xhr.onerror = function() { onError(); };
        xhr.ontimeout = function() { onError(); };
        xhr.send();
    }

    function refreshWeather() {
        if (!cfg.WeatherReactiveEnabled || !host.configuration) {
            return;
        }
        var location = String(cfg.WeatherLocation || "").trim();
        if (!location) {
            return;
        }
        if (location === monitors._weatherLastLocation && cfg.WeatherResolvedLat) {
            fetchWeather(cfg.WeatherResolvedLat, cfg.WeatherResolvedLon);
            return;
        }
        var direct = Wallhaven.parseLatLon(location);
        if (direct) {
            monitors._weatherLastLocation = location;
            host.configuration.WeatherResolvedLat = String(direct.lat);
            host.configuration.WeatherResolvedLon = String(direct.lon);
            host.scheduleConfigWrite();
            fetchWeather(direct.lat, direct.lon);
            return;
        }
        var geocodeUrl = "https://geocoding-api.open-meteo.com/v1/search?count=1&name="
            + encodeURIComponent(location);
        fetchJson(geocodeUrl, function(json) {
            var place = Wallhaven.parseGeocodeResponse(json);
            if (!place || !host.configuration) {
                return;
            }
            monitors._weatherLastLocation = location;
            host.configuration.WeatherResolvedLat = String(place.lat);
            host.configuration.WeatherResolvedLon = String(place.lon);
            host.scheduleConfigWrite();
            fetchWeather(place.lat, place.lon);
        }, function() {});
    }

    function fetchWeather(lat, lon) {
        var url = "https://api.open-meteo.com/v1/forecast?latitude=" + lat
            + "&longitude=" + lon + "&current_weather=true";
        fetchJson(url, function(json) {
            var current = Wallhaven.parseCurrentWeatherResponse(json);
            if (!current || !host.configuration) {
                return;
            }
            var tag = Wallhaven.mapWeatherCodeToTag(current.code);
            if (tag && tag !== cfg.WeatherTagCache) {
                host.configuration.WeatherTagCache = tag;
                host.scheduleConfigWrite();
                host.logDebug("Weather-reactive tag set to " + tag);
            }
        }, function() {});
    }

    Timer {
        interval: 1800000
        running: monitors.active && monitors.cfg.WeatherReactiveEnabled
        repeat: true
        triggeredOnStart: true
        onTriggered: monitors.refreshWeather()
    }
}

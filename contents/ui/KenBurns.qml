import QtQuick
import "../code/wallhaven.js" as Wallhaven

// Slow zoom-and-pan on the visible wallpaper layer. main.qml multiplies the
// bg*/fg* values into the two image layers' transforms.
Item {
    id: kenBurns

    required property var host   // wallpaper root (main.qml)
    readonly property var cfg: host.cfg

    property real bgScale: 1
    property real fgScale: 1
    property real bgX: 0
    property real bgY: 0
    property real fgX: 0
    property real fgY: 0

    function stopAll() {
        bgKenBurns.stop();
        fgKenBurns.stop();
        bgPanX.stop();
        fgPanX.stop();
        bgPanY.stop();
        fgPanY.stop();
    }

    function restart() {
        stopAll();
        if (!cfg.KenBurnsEnabled || !host.effectsMotionAllowed()) {
            bgScale = fgScale = 1;
            bgX = bgY = fgX = fgY = 0;
            return;
        }
        var panX = (Math.random() - 0.5) * host.width * 0.04;
        var panY = (Math.random() - 0.5) * host.height * 0.03;
        if (host.activeIsForeground) {
            fgScale = 1.06;
            fgX = panX;
            fgY = panY;
            fgKenBurns.from = 1.06;
            fgKenBurns.to = 1.14;
            fgPanX.from = panX;
            fgPanX.to = -panX;
            fgPanY.from = panY;
            fgPanY.to = -panY;
            fgKenBurns.start();
            fgPanX.start();
            fgPanY.start();
        } else {
            bgScale = 1.06;
            bgX = panX;
            bgY = panY;
            bgKenBurns.from = 1.06;
            bgKenBurns.to = 1.14;
            bgPanX.from = panX;
            bgPanX.to = -panX;
            bgPanY.from = panY;
            bgPanY.to = -panY;
            bgKenBurns.start();
            bgPanX.start();
            bgPanY.start();
        }
    }

    readonly property int kenBurnsDuration: {
        var duration;
        if (cfg.RandomInterval > 0) {
            duration = cfg.RandomInterval * 60 * 1000 * 0.9;
        } else {
            var speed = Math.max(1, Math.min(cfg.KenBurnsSpeed, 100));
            duration = 120000 - ((speed - 1) / 99) * 90000;
        }
        var multiplier = Wallhaven.musicReactiveSpeedMultiplier(
            cfg.MusicReactiveIntensity, cfg.MusicReactiveEnabled && host._musicPlaying);
        return Math.round(duration / multiplier);
    }

    NumberAnimation { id: bgKenBurns; target: kenBurns; property: "bgScale"; duration: kenBurns.kenBurnsDuration; easing.type: Easing.InOutSine }
    NumberAnimation { id: fgKenBurns; target: kenBurns; property: "fgScale"; duration: kenBurns.kenBurnsDuration; easing.type: Easing.InOutSine }
    NumberAnimation { id: bgPanX; target: kenBurns; property: "bgX"; duration: kenBurns.kenBurnsDuration; easing.type: Easing.InOutSine }
    NumberAnimation { id: fgPanX; target: kenBurns; property: "fgX"; duration: kenBurns.kenBurnsDuration; easing.type: Easing.InOutSine }
    NumberAnimation { id: bgPanY; target: kenBurns; property: "bgY"; duration: kenBurns.kenBurnsDuration; easing.type: Easing.InOutSine }
    NumberAnimation { id: fgPanY; target: kenBurns; property: "fgY"; duration: kenBurns.kenBurnsDuration; easing.type: Easing.InOutSine }
}

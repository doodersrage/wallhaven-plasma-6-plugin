import QtQuick
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import "../code/wallhaven.js" as Wallhaven

WallpaperItem {
    id: root

    readonly property var cfg: wallpaper.configuration

    property string currentUrl: ""
    property string statusMessage: ""
    property string statusType: "info"
    property bool statusVisible: false
    property string attributionText: ""
    property bool activeIsForeground: false

    property int _forwardClicks: 0
    property int _backClicks: 0
    property bool _configured: false

    QtObject {
        id: engine

        property var apiData: null
        property string randomSeed: Wallhaven.createRandomSeed()
        property int page: 1
        property int index: 0
        property int lastPage: 0
        property int total: 0
        property int totalShown: 0
        property var usedIndices: []
        property var seenIds: []
        property var history: []
        property int historyIndex: -1
        property string searchQuery: ""
        property string favoritesUser: ""
        property string favoritesId: ""
        property bool busy: false
        property string nextPreloadedUrl: ""

        function resetSlideshow() {
            randomSeed = Wallhaven.createRandomSeed();
            page = 1;
            index = 0;
            lastPage = 0;
            total = 0;
            totalShown = 0;
            usedIndices = [];
            history = [];
            historyIndex = -1;
            apiData = null;
            searchQuery = "";
            favoritesUser = "";
            favoritesId = "";
            nextWallpaper(false);
        }

        function configObject() {
            return {
                SearchText: cfg.SearchText,
                ApiKey: cfg.ApiKey,
                BrowseMode: cfg.BrowseMode,
                CollectionUser: cfg.CollectionUser,
                CollectionId: cfg.CollectionId,
                Sortings: cfg.Sortings,
                LocalSortings: cfg.LocalSortings,
                Order: cfg.Order,
                CategoryGeneral: cfg.CategoryGeneral,
                CategoryAnime: cfg.CategoryAnime,
                CategoryPeople: cfg.CategoryPeople,
                PuritySfw: cfg.PuritySfw,
                PuritySketchy: cfg.PuritySketchy,
                PurityNsfw: cfg.PurityNsfw,
                MinWidth: cfg.MinWidth,
                MinHeight: cfg.MinHeight,
                Ratio: cfg.Ratio,
                ColorFilter: cfg.ColorFilter,
                TopRange: cfg.TopRange,
                ExactResolutions: cfg.ExactResolutions,
                UseBlacklist: cfg.UseBlacklist,
                DedupEnabled: cfg.DedupEnabled,
                TimeOfDayEnabled: cfg.TimeOfDayEnabled,
                DaySearch: cfg.DaySearch,
                NightSearch: cfg.NightSearch,
            };
        }

        function stateObject() {
            return {
                page: page,
                index: index,
                seed: randomSeed,
                lastPage: lastPage,
                total: total,
                totalShown: totalShown,
                usedIndices: usedIndices,
                seenIds: seenIds,
                screenWidth: Math.round(root.width),
                screenHeight: Math.round(root.height),
                searchQuery: searchQuery,
                favoritesUser: favoritesUser,
                favoritesId: favoritesId,
            };
        }

        function showStatus(message, type, autoHide) {
            root.statusMessage = message;
            root.statusType = type || "info";
            root.statusVisible = message !== "";
            if (autoHide !== false && message !== "") {
                statusHideTimer.restart();
            }
        }

        function requestJson(url, onSuccess, onError) {
            var xhr = new XMLHttpRequest();
            xhr.open("GET", url);
            xhr.setRequestHeader("Accept", "application/json");
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE) {
                    return;
                }
                if (xhr.status === 200) {
                    onSuccess(JSON.parse(xhr.responseText));
                } else {
                    onError(xhr.status, xhr.statusText);
                }
            };
            xhr.send();
        }

        function buildBlacklistQuery(callback) {
            var config = configObject();
            var base = Wallhaven.getEffectiveSearchText(config);
            if (!config.UseBlacklist || !config.ApiKey) {
                searchQuery = base;
                callback();
                return;
            }
            requestJson(Wallhaven.buildSettingsUrl(config.ApiKey), function(json) {
                var blacklist = json.data && json.data.tag_blacklist ? json.data.tag_blacklist : [];
                var query = base;
                for (var i = 0; i < blacklist.length; i++) {
                    if (blacklist[i]) {
                        query += " -" + String(blacklist[i]).trim().replace(/\s+/g, "_");
                    }
                }
                searchQuery = query.trim();
                callback();
            }, function() {
                searchQuery = base;
                callback();
            });
        }

        function resolveFavorites(callback) {
            var config = configObject();
            if (!config.ApiKey) {
                showStatus("API key required for favorites mode.", "error");
                busy = false;
                return;
            }
            requestJson(Wallhaven.buildCollectionsUrl(config.ApiKey), function(json) {
                var favorite = null;
                if (json.data && json.data.length) {
                    for (var i = 0; i < json.data.length; i++) {
                        if (json.data[i].label && json.data[i].label.toLowerCase() === "favorites") {
                            favorite = json.data[i];
                            break;
                        }
                    }
                    if (!favorite) {
                        favorite = json.data[0];
                    }
                }
                if (!favorite) {
                    showStatus("No favorites collection found.", "error");
                    busy = false;
                    return;
                }
                favoritesUser = config.CollectionUser
                    || favorite.username
                    || (favorite.user && favorite.user.username)
                    || favorite.user
                    || "";
                favoritesId = String(favorite.id);
                callback();
            }, function(status) {
                showStatus("Failed to load favorites (" + status + ").", "error");
                busy = false;
            });
        }

        function fetchApiData(onDone) {
            var config = configObject();

            function doFetch() {
                var url;
                if (config.BrowseMode === "collection") {
                    if (!config.CollectionUser || !config.CollectionId) {
                        showStatus("Collection username and ID are required.", "error");
                        busy = false;
                        return;
                    }
                    url = Wallhaven.buildCollectionUrl(config, stateObject());
                } else if (config.BrowseMode === "favorites") {
                    url = Wallhaven.buildCollectionUrl(config, stateObject());
                } else {
                    url = Wallhaven.buildSearchUrl(config, stateObject());
                }

                requestJson(url, function(json) {
                    if (!json.data || !json.data.length) {
                        showStatus("No wallpapers match your current filters.", "warn");
                        busy = false;
                        onDone(null);
                        return;
                    }
                    apiData = json;
                    lastPage = json.meta.last_page;
                    total = json.meta.total;
                    onDone(json);
                }, function(status) {
                    showStatus("Wallhaven request failed (" + status + "). Retrying…", "error");
                    retryTimer.start();
                    busy = false;
                    onDone(null);
                });
            }

            if (config.BrowseMode === "favorites" && !favoritesId) {
                resolveFavorites(doFetch);
                return;
            }
            if (config.BrowseMode === "search") {
                buildBlacklistQuery(doFetch);
                return;
            }
            doFetch();
        }

        function markSeen(id) {
            if (!cfg.DedupEnabled || !id) {
                return;
            }
            var idStr = String(id);
            if (seenIds.indexOf(idStr) === -1) {
                seenIds.push(idStr);
                if (seenIds.length > 500) {
                    seenIds = seenIds.slice(-500);
                }
            }
        }

        function updateAttribution(wallpaper) {
            if (!cfg.ShowAttribution || !wallpaper) {
                root.attributionText = "";
                return;
            }
            var resolution = wallpaper.resolution || (wallpaper.dimension_x + "x" + wallpaper.dimension_y);
            var link = wallpaper.url || ("https://wallhaven.cc/w/" + wallpaper.id);
            root.attributionText = "Wallhaven #" + wallpaper.id + "\n"
                + resolution + " · " + wallpaper.category + " · " + wallpaper.purity + "\n"
                + link;

            requestJson(Wallhaven.buildWallpaperUrl(wallpaper.id, cfg.ApiKey), function(json) {
                if (!json.data) {
                    return;
                }
                var tags = Wallhaven.formatTags(json.data.tags);
                if (tags) {
                    root.attributionText = "Wallhaven #" + wallpaper.id + "\n"
                        + resolution + " · " + wallpaper.category + " · " + wallpaper.purity + "\n"
                        + tags + "\n" + link;
                }
            }, function() {});
        }

        function displayWallpaper(wallpaper, url, immediate) {
            if (!url) {
                return;
            }
            root.showImage(url, immediate);
            root.currentUrl = url;
            updateAttribution(wallpaper);
            kenBurnsAnimation.restart();
        }

        function pushHistory(entry) {
            history = history.slice(0, historyIndex + 1);
            history.push(entry);
            if (history.length > 50) {
                history.shift();
                historyIndex--;
            }
            historyIndex = history.length - 1;
        }

        function preloadUrl(url) {
            if (!url || url === nextPreloadedUrl) {
                return;
            }
            nextPreloadedUrl = url;
            preloadImage.source = url;
        }

        function preloadNext() {
            if (!apiData || !apiData.data || !apiData.data.length) {
                return;
            }
            var dryState = stateObject();
            var wallpaper = Wallhaven.advanceIndex(configObject(), dryState, apiData.data, true);
            preloadUrl(Wallhaven.wallpaperUrl(wallpaper, cfg.ImageQuality));
        }

        function nextWallpaper(fromHistory) {
            if (busy) {
                return;
            }
            busy = true;

            function finish(wallpaper, url) {
                if (!wallpaper || !url) {
                    busy = false;
                    return;
                }
                markSeen(wallpaper.id);
                if (!fromHistory) {
                    pushHistory({
                        wallpaper: wallpaper,
                        url: url,
                        index: index,
                        page: page,
                    });
                }
                displayWallpaper(wallpaper, url, false);
                preloadNext();
                busy = false;
                root.statusVisible = false;
            }

            function processData(data) {
                if (!data) {
                    return;
                }
                var wallpaper = Wallhaven.advanceIndex(configObject(), engine, data.data, false);
                Wallhaven.updatePageState(configObject(), engine);
                totalShown++;
                var url = Wallhaven.wallpaperUrl(wallpaper, cfg.ImageQuality);
                finish(wallpaper, url);
            }

            if (apiData && apiData.data && apiData.data.length) {
                processData(apiData);
                return;
            }
            fetchApiData(processData);
        }

        function previousWallpaper() {
            if (historyIndex <= 0) {
                showStatus("No previous wallpaper in history.", "info");
                return;
            }
            historyIndex--;
            var entry = history[historyIndex];
            index = entry.index;
            page = entry.page;
            displayWallpaper(entry.wallpaper, entry.url, true);
        }
    }

    function showImage(url, immediate) {
        if (!url) {
            return;
        }

        var crossfade = cfg.CrossfadeMs > 0 && !immediate && currentUrl !== "";

        if (crossfade) {
            if (activeIsForeground) {
                backgroundImage.source = url;
                crossfadeToBackground.start();
            } else {
                foregroundImage.source = url;
                crossfadeToForeground.start();
            }
            return;
        }

        backgroundImage.source = url;
        foregroundImage.opacity = 0;
        activeIsForeground = false;
    }

    Image {
        id: backgroundImage
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        transformOrigin: Item.Center
        scale: kenBurnsAnimation.bgScale
        x: kenBurnsAnimation.bgX
        y: kenBurnsAnimation.bgY
    }

    Image {
        id: foregroundImage
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        opacity: 0
        transformOrigin: Item.Center
        scale: kenBurnsAnimation.fgScale
        x: kenBurnsAnimation.fgX
        y: kenBurnsAnimation.fgY
    }

    Image {
        id: preloadImage
        visible: false
        width: 1
        height: 1
    }

    ParallelAnimation {
        id: crossfadeToForeground
        NumberAnimation { target: foregroundImage; property: "opacity"; to: 1; duration: cfg.CrossfadeMs }
        NumberAnimation { target: backgroundImage; property: "opacity"; to: 0; duration: cfg.CrossfadeMs }
        onStarted: activeIsForeground = true
    }

    ParallelAnimation {
        id: crossfadeToBackground
        NumberAnimation { target: backgroundImage; property: "opacity"; to: 1; duration: cfg.CrossfadeMs }
        NumberAnimation { target: foregroundImage; property: "opacity"; to: 0; duration: cfg.CrossfadeMs }
        onStarted: activeIsForeground = false
    }

    QtObject {
        id: kenBurnsAnimation
        property real bgScale: 1
        property real fgScale: 1
        property real bgX: 0
        property real bgY: 0
        property real fgX: 0
        property real fgY: 0

        function restart() {
            if (!cfg.KenBurnsEnabled) {
                bgScale = fgScale = 1;
                bgX = bgY = fgX = fgY = 0;
                return;
            }
            var panX = (Math.random() - 0.5) * root.width * 0.04;
            var panY = (Math.random() - 0.5) * root.height * 0.03;
            if (activeIsForeground) {
                fgScale = 1.06; fgX = panX; fgY = panY;
                fgKenBurns.from = 1.06; fgKenBurns.to = 1.14;
                fgPanX.from = panX; fgPanX.to = -panX;
                fgPanY.from = panY; fgPanY.to = -panY;
                fgKenBurns.start(); fgPanX.start(); fgPanY.start();
            } else {
                bgScale = 1.06; bgX = panX; bgY = panY;
                bgKenBurns.from = 1.06; bgKenBurns.to = 1.14;
                bgPanX.from = panX; bgPanX.to = -panX;
                bgPanY.from = panY; bgPanY.to = -panY;
                bgKenBurns.start(); bgPanX.start(); bgPanY.start();
            }
        }
    }

    property int kenBurnsDuration: {
        if (cfg.RandomInterval > 0) {
            return cfg.RandomInterval * 60 * 1000 * 0.9;
        }
        var speed = Math.max(1, Math.min(cfg.KenBurnsSpeed, 100));
        return 120000 - ((speed - 1) / 99) * 90000;
    }

    NumberAnimation { id: bgKenBurns; target: kenBurnsAnimation; property: "bgScale"; duration: root.kenBurnsDuration; easing.type: Easing.InOutSine }
    NumberAnimation { id: fgKenBurns; target: kenBurnsAnimation; property: "fgScale"; duration: root.kenBurnsDuration; easing.type: Easing.InOutSine }
    NumberAnimation { id: bgPanX; target: kenBurnsAnimation; property: "bgX"; duration: root.kenBurnsDuration; easing.type: Easing.InOutSine }
    NumberAnimation { id: fgPanX; target: kenBurnsAnimation; property: "fgX"; duration: root.kenBurnsDuration; easing.type: Easing.InOutSine }
    NumberAnimation { id: bgPanY; target: kenBurnsAnimation; property: "bgY"; duration: root.kenBurnsDuration; easing.type: Easing.InOutSine }
    NumberAnimation { id: fgPanY; target: kenBurnsAnimation; property: "fgY"; duration: root.kenBurnsDuration; easing.type: Easing.InOutSine }

    Timer {
        id: intervalTimer
        interval: Math.max(cfg.RandomInterval, 0) * 60 * 1000
        running: cfg.RandomInterval > 0
        repeat: true
        onTriggered: engine.nextWallpaper(false)
    }

    Timer {
        id: retryTimer
        interval: 60000
        repeat: false
        onTriggered: engine.nextWallpaper(false)
    }

    Timer {
        id: statusHideTimer
        interval: 5000
        repeat: false
        onTriggered: root.statusVisible = false
    }

    Timer {
        id: timeOfDayTimer
        interval: 60000
        running: cfg.TimeOfDayEnabled
        repeat: true
        onTriggered: engine.resetSlideshow()
    }

    Timer {
        id: clickResetTimer
        interval: 300
        repeat: false
        onTriggered: {
            root._forwardClicks = 0;
            root._backClicks = 0;
        }
    }

    MouseArea {
        anchors.fill: parent
        z: 1
        acceptedButtons: Qt.LeftButton
        propagateComposedEvents: true
        onClicked: function(mouse) {
            clickResetTimer.restart();
            if (mouse.x < root.width * 0.5 && cfg.ClicksToGoBack > 0) {
                root._backClicks++;
                root._forwardClicks = 0;
                if (root._backClicks >= cfg.ClicksToGoBack) {
                    root._backClicks = 0;
                    engine.previousWallpaper();
                }
            } else {
                root._forwardClicks++;
                root._backClicks = 0;
                if (root._forwardClicks >= cfg.ClicksToAdvance) {
                    root._forwardClicks = 0;
                    engine.nextWallpaper(false);
                }
            }
            mouse.accepted = false;
        }
    }

    Rectangle {
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 16
        width: Math.min(statusLabel.width + 24, parent.width - 32)
        height: statusLabel.height + 16
        radius: 8
        visible: root.statusVisible
        color: root.statusType === "error" ? "#cc1e1e"
             : root.statusType === "warn" ? "#785014"
             : "#1e3c64"
        opacity: 0.9

        QQC2.Label {
            id: statusLabel
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.parent.width - 56)
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            color: "white"
            text: root.statusMessage
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 16
        width: Math.min(attributionLabel.width + 24, parent.width - 32)
        height: attributionLabel.height + 16
        radius: 8
        visible: cfg.ShowAttribution && root.attributionText !== ""
        color: "#000000"
        opacity: 0.55

        QQC2.Label {
            id: attributionLabel
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.parent.width - 56)
            wrapMode: Text.WordWrap
            color: "#ffffff"
            font.pointSize: 9
            text: root.attributionText
        }
    }

    Connections {
        target: wallpaper.configuration
        function onSearchTextChanged() { if (root._configured) engine.resetSlideshow(); }
        function onApiKeyChanged() { if (root._configured) engine.resetSlideshow(); }
        function onBrowseModeChanged() { if (root._configured) engine.resetSlideshow(); }
        function onCollectionUserChanged() { if (root._configured) engine.resetSlideshow(); }
        function onCollectionIdChanged() { if (root._configured) engine.resetSlideshow(); }
        function onSortingsChanged() { if (root._configured) engine.resetSlideshow(); }
        function onLocalSortingsChanged() { if (root._configured) engine.resetSlideshow(); }
        function onOrderChanged() { if (root._configured) engine.resetSlideshow(); }
        function onCategoryGeneralChanged() { if (root._configured) engine.resetSlideshow(); }
        function onCategoryAnimeChanged() { if (root._configured) engine.resetSlideshow(); }
        function onCategoryPeopleChanged() { if (root._configured) engine.resetSlideshow(); }
        function onPuritySfwChanged() { if (root._configured) engine.resetSlideshow(); }
        function onPuritySketchyChanged() { if (root._configured) engine.resetSlideshow(); }
        function onPurityNsfwChanged() { if (root._configured) engine.resetSlideshow(); }
        function onMinWidthChanged() { if (root._configured) engine.resetSlideshow(); }
        function onMinHeightChanged() { if (root._configured) engine.resetSlideshow(); }
        function onRatioChanged() { if (root._configured) engine.resetSlideshow(); }
        function onColorFilterChanged() { if (root._configured) engine.resetSlideshow(); }
        function onTopRangeChanged() { if (root._configured) engine.resetSlideshow(); }
        function onExactResolutionsChanged() { if (root._configured) engine.resetSlideshow(); }
        function onUseBlacklistChanged() { if (root._configured) engine.resetSlideshow(); }
        function onDaySearchChanged() { if (root._configured) engine.resetSlideshow(); }
        function onNightSearchChanged() { if (root._configured) engine.resetSlideshow(); }
        function onTimeOfDayEnabledChanged() { if (root._configured) engine.resetSlideshow(); }
        function onImageQualityChanged() { if (root._configured) engine.resetSlideshow(); }
    }

    Component.onCompleted: {
        engine.nextWallpaper(false);
        root._configured = true;
    }
}

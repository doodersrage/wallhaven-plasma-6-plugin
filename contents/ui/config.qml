import "../code/wallhaven.js" as Wallhaven
import QtQuick
import QtQuick.Controls as QtControls2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.workspace.dbus as PDBus

ColumnLayout {
    // Keep PreviewImage / attribution keys; they are runtime state for the settings preview.

    id: root

    property var wallpaperConfiguration
    property alias formLayout: sourceForm
    readonly property var liveWallpaper: (typeof Plasmoid !== "undefined" && Plasmoid.wallpaperGraphicsObject) ? Plasmoid.wallpaperGraphicsObject : null
    readonly property string previewAttribution: {
        if (wallpaperConfiguration && wallpaperConfiguration.PreviewAttribution)
            return wallpaperConfiguration.PreviewAttribution;

        if (liveWallpaper && liveWallpaper.attributionText)
            return liveWallpaper.attributionText;

        return "";
    }
    readonly property string previewWallpaperId: {
        if (wallpaperConfiguration && wallpaperConfiguration.PreviewWallpaperId)
            return wallpaperConfiguration.PreviewWallpaperId;

        var match = /Wallhaven #([a-z0-9]+)/i.exec(previewAttribution);
        return match ? match[1] : "";
    }
    readonly property string previewThumbUrl: {
        if (previewWallpaperId)
            return Wallhaven.thumbUrlForId(previewWallpaperId);

        if (wallpaperConfiguration && wallpaperConfiguration.PreviewThumbUrl)
            return wallpaperConfiguration.PreviewThumbUrl;

        return "";
    }
    readonly property string previewFileUrl: {
        if (!wallpaperConfiguration)
            return "";

        var value = wallpaperConfiguration.PreviewImage;
        if (!value || value === "null")
            return "";

        return value;
    }
    readonly property string previewWallpaperDetails: {
        if (liveWallpaper && liveWallpaper.wallpaperDetailsText)
            return liveWallpaper.wallpaperDetailsText;

        if (wallpaperConfiguration && wallpaperConfiguration.PreviewWallpaperDetails)
            return wallpaperConfiguration.PreviewWallpaperDetails;

        return "";
    }
    readonly property real previewWidth: Math.min(420, Math.max(280, width > 0 ? Math.round(width * 0.55) : 360))
    readonly property real previewHeight: Math.round(previewWidth * 9 / 16)
    property alias cfg_SearchText: searchTextField.text
    property alias cfg_ApiKey: apiKeyField.text
    property alias cfg_BrowseMode: browseModeCombo.currentValue
    property alias cfg_CollectionUser: collectionUserField.text
    property alias cfg_CollectionId: collectionIdField.text
    property alias cfg_RandomInterval: intervalSpin.value
    property alias cfg_SlideshowPaused: slideshowPausedCheck.checked
    property alias cfg_IntervalJitterPercent: jitterSpin.value
    property alias cfg_DayIntervalMin: dayIntervalSpin.value
    property alias cfg_NightIntervalMin: nightIntervalSpin.value
    property alias cfg_CrossfadeMs: crossfadeSpin.value
    property alias cfg_TransitionMode: transitionCombo.currentValue
    property alias cfg_ImageQuality: qualityCombo.currentValue
    property alias cfg_FileTypeFilter: fileTypeCombo.currentValue
    property alias cfg_Sortings: sortingsCombo.currentValue
    property alias cfg_LocalSortings: localSortingsCombo.currentValue
    property alias cfg_Order: orderCombo.currentValue
    property alias cfg_CategoryGeneral: generalCheck.checked
    property alias cfg_CategoryAnime: animeCheck.checked
    property alias cfg_CategoryPeople: peopleCheck.checked
    property alias cfg_PuritySfw: sfwCheck.checked
    property alias cfg_PuritySketchy: sketchyCheck.checked
    property alias cfg_PurityNsfw: nsfwCheck.checked
    property alias cfg_MinWidth: minWidthField.text
    property alias cfg_MinHeight: minHeightField.text
    property alias cfg_Ratio: ratioCombo.currentValue
    property alias cfg_ColorFilter: colorCombo.currentValue
    property alias cfg_TopRange: topRangeCombo.currentValue
    property alias cfg_ExactResolutions: resolutionsField.text
    property alias cfg_UseBlacklist: blacklistCheck.checked
    property alias cfg_DedupEnabled: dedupCheck.checked
    property alias cfg_PreferSharpMatches: preferSharpMatchesCheck.checked
    property alias cfg_KenBurnsEnabled: kenBurnsCheck.checked
    property alias cfg_KenBurnsSpeed: kenBurnsSpeedSpin.value
    property alias cfg_ImageEnhanceEnabled: imageEnhanceCheck.checked
    property alias cfg_EnhanceBrightness: enhanceBrightnessSpin.value
    property alias cfg_EnhanceContrast: enhanceContrastSpin.value
    property alias cfg_EnhanceSaturation: enhanceSaturationSpin.value
    property alias cfg_ShowAttribution: attributionCheck.checked
    property alias cfg_AttributionCorner: attributionCornerCombo.currentValue
    property alias cfg_AttributionAutoHideSec: attributionHideSpin.value
    property alias cfg_AttributionFontScale: attributionScaleSpin.value
    property alias cfg_RequestTimeoutSec: requestTimeoutSpin.value
    property alias cfg_RetryDelaySec: retryDelaySpin.value
    property alias cfg_RetryAttempts: retryAttemptsSpin.value
    property alias cfg_NotifyOnRefresh: notifyRefreshCheck.checked
    property alias cfg_NotifyOnError: notifyErrorCheck.checked
    property alias cfg_ShowStatusBanner: statusBannerCheck.checked
    property alias cfg_DiskCacheEnabled: diskCacheCheck.checked
    property alias cfg_DiskCacheMaxSlots: diskCacheSlotsSpin.value
    property alias cfg_OfflineCacheFallback: offlineCacheCheck.checked
    property alias cfg_OfflineOnlyMode: offlineOnlyCheck.checked
    property alias cfg_MeteredCacheOnly: meteredCacheCheck.checked
    property alias cfg_UpscaleEnabled: upscaleCheck.checked
    property alias cfg_CacheDownloadOriginal: cacheDownloadOriginalCheck.checked
    property alias cfg_PauseOnIdleEnabled: pauseIdleCheck.checked
    property alias cfg_IdlePauseMinutes: idlePauseMinutesSpin.value
    property alias cfg_SyncProfilesEnabled: syncProfilesCheck.checked
    property string cfg_SyncProfilesJson
    property alias cfg_PanelBlurStrength: panelBlurStrengthSpin.value
    property alias cfg_SettingsFilterHint: settingsSearchField.text
    property string cfg_WallpaperHistoryJson
    property string cfg_TagBlocklistJson
    property string cfg_TagFavoritesJson
    property string cfg_CollectionRotationJson
    property string cfg_TimeCapsulesJson
    property string cfg_SearchPresetsJson
    property alias cfg_UseKWalletForApiKey: kwalletCheck.checked
    property alias cfg_ControlBusEnabled: controlBusCheck.checked
    property alias cfg_SyncAdvanceEnabled: syncAdvanceCheck.checked
    property alias cfg_SyncAdvanceGroup: syncGroupField.text
    property alias cfg_VarietyMetadataEnabled: varietyCheck.checked
    property alias cfg_TimeOfDayEnabled: timeOfDayCheck.checked
    property alias cfg_DaySearch: daySearchField.text
    property alias cfg_NightSearch: nightSearchField.text
    property alias cfg_ScheduleEnabled: scheduleCheck.checked
    property alias cfg_WeekdaySearch: weekdaySearchField.text
    property alias cfg_WeekendSearch: weekendSearchField.text
    property alias cfg_CollectionRotationEnabled: collectionRotationCheck.checked
    property alias cfg_SyncLockScreen: lockScreenCheck.checked
    property alias cfg_PanelTintEnabled: panelTintCheck.checked
    property alias cfg_ParallaxEnabled: parallaxCheck.checked
    property alias cfg_ParallaxStrength: parallaxStrengthSpin.value
    property alias cfg_VarietyFolderPath: varietyFolderField.text
    property alias cfg_VarietySymlinkEnabled: varietySymlinkCheck.checked
    property alias cfg_VarietyWatchEnabled: varietyWatchCheck.checked
    property alias cfg_SetupWizardCompleted: setupWizardCompletedFlag.value
    property alias cfg_WallpaperOfDayEnabled: wallpaperOfDayCheck.checked
    property alias cfg_FavoritesRefreshMin: favoritesRefreshSpin.value
    property alias cfg_DebugLogEnabled: debugLogCheck.checked
    property alias cfg_AdaptivePreloadEnabled: adaptivePreloadCheck.checked
    property alias cfg_PreloadCount: preloadCountSpin.value
    property alias cfg_AutoPanelAccentEnabled: autoPanelAccentCheck.checked
    property alias cfg_PauseOnBatteryLow: pauseBatteryCheck.checked
    property alias cfg_BatteryLowThreshold: batteryThresholdSpin.value
    property alias cfg_PauseWhenInactive: pauseInactiveCheck.checked
    property alias cfg_SmartColorFromWallpaper: smartColorCheck.checked
    property alias cfg_MusicReactiveEnabled: musicReactiveCheck.checked
    property alias cfg_MusicReactiveIntensity: musicReactiveIntensitySpin.value
    property alias cfg_WeatherReactiveEnabled: weatherReactiveCheck.checked
    property alias cfg_WeatherLocation: weatherLocationField.text
    property alias cfg_AchievementsEnabled: achievementsCheck.checked
    property alias cfg_SystemThemeSyncEnabled: systemThemeSyncCheck.checked
    property string settingsFilter: ""
    readonly property var settingsFilterKeywords: [
        "search", "filter", "settings", "source", "tags", "query", "cache", "variety",
        "dbus", "slideshow", "blocklist", "preset", "history", "sync", "shortcut",
        "debug", "import", "export", "favorites", "collection", "interval", "transition",
        "attribution", "ken", "parallax", "panel", "battery", "offline", "kwallet",
        "toplist", "wotd", "refresh", "playback", "advanced", "similar", "quality",
        "music", "weather", "achievement", "streak", "milestone", "theme", "capsule",
        "swipe", "like", "dislike",
    ]
    property bool showSetupWizard: wallpaperConfiguration && !wallpaperConfiguration.SetupWizardCompleted
    property bool dbusPollCompleted: false
    property bool dbusPolledOnline: false
    property bool upscalerPollCompleted: false
    property string upscalerPolledPath: ""
    readonly property bool dbusServiceOnline: dbusPolledOnline
        || !!(liveWallpaper && liveWallpaper.dbusServiceAvailable)
    readonly property bool upscalerStatusKnown: upscalerPollCompleted
        || !!(liveWallpaper && liveWallpaper.upscalerStatusKnown)
    readonly property bool upscalerAvailable: (upscalerPollCompleted && upscalerPolledPath !== "")
        || !!(liveWallpaper && liveWallpaper.upscalerAvailable)
    property string varietyPreviewSearch: ""

    function fieldVisible(keywords) {
        if (!settingsFilter || !keywords || !keywords.length)
            return true;

        var needle = settingsFilter.toLowerCase();
        for (var i = 0; i < keywords.length; i++) {
            if (String(keywords[i]).toLowerCase().indexOf(needle) >= 0)
                return true;

        }
        return false;
    }

    function settingsFilterMatchesAny() {
        if (!settingsFilter)
            return true;

        var needle = settingsFilter.toLowerCase();
        for (var i = 0; i < settingsFilterKeywords.length; i++) {
            if (String(settingsFilterKeywords[i]).toLowerCase().indexOf(needle) >= 0)
                return true;
        }
        return false;
    }

    function importBundledPresets(presets, emptyMessage, successMessage) {
        if (!presets || !presets.length) {
            importExportStatus.text = emptyMessage;
            return;
        }

        var merged = Wallhaven.mergePresetLists(currentPresets(), presets);
        persistPresets(merged);
        if (presets[0] && presets[0].name) {
            for (var i = 0; i < merged.length; i++) {
                if (merged[i].name === presets[0].name) {
                    presetCombo.currentIndex = i;
                    break;
                }
            }
        }
        importExportStatus.text = successMessage;
    }

    function importCuratedPresets() {
        var curated = Wallhaven.bundledCuratedPresets();
        importBundledPresets(curated, i18n("Could not load curated presets."),
            i18n("Imported %1 curated preset(s).", curated.length));
    }

    function importCommunityPresets() {
        var community = Wallhaven.bundledCommunityPresets();
        importBundledPresets(community, i18n("Could not load community presets."),
            i18n("Imported %1 community preset(s).", community.length));
    }

    function importPresetFromUrlField() {
        if (!presetUrlField.text.trim())
            return ;

        if (liveWallpaper && liveWallpaper.importPresetFromUrl) {
            liveWallpaper.importPresetFromUrl(presetUrlField.text.trim());
            importExportStatus.text = i18n("Sent preset import request.");
        }
    }

    function resetSetupWizard() {
        if (!wallpaperConfiguration)
            return ;

        wallpaperConfiguration.SetupWizardCompleted = false;
        if (wallpaperConfiguration.writeConfig)
            wallpaperConfiguration.writeConfig();

        setupWizardCompletedFlag.value = false;
    }

    function shareSelectedPresetUrl() {
        var presets = currentPresets();
        if (presetCombo.currentIndex < 0 || presetCombo.currentIndex >= presets.length)
            return ;

        var url = Wallhaven.buildPresetShareUrl(presets[presetCombo.currentIndex]);
        settingsClipboardHelper.text = url;
        settingsClipboardHelper.selectAll();
        settingsClipboardHelper.copy();
        importExportStatus.text = i18n("Preset share URL copied.");
    }

    function finishSetupWizard() {
        if (!wallpaperConfiguration)
            return ;

        wallpaperConfiguration.SetupWizardCompleted = true;
        if (wallpaperConfiguration.writeConfig)
            wallpaperConfiguration.writeConfig();

        setupWizardCompletedFlag.value = true;
    }

    function refreshCacheModel() {
        cacheModel.clear();
        if (!liveWallpaper || !liveWallpaper.getCacheEntries)
            return ;

        var entries = liveWallpaper.getCacheEntries();
        for (var i = 0; i < entries.length; i++) {
            cacheModel.append(entries[i]);
        }
    }

    function tagBlocklistText() {
        return Wallhaven.parseTagBlocklist(cfg_TagBlocklistJson || "[]").join(", ");
    }

    function persistTagBlocklist(text) {
        var tags = String(text || "").split(",").map(function(tag) {
            return tag.trim();
        }).filter(function(tag) {
            return tag.length > 0;
        });
        cfg_TagBlocklistJson = Wallhaven.serializeTagBlocklist(tags);
    }

    function collectionRotationText() {
        return Wallhaven.formatCollectionRotationLines(Wallhaven.parseCollectionRotation(cfg_CollectionRotationJson || "[]"));
    }

    function persistCollectionRotation(text) {
        var entries = Wallhaven.parseCollectionRotationLines(text);
        cfg_CollectionRotationJson = Wallhaven.serializeCollectionRotation(entries);
    }

    function timeCapsuleText() {
        return Wallhaven.formatTimeCapsuleLines(Wallhaven.parseTimeCapsules(cfg_TimeCapsulesJson || "[]"));
    }

    function persistTimeCapsules(text) {
        var entries = Wallhaven.parseTimeCapsuleLines(text);
        cfg_TimeCapsulesJson = Wallhaven.serializeTimeCapsules(entries);
    }

    function favoriteTagsText() {
        return Wallhaven.parseTagFavorites(cfg_TagFavoritesJson || "[]").join(", ");
    }

    function persistFavoriteTags(text) {
        var tags = String(text || "").split(",").map(function(t) {
            return t.trim();
        }).filter(function(t) {
            return t;
        });
        cfg_TagFavoritesJson = Wallhaven.serializeTagBlocklist(tags);
    }

    function currentHistoryEntries() {
        if (liveWallpaper && liveWallpaper.wallpaperHistoryEntries && liveWallpaper.wallpaperHistoryEntries.length)
            return liveWallpaper.wallpaperHistoryEntries;

        if (liveWallpaper && liveWallpaper.getWallpaperHistory) {
            var live = liveWallpaper.getWallpaperHistory();
            if (live && live.length)
                return live;

        }
        var raw = cfg_WallpaperHistoryJson || "";
        if (!raw && wallpaperConfiguration)
            raw = wallpaperConfiguration.WallpaperHistoryJson || "";

        return Wallhaven.parseWallpaperHistory(raw || "[]");
    }

    function refreshHistoryModel() {
        var entries = currentHistoryEntries();
        historyModel.clear();
        for (var i = entries.length - 1; i >= 0; i--) {
            historyModel.append({
                id: String(entries[i].id || ""),
                thumbUrl: String(entries[i].thumbUrl || Wallhaven.thumbUrlForId(entries[i].id)),
                ts: Number(entries[i].ts) || 0,
            });
        }
    }

    function saveConfig() {
    }

    function currentPresets() {
        return Wallhaven.parseSearchPresets(cfg_SearchPresetsJson || "[]");
    }

    function setComboValue(combo, value) {
        if (!combo || value === undefined || value === null)
            return;

        var model = combo.model;
        if (!model)
            return;

        for (var i = 0; i < model.length; i++) {
            if (model[i] && model[i].value === value) {
                combo.currentIndex = i;
                return;
            }
        }
    }

    function applySearchPreset(preset) {
        if (!preset || !wallpaperConfiguration)
            return;

        var normalized = Wallhaven.normalizeSearchPreset(preset);
        Wallhaven.applyPresetToConfig(preset, wallpaperConfiguration);
        if (normalized.SearchText !== undefined)
            searchTextField.text = normalized.SearchText;

        root.setComboValue(sortingsCombo, normalized.Sortings);
        root.setComboValue(orderCombo, normalized.Order);
        root.setComboValue(topRangeCombo, normalized.TopRange);
        root.setComboValue(ratioCombo, normalized.Ratio);
        root.setComboValue(colorCombo, normalized.ColorFilter);
        if (normalized.CategoryGeneral !== undefined)
            generalCheck.checked = normalized.CategoryGeneral;

        if (normalized.CategoryAnime !== undefined)
            animeCheck.checked = normalized.CategoryAnime;

        if (normalized.CategoryPeople !== undefined)
            peopleCheck.checked = normalized.CategoryPeople;

        if (normalized.PuritySfw !== undefined)
            sfwCheck.checked = normalized.PuritySfw;

        if (normalized.PuritySketchy !== undefined)
            sketchyCheck.checked = normalized.PuritySketchy;

        if (normalized.PurityNsfw !== undefined)
            nsfwCheck.checked = normalized.PurityNsfw;

        if (normalized.MinWidth !== undefined)
            minWidthField.text = normalized.MinWidth;

        if (normalized.MinHeight !== undefined)
            minHeightField.text = normalized.MinHeight;

        if (normalized.ExactResolutions !== undefined)
            resolutionsField.text = normalized.ExactResolutions;

        if (normalized.UseBlacklist !== undefined)
            blacklistCheck.checked = normalized.UseBlacklist;

        if (normalized.TimeOfDayEnabled !== undefined)
            timeOfDayCheck.checked = normalized.TimeOfDayEnabled;

        if (normalized.DaySearch !== undefined)
            daySearchField.text = normalized.DaySearch;

        if (normalized.NightSearch !== undefined)
            nightSearchField.text = normalized.NightSearch;

        if (wallpaperConfiguration.writeConfig)
            wallpaperConfiguration.writeConfig();

        if (liveWallpaper && liveWallpaper.reloadWallpaper)
            liveWallpaper.reloadWallpaper();

    }

    function persistPresets(presets) {
        cfg_SearchPresetsJson = Wallhaven.serializeSearchPresets(presets || []);
        presetCombo.model = presets || [];
    }

    function buildCurrentConfigObject() {
        return Wallhaven.buildPresetSnapshotFromCfg({
            SearchText: cfg_SearchText,
            BrowseMode: cfg_BrowseMode,
            CollectionUser: cfg_CollectionUser,
            CollectionId: cfg_CollectionId,
            Sortings: cfg_Sortings,
            LocalSortings: cfg_LocalSortings,
            Order: cfg_Order,
            TopRange: cfg_TopRange,
            CategoryGeneral: cfg_CategoryGeneral,
            CategoryAnime: cfg_CategoryAnime,
            CategoryPeople: cfg_CategoryPeople,
            PuritySfw: cfg_PuritySfw,
            PuritySketchy: cfg_PuritySketchy,
            PurityNsfw: cfg_PurityNsfw,
            MinWidth: cfg_MinWidth,
            MinHeight: cfg_MinHeight,
            Ratio: cfg_Ratio,
            ColorFilter: cfg_ColorFilter,
            ExactResolutions: cfg_ExactResolutions,
            UseBlacklist: cfg_UseBlacklist,
            DedupEnabled: cfg_DedupEnabled,
            PreferSharpMatches: cfg_PreferSharpMatches,
            FileTypeFilter: cfg_FileTypeFilter,
            TagBlocklistJson: cfg_TagBlocklistJson,
            TagFavoritesJson: cfg_TagFavoritesJson,
            TimeOfDayEnabled: cfg_TimeOfDayEnabled,
            DaySearch: cfg_DaySearch,
            NightSearch: cfg_NightSearch,
            ScheduleEnabled: cfg_ScheduleEnabled,
            WeekdaySearch: cfg_WeekdaySearch,
            WeekendSearch: cfg_WeekendSearch,
            WallpaperOfDayEnabled: cfg_WallpaperOfDayEnabled,
        });
    }

    function exportSettingsToClipboard() {
        if (!wallpaperConfiguration)
            return ;

        var json = Wallhaven.exportSettingsSnapshot(wallpaperConfiguration);
        settingsClipboardHelper.text = json;
        settingsClipboardHelper.selectAll();
        settingsClipboardHelper.copy();
        importExportStatus.text = i18n("Settings copied to clipboard as JSON.");
    }

    function importSettingsFromText(raw) {
        if (!wallpaperConfiguration)
            return ;

        try {
            var settings = Wallhaven.importSettingsSnapshot(raw);
            var keys = Object.keys(settings);
            for (var i = 0; i < keys.length; i++) {
                wallpaperConfiguration[keys[i]] = settings[keys[i]];
            }
            if (wallpaperConfiguration.writeConfig)
                wallpaperConfiguration.writeConfig();

            if (liveWallpaper && liveWallpaper.reloadWallpaper)
                liveWallpaper.reloadWallpaper();

            importExportStatus.text = i18n("Settings imported.");
        } catch (e) {
            importExportStatus.text = i18n("Could not import settings file.");
        }
    }

    Layout.fillWidth: true
    implicitHeight: Math.max(previewColumn.implicitHeight + tabBar.implicitHeight + (settingsSearchField.visible ? settingsSearchField.implicitHeight : 0) + tabs.implicitHeight + (setupWizardPanel.visible ? setupWizardPanel.implicitHeight : 0) + Kirigami.Units.gridUnit * 2, 420)
    spacing: Kirigami.Units.smallSpacing
    Component.onCompleted: {
        refreshHistoryModel();
        refreshCacheModel();
    }

    QtObject {
        id: setupWizardCompletedFlag

        property bool value: wallpaperConfiguration ? wallpaperConfiguration.SetupWizardCompleted : true
    }

    ListModel {
        id: cacheModel
    }

    ListModel {
        id: historyModel
    }

    TextEdit {
        id: settingsClipboardHelper

        visible: false
        width: 1
        height: 1
    }

    QtControls2.Label {
        id: importExportStatus

        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        opacity: 0.7
        visible: text !== ""
    }

    Timer {
        interval: 4000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.refreshHistoryModel();
            if (typeof PDBus === "undefined" || !PDBus.SessionBus) {
                root.dbusPollCompleted = true;
                root.dbusPolledOnline = !!(liveWallpaper && liveWallpaper.dbusServiceAvailable);
                return;
            }
            var msg = new PDBus.dbusMessage({
                service: "org.robertsm.Wallhaven",
                path: "/Wallhaven",
                iface: "org.robertsm.Wallhaven",
                member: "Ping",
                signature: "",
                arguments: [],
            });
            PDBus.SessionBus.asyncCall(msg, function() {
                root.dbusPolledOnline = true;
                root.dbusPollCompleted = true;
                var upscaleMsg = new PDBus.dbusMessage({
                    service: "org.robertsm.Wallhaven",
                    path: "/Wallhaven",
                    iface: "org.robertsm.Wallhaven",
                    member: "UpscalerAvailable",
                    signature: "",
                    arguments: [],
                });
                PDBus.SessionBus.asyncCall(upscaleMsg, function(reply) {
                    root.upscalerPolledPath = Wallhaven.dbusReplyAsString(reply);
                    root.upscalerPollCompleted = true;
                }, function() {
                    root.upscalerPolledPath = "";
                    root.upscalerPollCompleted = true;
                });
            }, function() {
                root.dbusPolledOnline = false;
                root.dbusPollCompleted = true;
                root.upscalerPolledPath = "";
                root.upscalerPollCompleted = true;
            });
        }
    }

    Kirigami.InlineMessage {
        Layout.fillWidth: true
        visible: root.dbusPollCompleted && !root.dbusServiceOnline
        type: Kirigami.InlineMessage.Warning
        text: i18n("Wallhaven D-Bus service is not running. Run: systemctl --user enable --now wallhaven-dbus.service")
    }

    ColumnLayout {
        id: setupWizardPanel

        Layout.fillWidth: true
        visible: root.showSetupWizard
        spacing: Kirigami.Units.smallSpacing

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            type: Kirigami.MessageType.Information
            text: i18n("Welcome to Wallhaven for Plasma")
        }

        Kirigami.FormLayout {
            Layout.fillWidth: true
            twinFormLayouts: typeof appearanceRoot !== "undefined" ? [appearanceRoot.parentLayout] : []

            QtControls2.Label {
                Kirigami.FormData.label: i18n("Getting started:")
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: i18n("Optional: add your Wallhaven API key for NSFW and favorites.")
            }

            QtControls2.TextField {
                id: wizardApiKeyField

                Kirigami.FormData.label: i18n("API key:")
                Layout.fillWidth: true
                placeholderText: i18n("API key (optional)")
                echoMode: TextInput.Password
                text: apiKeyField.text
                onTextChanged: apiKeyField.text = text
            }

            QtControls2.TextField {
                id: wizardSearchField

                Kirigami.FormData.label: i18n("Search:")
                Layout.fillWidth: true
                placeholderText: i18n("Search tags, e.g. nature landscape")
                text: searchTextField.text
                onTextChanged: searchTextField.text = text
            }

            QtControls2.SpinBox {
                id: wizardIntervalSpin

                Kirigami.FormData.label: i18n("Slideshow interval (min):")
                from: 0
                to: 240
                value: intervalSpin.value > 0 ? intervalSpin.value : 30
                onValueChanged: intervalSpin.value = value
            }

            QtControls2.Button {
                Kirigami.FormData.label: i18n("Presets:")
                text: i18n("Import curated presets")
                onClicked: root.importCuratedPresets()
            }

            QtControls2.Label {
                Kirigami.FormData.label: i18n("Setup status:")
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                opacity: 0.85
                text: root.dbusServiceOnline
                    ? i18n("D-Bus service: online")
                    : i18n("D-Bus service: offline — run: systemctl --user enable --now wallhaven-dbus.service")
            }

            QtControls2.Label {
                Kirigami.FormData.label: " "
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                opacity: 0.85
                text: {
                    if (!root.upscalerStatusKnown)
                        return i18n("Upscaler: checking…");
                    return root.upscalerAvailable
                        ? i18n("Upscaler: realesrgan-ncnn-vulkan found")
                        : i18n("Upscaler: not installed (optional)");
                }
            }

            QtControls2.Label {
                Kirigami.FormData.label: " "
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                opacity: 0.7
                text: i18n("Shortcuts: ./dev-helper.sh install-shortcuts (Meta+Alt+arrows)")
            }

            RowLayout {
                Kirigami.FormData.label: " "

                Item {
                    Layout.fillWidth: true
                }

                QtControls2.Button {
                    text: i18n("Skip")
                    onClicked: root.finishSetupWizard()
                }

                QtControls2.Button {
                    text: i18n("Finish")
                    onClicked: {
                        if (wallpaperConfiguration) {
                            wallpaperConfiguration.RandomInterval = Math.max(wallpaperConfiguration.RandomInterval, wizardIntervalSpin.value);
                            if (wizardSearchField.text.trim()) {
                                wallpaperConfiguration.SearchText = wizardSearchField.text.trim();
                                wallpaperConfiguration.BrowseMode = "search";
                            }
                            if (wallpaperConfiguration.writeConfig)
                                wallpaperConfiguration.writeConfig();

                        }
                        root.finishSetupWizard();
                    }
                }

            }

        }

    }

    // Current wallpaper: landscape preview above description, centered
    ColumnLayout {
        id: previewColumn

        Layout.fillWidth: true
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: Kirigami.Units.smallSpacing
        Layout.bottomMargin: Kirigami.Units.smallSpacing
        Layout.maximumWidth: Math.min(root.previewWidth + Kirigami.Units.largeSpacing * 2, root.width)
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Heading {
            text: i18n("Current Wallpaper")
            level: 3
            Layout.alignment: Qt.AlignHCenter
        }

        Rectangle {
            id: previewFrame

            Layout.preferredWidth: root.previewWidth
            Layout.preferredHeight: root.previewHeight
            Layout.alignment: Qt.AlignHCenter
            color: Kirigami.Theme.backgroundColor
            border.color: Kirigami.Theme.disabledTextColor
            border.width: 1
            radius: Kirigami.Units.smallSpacing
            clip: true

            // Prefer Wallhaven thumb; cache is a screen-grab fallback.
            Image {
                id: thumbPreviewImage

                anchors.fill: parent
                anchors.margins: 1
                fillMode: Image.PreserveAspectCrop
                source: root.previewThumbUrl
                asynchronous: true
                cache: false
                visible: status === Image.Ready
            }

            Image {
                id: filePreviewImage

                anchors.fill: parent
                anchors.margins: 1
                fillMode: Image.PreserveAspectCrop
                source: root.previewFileUrl
                asynchronous: true
                cache: false
                visible: !thumbPreviewImage.visible && status === Image.Ready
            }

            Kirigami.Icon {
                anchors.centerIn: parent
                width: Kirigami.Units.iconSizes.large
                height: width
                source: (root.previewFileUrl || root.previewThumbUrl) ? "image-loading" : "image-x-generic"
                visible: !thumbPreviewImage.visible && !filePreviewImage.visible
            }

        }

        QtControls2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: root.previewWidth
            Layout.alignment: Qt.AlignHCenter
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: root.previewAttribution !== "" ? root.previewAttribution : i18n("No wallpaper loaded yet. Apply Wallhaven as the wallpaper type and wait for the first image.")
            opacity: root.previewAttribution !== "" ? 1 : 0.7
        }

        QtControls2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: root.previewWidth
            Layout.alignment: Qt.AlignHCenter
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: 0.85
            visible: root.previewWallpaperDetails !== ""
            text: root.previewWallpaperDetails
        }

        QtControls2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: root.previewWidth
            Layout.alignment: Qt.AlignHCenter
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: 0.7
            text: i18n("Wallpaper Actions: Reload / Next / Similar / Pause / Copy / Block / Save.")
        }

    }

    QtObject {
        id: apiKeyValidator

        property bool checking: false
        property string statusText: ""

        function validate() {
            statusText = "";
            if (!apiKeyField.text) {
                statusText = i18n("Enter an API key first.");
                return ;
            }
            checking = true;
            var xhr = new XMLHttpRequest();
            xhr.open("GET", Wallhaven.buildSettingsUrl(apiKeyField.text));
            xhr.timeout = 15000;
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE)
                    return ;

                checking = false;
                if (xhr.status === 200) {
                    statusText = i18n("API key is valid.");
                    if (wallpaperConfiguration)
                        wallpaperConfiguration.ApiKeyValid = true;

                } else {
                    statusText = i18n("API key validation failed (%1).", xhr.status);
                    if (wallpaperConfiguration)
                        wallpaperConfiguration.ApiKeyValid = false;

                }
            };
            xhr.onerror = function() {
                checking = false;
                statusText = i18n("Network error while validating API key.");
            };
            xhr.send();
        }

    }

    QtObject {
        id: searchValidator

        property bool checking: false
        property string statusText: ""

        function testSearch() {
            statusText = "";
            checking = true;
            var cfg = root.buildCurrentConfigObject();
            cfg.FileTypeFilter = fileTypeCombo.currentValue;
            cfg.ApiKey = apiKeyField.text;
            cfg.Sortings = sortingsCombo.currentValue;
            cfg.Order = orderCombo.currentValue;
            cfg.TopRange = topRangeCombo.currentValue;
            var state = {
                "page": 1,
                "seed": "test",
                "searchQuery": searchTextField.text,
                "screenWidth": 1920,
                "screenHeight": 1080
            };
            var xhr = new XMLHttpRequest();
            xhr.open("GET", Wallhaven.buildSearchUrl(cfg, state));
            xhr.timeout = 20000;
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE)
                    return ;

                checking = false;
                if (xhr.status !== 200) {
                    statusText = i18n("Search test failed (%1).", xhr.status);
                    return ;
                }
                try {
                    var json = JSON.parse(xhr.responseText);
                    var total = json.meta && json.meta.total !== undefined ? json.meta.total : 0;
                    statusText = i18n("Search test: %1 result(s).", total);
                } catch (e) {
                    statusText = i18n("Could not parse search response.");
                }
            };
            xhr.onerror = function() {
                checking = false;
                statusText = i18n("Network error during search test.");
            };
            xhr.send();
        }

    }

    QtObject {
        id: collectionsLoader

        property var entries: []
        property bool loading: false
        property string errorText: ""

        function refresh() {
            errorText = "";
            if (!apiKeyField.text) {
                errorText = i18n("Enter an API key first.");
                return ;
            }
            loading = true;
            entries = [];
            var xhr = new XMLHttpRequest();
            xhr.open("GET", Wallhaven.buildCollectionsUrl(apiKeyField.text));
            xhr.setRequestHeader("Accept", "application/json");
            xhr.timeout = 30000;
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE)
                    return ;

                loading = false;
                if (xhr.status === 200) {
                    try {
                        entries = Wallhaven.parseCollectionsResponse(JSON.parse(xhr.responseText));
                        if (!entries.length)
                            errorText = i18n("No collections found for this API key.");
                        else
                            syncPickerSelection();
                    } catch (e) {
                        errorText = i18n("Could not parse collections response.");
                    }
                } else {
                    errorText = i18n("Failed to load collections (%1).", xhr.status);
                }
            };
            xhr.onerror = function() {
                loading = false;
                errorText = i18n("Network error while loading collections.");
            };
            xhr.ontimeout = function() {
                loading = false;
                errorText = i18n("Timed out while loading collections.");
            };
            xhr.send();
        }

        function applySelection(index) {
            if (index < 0 || index >= entries.length)
                return ;

            var entry = entries[index];
            collectionUserField.text = entry.username;
            collectionIdField.text = entry.id;
        }

        function syncPickerSelection() {
            for (var i = 0; i < entries.length; i++) {
                if (entries[i].id === collectionIdField.text && entries[i].username === collectionUserField.text) {
                    collectionPickerCombo.currentIndex = i;
                    return ;
                }
            }
        }

    }

    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: settingsSearchField.implicitHeight

        QtControls2.TextField {
            id: settingsSearchField

            anchors.fill: parent
            placeholderText: i18n("Filter settings…")
            onTextChanged: root.settingsFilter = text.trim()
        }

    }

    QtControls2.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        opacity: 0.65
        visible: root.settingsFilter !== "" && !root.settingsFilterMatchesAny()
        text: i18n("No settings match %1. Try another tab or clear the filter.", root.settingsFilter)
    }

    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: tabBar.implicitHeight

        QtControls2.TabBar {
            id: tabBar

            anchors.horizontalCenter: parent.horizontalCenter
            width: implicitWidth

            QtControls2.TabButton {
                text: i18n("Source")
            }

            QtControls2.TabButton {
                text: i18n("Filters")
            }

            QtControls2.TabButton {
                text: i18n("Playback")
            }

            QtControls2.TabButton {
                text: i18n("Advanced")
            }

        }

    }

    StackLayout {
        id: tabs

        Layout.fillWidth: true
        Layout.preferredHeight: 420
        Layout.minimumHeight: 320
        currentIndex: tabBar.currentIndex

        // Source
        QtControls2.ScrollView {
            id: sourceScroll

            contentWidth: availableWidth
            clip: true

            Kirigami.FormLayout {
                id: sourceForm

                width: sourceScroll.availableWidth
                twinFormLayouts: typeof appearanceRoot !== "undefined" ? [appearanceRoot.parentLayout] : []

                QtControls2.ComboBox {
                    id: browseModeCombo

                    Kirigami.FormData.label: i18n("Browse mode:")
                    textRole: "label"
                    valueRole: "value"
                    model: [{
                        "label": i18n("Search"),
                        "value": "search"
                    }, {
                        "label": i18n("More like current"),
                        "value": "similar"
                    }, {
                        "label": i18n("Collection"),
                        "value": "collection"
                    }, {
                        "label": i18n("Favorites"),
                        "value": "favorites"
                    }]
                }

                QtControls2.Label {
                    Kirigami.FormData.label: " "
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    visible: browseModeCombo.currentValue === "similar"
                    text: i18n("Keeps searching for wallpapers similar to the one on screen (like:ID). Start in Search or Collection mode first if the screen is empty.")
                }

                QtControls2.TextField {
                    id: searchTextField

                    Kirigami.FormData.label: i18n("Search string:")
                    placeholderText: i18n("Tags, keywords, e.g. nature anime")
                    visible: browseModeCombo.currentValue === "search" && fieldVisible(["search", "tags", "query"])
                }

                QtControls2.CheckBox {
                    id: wallpaperOfDayCheck

                    Kirigami.FormData.label: i18n("Wallpaper of the day:")
                    text: i18n("Use today's Wallhaven toplist (overrides sorting)")
                    visible: browseModeCombo.currentValue === "search" && fieldVisible(["toplist", "daily", "wotd"])
                }

                QtControls2.SpinBox {
                    id: favoritesRefreshSpin

                    Kirigami.FormData.label: i18n("Favorites refresh (min):")
                    from: 0
                    to: 1440
                    visible: browseModeCombo.currentValue === "favorites" && fieldVisible(["favorites", "refresh"])
                }

                QtControls2.Button {
                    Kirigami.FormData.label: i18n("Test search:")
                    text: searchValidator.checking ? i18n("Testing…") : i18n("Test search")
                    visible: browseModeCombo.currentValue === "search"
                    enabled: !searchValidator.checking
                    onClicked: searchValidator.testSearch()
                }

                QtControls2.Label {
                    Kirigami.FormData.label: " "
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    visible: browseModeCombo.currentValue === "search" && searchValidator.statusText !== ""
                    text: searchValidator.statusText
                }

                QtControls2.TextField {
                    id: apiKeyField

                    Kirigami.FormData.label: i18n("API key:")
                    placeholderText: i18n("Optional; required for NSFW and favorites")
                    echoMode: TextInput.Password
                }

                QtControls2.Button {
                    Kirigami.FormData.label: i18n("Validate key:")
                    text: apiKeyValidator.checking ? i18n("Checking…") : i18n("Test API key")
                    enabled: apiKeyField.text !== "" && !apiKeyValidator.checking
                    onClicked: apiKeyValidator.validate()
                }

                QtControls2.Label {
                    Kirigami.FormData.label: " "
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    visible: apiKeyValidator.statusText !== ""
                    text: apiKeyValidator.statusText
                }

                QtControls2.CheckBox {
                    id: kwalletCheck

                    Kirigami.FormData.label: i18n("KWallet:")
                    text: i18n("Load API key from KWallet on startup")
                }

                QtControls2.TextField {
                    id: collectionUserField

                    Kirigami.FormData.label: i18n("Collection user:")
                    placeholderText: i18n("Username for collection/favorites override")
                    visible: browseModeCombo.currentValue !== "search"
                }

                QtControls2.TextField {
                    id: collectionIdField

                    Kirigami.FormData.label: i18n("Collection ID:")
                    visible: browseModeCombo.currentValue === "collection"
                }

                QtControls2.Button {
                    id: loadCollectionsButton

                    Kirigami.FormData.label: i18n("Collections:")
                    text: collectionsLoader.loading ? i18n("Loading…") : i18n("Load collections")
                    visible: browseModeCombo.currentValue === "collection"
                    enabled: apiKeyField.text !== "" && !collectionsLoader.loading
                    onClicked: collectionsLoader.refresh()
                }

                QtControls2.ComboBox {
                    id: collectionPickerCombo

                    Kirigami.FormData.label: i18n("Pick collection:")
                    textRole: "display"
                    visible: browseModeCombo.currentValue === "collection" && collectionsLoader.entries.length > 0
                    model: collectionsLoader.entries
                    onActivated: collectionsLoader.applySelection(currentIndex)
                }

                QtControls2.Label {
                    Kirigami.FormData.label: " "
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    visible: browseModeCombo.currentValue === "collection" && collectionsLoader.errorText !== ""
                    text: collectionsLoader.errorText
                }

                QtControls2.CheckBox {
                    id: collectionRotationCheck

                    Kirigami.FormData.label: i18n("Rotate collections:")
                    text: i18n("Cycle through multiple collections on each advance")
                    visible: browseModeCombo.currentValue === "collection"
                }

                QtControls2.TextArea {
                    id: collectionRotationField

                    Kirigami.FormData.label: i18n("Collection list:")
                    placeholderText: i18n("username/id per line (optional # label)")
                    visible: browseModeCombo.currentValue === "collection"
                    enabled: collectionRotationCheck.checked
                    text: root.collectionRotationText()
                    Binding on text {
                        when: !collectionRotationField.activeFocus
                        value: root.collectionRotationText()
                    }
                    onEditingFinished: root.persistCollectionRotation(text)
                }

                QtControls2.ComboBox {
                    id: sortingsCombo

                    Kirigami.FormData.label: i18n("API sorting:")
                    textRole: "label"
                    valueRole: "value"
                    visible: browseModeCombo.currentValue === "search"
                    model: [{
                        "label": i18n("Random"),
                        "value": "random"
                    }, {
                        "label": i18n("Date added"),
                        "value": "date_added"
                    }, {
                        "label": i18n("Relevance"),
                        "value": "relevance"
                    }, {
                        "label": i18n("Views"),
                        "value": "views"
                    }, {
                        "label": i18n("Favorites"),
                        "value": "favorites"
                    }, {
                        "label": i18n("Toplist"),
                        "value": "toplist"
                    }]
                }

                QtControls2.ComboBox {
                    id: topRangeCombo

                    Kirigami.FormData.label: i18n("Toplist range:")
                    textRole: "label"
                    valueRole: "value"
                    visible: browseModeCombo.currentValue === "search" && sortingsCombo.currentValue === "toplist"
                    model: [{
                        "label": "1d",
                        "value": "1d"
                    }, {
                        "label": "1w",
                        "value": "1w"
                    }, {
                        "label": "1M",
                        "value": "1M"
                    }, {
                        "label": "3M",
                        "value": "3M"
                    }, {
                        "label": "1y",
                        "value": "1y"
                    }]
                }

                QtControls2.ComboBox {
                    id: orderCombo

                    Kirigami.FormData.label: i18n("API order:")
                    textRole: "label"
                    valueRole: "value"
                    visible: browseModeCombo.currentValue === "search"
                    model: [{
                        "label": i18n("Descending"),
                        "value": "desc"
                    }, {
                        "label": i18n("Ascending"),
                        "value": "asc"
                    }]
                }

                QtControls2.ComboBox {
                    id: localSortingsCombo

                    Kirigami.FormData.label: i18n("Local sorting:")
                    textRole: "label"
                    valueRole: "value"
                    model: [{
                        "label": i18n("Ascending"),
                        "value": "ascending"
                    }, {
                        "label": i18n("Descending"),
                        "value": "descending"
                    }, {
                        "label": i18n("Random"),
                        "value": "random"
                    }]
                }

            }

        }

        // Filters
        QtControls2.ScrollView {
            id: filtersScroll

            contentWidth: availableWidth
            clip: true

            Kirigami.FormLayout {
                readonly property bool searchFilters: browseModeCombo.currentValue === "search"

                width: filtersScroll.availableWidth

                Kirigami.InlineMessage {
                    Layout.fillWidth: true
                    visible: !parent.searchFilters
                    type: Kirigami.MessageType.Information
                    text: i18n("Category, purity, ratio, color, blacklist, and time-of-day filters apply to Search mode only. Collection and Favorites use the collection API as-is.")
                }

                Kirigami.Separator {
                    Kirigami.FormData.label: i18n("Categories")
                    Kirigami.FormData.isSection: true
                    visible: parent.searchFilters
                }

                QtControls2.CheckBox {
                    id: generalCheck

                    Kirigami.FormData.label: i18n("General:")
                    text: i18n("Enabled")
                    visible: parent.searchFilters
                }

                QtControls2.CheckBox {
                    id: animeCheck

                    Kirigami.FormData.label: i18n("Anime:")
                    text: i18n("Enabled")
                    visible: parent.searchFilters
                }

                QtControls2.CheckBox {
                    id: peopleCheck

                    Kirigami.FormData.label: i18n("People:")
                    text: i18n("Enabled")
                    visible: parent.searchFilters
                }

                Kirigami.Separator {
                    Kirigami.FormData.label: i18n("Purity")
                    Kirigami.FormData.isSection: true
                    visible: parent.searchFilters
                }

                QtControls2.CheckBox {
                    id: sfwCheck

                    Kirigami.FormData.label: i18n("SFW:")
                    text: i18n("Enabled")
                    visible: parent.searchFilters
                }

                QtControls2.CheckBox {
                    id: sketchyCheck

                    Kirigami.FormData.label: i18n("Sketchy:")
                    text: i18n("Enabled")
                    visible: parent.searchFilters
                }

                QtControls2.CheckBox {
                    id: nsfwCheck

                    Kirigami.FormData.label: i18n("NSFW:")
                    text: i18n("Enabled")
                    visible: parent.searchFilters
                }

                Kirigami.Separator {
                    Kirigami.FormData.label: i18n("Resolution & Ratio")
                    Kirigami.FormData.isSection: true
                    visible: parent.searchFilters
                }

                QtControls2.TextField {
                    id: minWidthField

                    Kirigami.FormData.label: i18n("Min width:")
                    placeholderText: i18n("Empty = screen width")
                    visible: parent.searchFilters
                }

                QtControls2.TextField {
                    id: minHeightField

                    Kirigami.FormData.label: i18n("Min height:")
                    placeholderText: i18n("Empty = screen height")
                    visible: parent.searchFilters
                }

                QtControls2.TextField {
                    id: resolutionsField

                    Kirigami.FormData.label: i18n("Exact resolutions:")
                    placeholderText: i18n("e.g. 1920x1080,2560x1440")
                    visible: parent.searchFilters
                }

                QtControls2.ComboBox {
                    id: ratioCombo

                    Kirigami.FormData.label: i18n("Ratio:")
                    textRole: "label"
                    valueRole: "value"
                    visible: parent.searchFilters
                    model: [{
                        "label": i18n("All wide"),
                        "value": "landscape"
                    }, {
                        "label": "16×9",
                        "value": "16x9"
                    }, {
                        "label": "21×9",
                        "value": "21x9"
                    }, {
                        "label": "32×9",
                        "value": "32x9"
                    }, {
                        "label": i18n("All portrait"),
                        "value": "portrait"
                    }, {
                        "label": "9×16",
                        "value": "9x16"
                    }]
                }

                QtControls2.ComboBox {
                    id: fileTypeCombo

                    Kirigami.FormData.label: i18n("File type:")
                    textRole: "label"
                    valueRole: "value"
                    visible: parent.searchFilters
                    model: [{
                        "label": i18n("Any"),
                        "value": ""
                    }, {
                        "label": "JPEG",
                        "value": "jpg"
                    }, {
                        "label": "PNG",
                        "value": "png"
                    }, {
                        "label": "WebP",
                        "value": "webp"
                    }]
                }

                QtControls2.ComboBox {
                    id: colorCombo

                    Kirigami.FormData.label: i18n("Color:")
                    textRole: "label"
                    valueRole: "value"
                    visible: parent.searchFilters
                    model: [{
                        "label": i18n("Any"),
                        "value": ""
                    }, {
                        "label": i18n("System color scheme"),
                        "value": "system"
                    }, {
                        "label": i18n("Red"),
                        "value": "660000"
                    }, {
                        "label": i18n("Dark Red"),
                        "value": "990000"
                    }, {
                        "label": i18n("Bright Red"),
                        "value": "cc0000"
                    }, {
                        "label": i18n("Pink Red"),
                        "value": "cc3333"
                    }, {
                        "label": i18n("Pink"),
                        "value": "ea4c88"
                    }, {
                        "label": i18n("Purple"),
                        "value": "993399"
                    }, {
                        "label": i18n("Dark Purple"),
                        "value": "663399"
                    }, {
                        "label": i18n("Blue Purple"),
                        "value": "333399"
                    }, {
                        "label": i18n("Blue"),
                        "value": "0066cc"
                    }, {
                        "label": i18n("Cyan Blue"),
                        "value": "0099cc"
                    }, {
                        "label": i18n("Teal"),
                        "value": "66cccc"
                    }, {
                        "label": i18n("Green"),
                        "value": "77cc33"
                    }, {
                        "label": i18n("Dark Green"),
                        "value": "669900"
                    }, {
                        "label": i18n("Forest"),
                        "value": "336600"
                    }, {
                        "label": i18n("Olive"),
                        "value": "666600"
                    }, {
                        "label": i18n("Yellow Green"),
                        "value": "999900"
                    }, {
                        "label": i18n("Yellow"),
                        "value": "cccc33"
                    }, {
                        "label": i18n("Bright Yellow"),
                        "value": "ffff00"
                    }, {
                        "label": i18n("Gold"),
                        "value": "ffcc33"
                    }, {
                        "label": i18n("Orange"),
                        "value": "ff9900"
                    }, {
                        "label": i18n("Dark Orange"),
                        "value": "ff6600"
                    }, {
                        "label": i18n("Brown"),
                        "value": "cc6633"
                    }, {
                        "label": i18n("Tan"),
                        "value": "996633"
                    }, {
                        "label": i18n("Dark Brown"),
                        "value": "663300"
                    }, {
                        "label": i18n("Black"),
                        "value": "000000"
                    }, {
                        "label": i18n("Gray"),
                        "value": "999999"
                    }, {
                        "label": i18n("Light Gray"),
                        "value": "cccccc"
                    }, {
                        "label": i18n("White"),
                        "value": "ffffff"
                    }, {
                        "label": i18n("Slate"),
                        "value": "424153"
                    }]
                }

                Kirigami.Separator {
                    Kirigami.FormData.label: i18n("Other")
                    Kirigami.FormData.isSection: true
                }

                QtControls2.CheckBox {
                    id: blacklistCheck

                    Kirigami.FormData.label: i18n("Account blacklist:")
                    text: i18n("Apply Wallhaven tag blacklist (Search + API key)")
                    visible: parent.searchFilters
                }

                QtControls2.CheckBox {
                    id: dedupCheck

                    Kirigami.FormData.label: i18n("Duplicates:")
                    text: i18n("Avoid recent duplicates (saved across restarts)")
                }

                QtControls2.CheckBox {
                    id: preferSharpMatchesCheck

                    Kirigami.FormData.label: i18n("Image quality:")
                    text: i18n("Prefer sharper matches (bias random picks toward images that fit your screen size and aspect ratio without heavy upscaling or cropping)")
                }

                QtControls2.TextField {
                    id: tagBlocklistField

                    Kirigami.FormData.label: i18n("Tag blocklist:")
                    placeholderText: i18n("Comma-separated tags to exclude, e.g. nsfw, text")
                    visible: parent.searchFilters
                    text: root.tagBlocklistText()
                    Binding on text {
                        when: !tagBlocklistField.activeFocus
                        value: root.tagBlocklistText()
                    }
                    onEditingFinished: root.persistTagBlocklist(text)
                }

                Kirigami.Separator {
                    Kirigami.FormData.label: i18n("Search Presets")
                    Kirigami.FormData.isSection: true
                    visible: parent.searchFilters
                }

                QtControls2.TextField {
                    id: presetNameField

                    Kirigami.FormData.label: i18n("Preset name:")
                    placeholderText: i18n("e.g. Anime night")
                    visible: parent.searchFilters
                }

                QtControls2.ComboBox {
                    id: presetCombo

                    Kirigami.FormData.label: i18n("Saved presets:")
                    textRole: "name"
                    visible: parent.searchFilters
                    model: root.currentPresets()
                }

                QtControls2.Button {
                    Kirigami.FormData.label: i18n("Save preset:")
                    text: i18n("Save current search")
                    visible: parent.searchFilters
                    onClicked: {
                        var name = presetNameField.text.trim();
                        if (!name)
                            return ;

                        var presets = root.currentPresets().slice();
                        var preset = Wallhaven.buildPresetFromConfig(name, root.buildCurrentConfigObject());
                        var replaced = false;
                        for (var i = 0; i < presets.length; i++) {
                            if (presets[i].name === name) {
                                presets[i] = preset;
                                replaced = true;
                                break;
                            }
                        }
                        if (!replaced)
                            presets.push(preset);

                        root.persistPresets(presets);
                        var idx = -1;
                        for (var j = 0; j < presets.length; j++) {
                            if (presets[j].name === name) {
                                idx = j;
                                break;
                            }
                        }
                        presetCombo.currentIndex = idx;
                    }
                }

                QtControls2.Button {
                    Kirigami.FormData.label: i18n("Apply preset:")
                    text: i18n("Apply selected preset")
                    visible: parent.searchFilters
                    enabled: presetCombo.currentIndex >= 0
                    onClicked: root.applySearchPreset(root.currentPresets()[presetCombo.currentIndex])
                }

                QtControls2.Button {
                    Kirigami.FormData.label: i18n("Import curated:")
                    text: i18n("Import curated presets")
                    visible: parent.searchFilters
                    onClicked: root.importCuratedPresets()
                }

                QtControls2.Button {
                    Kirigami.FormData.label: i18n("Import community:")
                    text: i18n("Import community presets")
                    visible: parent.searchFilters
                    onClicked: root.importCommunityPresets()
                }

                QtControls2.Label {
                    Kirigami.FormData.label: i18n("Preset browser:")
                    visible: parent.searchFilters
                    text: i18n("Bundled packs (one-click import):")
                }

                Flow {
                    Kirigami.FormData.label: " "
                    Layout.fillWidth: true
                    visible: parent.searchFilters
                    spacing: Kirigami.Units.smallSpacing

                    Repeater {
                        model: Wallhaven.bundledCuratedPresets().concat(Wallhaven.bundledCommunityPresets())

                        delegate: QtControls2.Button {
                            text: modelData.name
                            onClicked: {
                                var merged = Wallhaven.mergePresetLists(root.currentPresets(), [modelData]);
                                root.persistPresets(merged);
                                importExportStatus.text = i18n("Imported preset \"%1\".", modelData.name);
                            }
                        }
                    }
                }

                QtControls2.Label {
                    Kirigami.FormData.label: " "
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    visible: parent.searchFilters && importExportStatus.text !== ""
                    text: importExportStatus.text
                }

                QtControls2.TextField {
                    id: presetUrlField

                    Kirigami.FormData.label: i18n("Preset URL:")
                    placeholderText: i18n("wallhaven://preset/…")
                    visible: parent.searchFilters
                }

                QtControls2.Button {
                    Kirigami.FormData.label: i18n("Import URL:")
                    text: i18n("Import preset from URL")
                    visible: parent.searchFilters
                    enabled: presetUrlField.text.trim() !== "" && liveWallpaper !== null
                    onClicked: root.importPresetFromUrlField()
                }

                QtControls2.TextField {
                    id: tagFavoritesField

                    Kirigami.FormData.label: i18n("Favorite tags:")
                    placeholderText: i18n("Comma-separated tags boosted in search")
                    visible: parent.searchFilters
                    text: root.favoriteTagsText()
                    Binding on text {
                        when: !tagFavoritesField.activeFocus
                        value: root.favoriteTagsText()
                    }
                    onEditingFinished: root.persistFavoriteTags(text)
                }

                QtControls2.Button {
                    Kirigami.FormData.label: i18n("Share preset:")
                    text: i18n("Copy preset share URL")
                    visible: parent.searchFilters
                    enabled: presetCombo.currentIndex >= 0
                    onClicked: root.shareSelectedPresetUrl()
                }

                QtControls2.Button {
                    Kirigami.FormData.label: i18n("Delete preset:")
                    text: i18n("Delete selected preset")
                    visible: parent.searchFilters
                    enabled: presetCombo.currentIndex >= 0
                    onClicked: {
                        var presets = root.currentPresets().slice();
                        presets.splice(presetCombo.currentIndex, 1);
                        root.persistPresets(presets);
                        presetCombo.currentIndex = -1;
                    }
                }

            }

        }

        // Playback & effects
        QtControls2.ScrollView {
            id: playbackScroll

            contentWidth: availableWidth
            clip: true

            Kirigami.FormLayout {
                width: playbackScroll.availableWidth

                Kirigami.Separator {
                    Kirigami.FormData.label: i18n("Slideshow")
                    Kirigami.FormData.isSection: true
                }

                QtControls2.SpinBox {
                    id: intervalSpin

                    Kirigami.FormData.label: i18n("Interval (min):")
                    from: 0
                    to: 10080
                }

                QtControls2.CheckBox {
                    id: slideshowPausedCheck

                    Kirigami.FormData.label: i18n("Pause:")
                    text: i18n("Pause automatic slideshow")
                    enabled: intervalSpin.value > 0
                }

                QtControls2.Label {
                    Kirigami.FormData.label: " "
                    text: i18n("0 = manual only. Pause also available from desktop Wallpaper Actions.")
                    opacity: 0.7
                    wrapMode: Text.WordWrap
                }

                QtControls2.SpinBox {
                    id: jitterSpin

                    Kirigami.FormData.label: i18n("Interval jitter (%):")
                    from: 0
                    to: 50
                }

                QtControls2.SpinBox {
                    id: dayIntervalSpin

                    Kirigami.FormData.label: i18n("Day interval (min):")
                    from: 0
                    to: 10080
                }

                QtControls2.SpinBox {
                    id: nightIntervalSpin

                    Kirigami.FormData.label: i18n("Night interval (min):")
                    from: 0
                    to: 10080
                }

                QtControls2.Label {
                    Kirigami.FormData.label: " "
                    text: i18n("Day/night intervals override the base interval when set (6am–8pm = day).")
                    opacity: 0.7
                    wrapMode: Text.WordWrap
                }

                Kirigami.Separator {
                    Kirigami.FormData.label: i18n("Effects")
                    Kirigami.FormData.isSection: true
                }

                QtControls2.ComboBox {
                    id: qualityCombo

                    Kirigami.FormData.label: i18n("Image quality:")
                    textRole: "label"
                    valueRole: "value"
                    model: [{
                        "label": i18n("Small (thumbnail, low bandwidth)"),
                        "value": "small"
                    }, {
                        "label": i18n("Large (full wallpaper)"),
                        "value": "large"
                    }, {
                        "label": i18n("Original (full wallpaper)"),
                        "value": "original"
                    }]
                }

                QtControls2.SpinBox {
                    id: crossfadeSpin

                    Kirigami.FormData.label: i18n("Crossfade (ms):")
                    from: 0
                    to: 3000
                    stepSize: 100
                }

                QtControls2.ComboBox {
                    id: transitionCombo

                    Kirigami.FormData.label: i18n("Transition:")
                    textRole: "label"
                    valueRole: "value"
                    model: [{
                        "label": i18n("Crossfade"),
                        "value": "crossfade"
                    }, {
                        "label": i18n("Fade through black"),
                        "value": "fadeblack"
                    }, {
                        "label": i18n("Slide"),
                        "value": "slide"
                    }, {
                        "label": i18n("Zoom"),
                        "value": "zoom"
                    }, {
                        "label": i18n("Random"),
                        "value": "random"
                    }, {
                        "label": i18n("Instant"),
                        "value": "instant"
                    }]
                }

                QtControls2.CheckBox {
                    id: parallaxCheck

                    Kirigami.FormData.label: i18n("Parallax:")
                    text: i18n("Slowly pan across the wallpaper")
                }

                QtControls2.SpinBox {
                    id: parallaxStrengthSpin

                    Kirigami.FormData.label: i18n("Parallax strength:")
                    from: 0
                    to: 100
                    enabled: parallaxCheck.checked
                }

                QtControls2.CheckBox {
                    id: lockScreenCheck

                    Kirigami.FormData.label: i18n("Lock screen:")
                    text: i18n("Copy the current wallpaper to the lock screen")
                }

                QtControls2.CheckBox {
                    id: panelTintCheck

                    Kirigami.FormData.label: i18n("Panel tint hint:")
                    text: i18n("Write dominant color JSON for external theming tools")
                }

                QtControls2.SpinBox {
                    id: panelBlurStrengthSpin

                    Kirigami.FormData.label: i18n("Panel blur hint (%):")
                    from: 0
                    to: 100
                    enabled: panelTintCheck.checked
                }

                QtControls2.Label {
                    Kirigami.FormData.label: " "
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    visible: panelTintCheck.checked
                    text: i18n("Blur strength is stored in the panel tint JSON for external tools; Plasma panel blur itself is configured in System Settings.")
                }

                QtControls2.CheckBox {
                    id: autoPanelAccentCheck

                    Kirigami.FormData.label: i18n("Auto panel accent:")
                    text: i18n("Apply accent color via plasma-apply-colors when available")
                }

                QtControls2.CheckBox {
                    id: smartColorCheck

                    Kirigami.FormData.label: i18n("Smart color search:")
                    text: i18n("Set color filter from current wallpaper palette")
                }

                Kirigami.Separator {
                    Kirigami.FormData.label: i18n("Slideshow rules")
                    Kirigami.FormData.isSection: true
                }

                QtControls2.CheckBox {
                    id: pauseBatteryCheck

                    Kirigami.FormData.label: i18n("Battery pause:")
                    text: i18n("Pause slideshow on low battery")
                }

                QtControls2.SpinBox {
                    id: batteryThresholdSpin

                    Kirigami.FormData.label: i18n("Battery threshold (%):")
                    from: 5
                    to: 80
                    enabled: pauseBatteryCheck.checked
                }

                QtControls2.CheckBox {
                    id: pauseInactiveCheck

                    Kirigami.FormData.label: i18n("Screen lock pause:")
                    text: i18n("Pause the slideshow while the screen is locked")
                }

                QtControls2.CheckBox {
                    id: pauseIdleCheck

                    Kirigami.FormData.label: i18n("Idle pause:")
                    text: i18n("Pause when the session has been idle for several minutes")
                }

                QtControls2.SpinBox {
                    id: idlePauseMinutesSpin

                    Kirigami.FormData.label: i18n("Idle threshold (min):")
                    from: 1
                    to: 120
                    enabled: pauseIdleCheck.checked
                }

                QtControls2.SpinBox {
                    id: preloadCountSpin

                    Kirigami.FormData.label: i18n("Preload count:")
                    from: 0
                    to: 4
                    enabled: adaptivePreloadCheck.checked
                }

                QtControls2.CheckBox {
                    id: adaptivePreloadCheck

                    Kirigami.FormData.label: i18n("Adaptive preload:")
                    text: i18n("Reduce preloads when offline or metered")
                }

                QtControls2.CheckBox {
                    id: kenBurnsCheck

                    Kirigami.FormData.label: i18n("Ken Burns:")
                    text: i18n("Slow pan/zoom")
                }

                QtControls2.SpinBox {
                    id: kenBurnsSpeedSpin

                    Kirigami.FormData.label: i18n("Ken Burns speed:")
                    from: 1
                    to: 100
                    enabled: kenBurnsCheck.checked
                }

                QtControls2.CheckBox {
                    id: attributionCheck

                    Kirigami.FormData.label: i18n("Attribution:")
                    text: i18n("Show overlay on desktop")
                }

                QtControls2.ComboBox {
                    id: attributionCornerCombo

                    Kirigami.FormData.label: i18n("Attribution corner:")
                    textRole: "label"
                    valueRole: "value"
                    enabled: attributionCheck.checked
                    model: [{
                        "label": i18n("Bottom left"),
                        "value": "bottom-left"
                    }, {
                        "label": i18n("Bottom right"),
                        "value": "bottom-right"
                    }, {
                        "label": i18n("Top left"),
                        "value": "top-left"
                    }, {
                        "label": i18n("Top right"),
                        "value": "top-right"
                    }]
                }

                QtControls2.SpinBox {
                    id: attributionHideSpin

                    Kirigami.FormData.label: i18n("Auto-hide (sec):")
                    from: 0
                    to: 120
                    enabled: attributionCheck.checked
                }

                QtControls2.SpinBox {
                    id: attributionScaleSpin

                    Kirigami.FormData.label: i18n("Font scale (%):")
                    from: 70
                    to: 150
                    enabled: attributionCheck.checked
                }

                Kirigami.Separator {
                    Kirigami.FormData.label: i18n("Fun & Discovery")
                    Kirigami.FormData.isSection: true
                }

                QtControls2.CheckBox {
                    id: musicReactiveCheck

                    Kirigami.FormData.label: i18n("Music-reactive pacing:")
                    text: i18n("Speed up Ken Burns panning while music is playing (via MPRIS)")
                    enabled: kenBurnsCheck.checked
                }

                QtControls2.Label {
                    Kirigami.FormData.label: " "
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    visible: !kenBurnsCheck.checked
                    text: i18n("Enable Ken Burns above for music-reactive pacing to take effect.")
                }

                QtControls2.SpinBox {
                    id: musicReactiveIntensitySpin

                    Kirigami.FormData.label: i18n("Music reactivity (%):")
                    from: 0
                    to: 100
                    enabled: musicReactiveCheck.checked && kenBurnsCheck.checked
                }

                QtControls2.CheckBox {
                    id: weatherReactiveCheck

                    Kirigami.FormData.label: i18n("Weather-reactive search:")
                    text: i18n("Bias search toward rain/snow/storm tags matching local weather")
                }

                QtControls2.TextField {
                    id: weatherLocationField

                    Kirigami.FormData.label: i18n("Weather location:")
                    placeholderText: i18n("City name, or \"lat,lon\"")
                    enabled: weatherReactiveCheck.checked
                }

                QtControls2.Label {
                    Kirigami.FormData.label: " "
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    visible: weatherReactiveCheck.checked
                    text: i18n("Uses the free Open-Meteo API (no key required); location is geocoded once and cached.")
                }

                QtControls2.CheckBox {
                    id: achievementsCheck

                    Kirigami.FormData.label: i18n("Milestone toasts:")
                    text: i18n("Notify on view-count milestones and daily streaks")
                }

                QtControls2.CheckBox {
                    id: systemThemeSyncCheck

                    Kirigami.FormData.label: i18n("System theme sync:")
                    text: i18n("Also push the wallpaper accent to GTK apps and kdeglobals")
                }

                QtControls2.CheckBox {
                    id: imageEnhanceCheck

                    Kirigami.FormData.label: i18n("Image enhance:")
                    text: i18n("Apply brightness/contrast/saturation adjustments to the wallpaper")
                }

                QtControls2.SpinBox {
                    id: enhanceBrightnessSpin

                    Kirigami.FormData.label: i18n("Brightness:")
                    from: -100
                    to: 100
                    stepSize: 5
                    enabled: imageEnhanceCheck.checked
                    textFromValue: function(value) { return value + "%"; }
                    valueFromText: function(text) { return parseInt(text, 10) || 0; }
                }

                QtControls2.SpinBox {
                    id: enhanceContrastSpin

                    Kirigami.FormData.label: i18n("Contrast:")
                    from: -100
                    to: 100
                    stepSize: 5
                    enabled: imageEnhanceCheck.checked
                    textFromValue: function(value) { return value + "%"; }
                    valueFromText: function(text) { return parseInt(text, 10) || 0; }
                }

                QtControls2.SpinBox {
                    id: enhanceSaturationSpin

                    Kirigami.FormData.label: i18n("Saturation:")
                    from: -100
                    to: 300
                    stepSize: 5
                    enabled: imageEnhanceCheck.checked
                    textFromValue: function(value) { return value + "%"; }
                    valueFromText: function(text) { return parseInt(text, 10) || 0; }
                }

                QtControls2.Label {
                    Kirigami.FormData.label: " "
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    visible: imageEnhanceCheck.checked
                    text: i18n("0% means no change on each slider. Rendered client-side; the cached image on disk is not modified.")
                }

                QtControls2.Label {
                    Kirigami.FormData.label: " "
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    text: i18n("Swipe the panel widget thumbnail left/right (or use its menu) to like/dislike the current wallpaper's tags.")
                }

            }

        }

        // Advanced
        QtControls2.ScrollView {
            id: advancedScroll

            contentWidth: availableWidth
            clip: true

            Kirigami.FormLayout {
                width: advancedScroll.availableWidth

                Kirigami.Separator {
                    Kirigami.FormData.label: i18n("Network & Retries")
                    Kirigami.FormData.isSection: true
                }

                QtControls2.SpinBox {
                    id: requestTimeoutSpin

                    Kirigami.FormData.label: i18n("Request timeout (sec):")
                    from: 5
                    to: 120
                }

                QtControls2.SpinBox {
                    id: retryDelaySpin

                    Kirigami.FormData.label: i18n("Retry delay (sec):")
                    from: 1
                    to: 300
                }

                QtControls2.SpinBox {
                    id: retryAttemptsSpin

                    Kirigami.FormData.label: i18n("Max retry attempts:")
                    from: 1
                    to: 20
                }

                QtControls2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    text: i18n("Timeout is per request. Retries use the delay with exponential backoff, up to the max attempts.")
                }

                Kirigami.Separator {
                    Kirigami.FormData.label: i18n("Notifications")
                    Kirigami.FormData.isSection: true
                }

                QtControls2.CheckBox {
                    id: notifyRefreshCheck

                    Kirigami.FormData.label: i18n("On refresh:")
                    text: i18n("System notification when wallpaper changes")
                }

                QtControls2.CheckBox {
                    id: notifyErrorCheck

                    Kirigami.FormData.label: i18n("On errors:")
                    text: i18n("System notification for errors and warnings")
                }

                QtControls2.CheckBox {
                    id: statusBannerCheck

                    Kirigami.FormData.label: i18n("Desktop banner:")
                    text: i18n("Show status messages on the wallpaper")
                }

                Kirigami.Separator {
                    Kirigami.FormData.label: i18n("Performance")
                    Kirigami.FormData.isSection: true
                }

                QtControls2.CheckBox {
                    id: diskCacheCheck

                    Kirigami.FormData.label: i18n("Disk cache:")
                    text: i18n("Cache recent wallpapers locally; oldest unused are replaced")
                }

                QtControls2.SpinBox {
                    id: diskCacheSlotsSpin

                    Kirigami.FormData.label: i18n("Max cache slots:")
                    from: 5
                    to: 200
                    enabled: diskCacheCheck.checked
                }

                QtControls2.CheckBox {
                    id: cacheDownloadOriginalCheck

                    Kirigami.FormData.label: i18n("Cache original file:")
                    text: i18n("Download the full-resolution file from Wallhaven (requires curl)")
                    enabled: diskCacheCheck.checked
                }

                QtControls2.Label {
                    Kirigami.FormData.label: i18n("Per-monitor cache:")
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    text: liveWallpaper
                        ? i18n("Each screen keeps its own cache files (namespace %1). People/NSFW filters apply per monitor.", liveWallpaper.diskCacheNamespace || "default")
                        : i18n("Each monitor keeps separate cache files so filters on one screen do not leak wallpapers to another.")
                }

                QtControls2.CheckBox {
                    id: offlineCacheCheck

                    Kirigami.FormData.label: i18n("Offline fallback:")
                    text: i18n("Show cached wallpapers when the network fails")
                    enabled: diskCacheCheck.checked
                }

                QtControls2.CheckBox {
                    id: offlineOnlyCheck

                    Kirigami.FormData.label: i18n("Offline only:")
                    text: i18n("Never use the network; cycle cached wallpapers only")
                    enabled: diskCacheCheck.checked
                }

                QtControls2.CheckBox {
                    id: meteredCacheCheck

                    Kirigami.FormData.label: i18n("Metered network:")
                    text: i18n("Use cache only on cellular connections")
                    enabled: diskCacheCheck.checked
                }

                QtControls2.CheckBox {
                    id: upscaleCheck

                    Kirigami.FormData.label: i18n("Upscale low-res:")
                    text: i18n("Use an external AI upscaler for wallpapers smaller than your screen, if installed")
                    enabled: diskCacheCheck.checked
                }

                QtControls2.Label {
                    Kirigami.FormData.label: " "
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    visible: upscaleCheck.checked
                    text: i18n("Requires the D-Bus service and realesrgan-ncnn-vulkan on your PATH, and disk cache enabled above. Falls back to plain scaling when either is missing.")
                }

                QtControls2.Label {
                    Kirigami.FormData.label: i18n("Upscaler status:")
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    visible: upscaleCheck.checked
                    text: {
                        if (liveWallpaper === null)
                            return i18n("Apply Wallhaven as the wallpaper type to check.");
                        if (!root.dbusServiceOnline)
                            return i18n("D-Bus service offline; can't check.");
                        if (!root.upscalerStatusKnown)
                            return i18n("Checking…");
                        return root.upscalerAvailable
                            ? i18n("realesrgan-ncnn-vulkan detected.")
                            : i18n("Not found on PATH; using plain scaling. Install: github.com/xinntao/Real-ESRGAN/releases");
                    }
                }

                QtControls2.Button {
                    Kirigami.FormData.label: i18n("Re-upscale:")
                    text: i18n("Re-upscale cached wallpapers")
                    enabled: liveWallpaper !== null && upscaleCheck.checked && diskCacheCheck.checked
                    onClicked: {
                        if (liveWallpaper && liveWallpaper.reupscaleCachedWallpapers)
                            liveWallpaper.reupscaleCachedWallpapers();
                    }
                }

                QtControls2.Label {
                    Kirigami.FormData.label: " "
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    visible: upscaleCheck.checked
                    text: i18n("Applies the upscaler to wallpapers already in the disk cache whose native resolution falls short of your screen. Cache entries saved before this setting existed have no recorded resolution and are skipped; they'll be covered next time they're re-cached.")
                }

                QtControls2.CheckBox {
                    id: varietyCheck

                    Kirigami.FormData.label: i18n("Variety metadata:")
                    text: i18n("Write current wallpaper JSON for external tools")
                }

                QtControls2.TextField {
                    id: varietyFolderField

                    Kirigami.FormData.label: i18n("Variety folder:")
                    placeholderText: i18n("Optional path for Variety integration")
                }

                QtControls2.CheckBox {
                    id: varietySymlinkCheck

                    Kirigami.FormData.label: i18n("Variety symlink:")
                    text: i18n("Symlink cached wallpaper as wallhaven-current.jpg")
                    enabled: varietyFolderField.text !== ""
                }

                QtControls2.Button {
                    Kirigami.FormData.label: i18n("Variety bridge:")
                    text: i18n("Preview Variety search")
                    enabled: liveWallpaper !== null
                    onClicked: {
                        if (liveWallpaper && liveWallpaper.previewVarietySearch) {
                            liveWallpaper.previewVarietySearch(function(search) {
                                root.varietyPreviewSearch = search || i18n("(none found)");
                            });
                        }
                    }
                }

                QtControls2.Button {
                    Kirigami.FormData.label: " "
                    text: i18n("Apply Variety search to Wallhaven")
                    enabled: liveWallpaper !== null
                    onClicked: {
                        if (liveWallpaper && liveWallpaper.applyVarietySearch)
                            liveWallpaper.applyVarietySearch();

                    }
                }

                QtControls2.Label {
                    Kirigami.FormData.label: i18n("Variety preview:")
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    visible: root.varietyPreviewSearch !== ""
                    text: root.varietyPreviewSearch.indexOf("(") === 0
                        ? root.varietyPreviewSearch
                        : i18n("Would apply search: %1", root.varietyPreviewSearch)
                }

                QtControls2.CheckBox {
                    id: varietyWatchCheck

                    Kirigami.FormData.label: i18n("Variety watch:")
                    text: i18n("Watch Variety config for changes")
                    enabled: liveWallpaper !== null && root.dbusServiceOnline
                }

                QtControls2.Label {
                    Kirigami.FormData.label: i18n("Cache status:")
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    text: liveWallpaper ? i18n("%1 cached wallpaper(s)", liveWallpaper.diskCacheEntryCount) : i18n("Apply Wallhaven as the wallpaper type to see cache stats.")
                }

                QtControls2.Button {
                    Kirigami.FormData.label: i18n("Clear cache:")
                    text: i18n("Clear disk cache")
                    enabled: liveWallpaper !== null && diskCacheCheck.checked
                    onClicked: {
                        if (liveWallpaper && liveWallpaper.clearDiskCache) {
                            liveWallpaper.clearDiskCache();
                            root.refreshCacheModel();
                        }
                    }
                }

                Kirigami.Separator {
                    Kirigami.FormData.label: i18n("Cache Manager")
                    Kirigami.FormData.isSection: true
                }

                QtControls2.Button {
                    Kirigami.FormData.label: i18n("Refresh cache list:")
                    text: i18n("Refresh cached wallpapers")
                    onClicked: root.refreshCacheModel()
                }

                ListView {
                    id: cacheList

                    Kirigami.FormData.label: i18n("Cached:")
                    Layout.preferredWidth: parent.width
                    Layout.preferredHeight: Math.min(240, cacheModel.count * 52)
                    clip: true
                    model: cacheModel

                    delegate: RowLayout {
                        width: cacheList.width
                        spacing: Kirigami.Units.smallSpacing

                        Image {
                            Layout.preferredWidth: 64
                            Layout.preferredHeight: 40
                            fillMode: Image.PreserveAspectCrop
                            source: model.thumbUrl
                        }

                        QtControls2.Label {
                            Layout.fillWidth: true
                            text: "#" + model.id + (model.pinned ? " ★" : "")
                        }

                        QtControls2.Button {
                            text: model.pinned ? i18n("Unpin") : i18n("Pin")
                            onClicked: {
                                if (!liveWallpaper)
                                    return ;

                                if (model.pinned)
                                    liveWallpaper.unpinCacheId(model.id);
                                else
                                    liveWallpaper.pinCacheId(model.id);
                                root.refreshCacheModel();
                            }
                        }

                        QtControls2.Button {
                            text: i18n("Evict")
                            enabled: !model.pinned && liveWallpaper !== null
                            onClicked: {
                                liveWallpaper.evictCacheId(model.id);
                                root.refreshCacheModel();
                            }
                        }

                    }

                }

                Kirigami.Separator {
                    Kirigami.FormData.label: i18n("Diagnostics")
                    Kirigami.FormData.isSection: true
                }

                QtControls2.CheckBox {
                    id: debugLogCheck

                    Kirigami.FormData.label: i18n("Debug log:")
                    text: i18n("Write debug events to cache log file")
                }

                QtControls2.Button {
                    Kirigami.FormData.label: i18n("Debug log:")
                    text: i18n("Show recent log lines")
                    enabled: liveWallpaper !== null && debugLogCheck.checked
                    onClicked: {
                        if (liveWallpaper && liveWallpaper.showDebugLogTail)
                            liveWallpaper.showDebugLogTail();

                    }
                }

                QtControls2.Button {
                    Kirigami.FormData.label: i18n("Debug info:")
                    text: i18n("Copy debug info")
                    enabled: liveWallpaper !== null
                    onClicked: {
                        if (liveWallpaper && liveWallpaper.copyDebugInfo)
                            liveWallpaper.copyDebugInfo();

                    }
                }

                QtControls2.Button {
                    Kirigami.FormData.label: i18n("GitHub issue:")
                    text: i18n("Copy GitHub issue template")
                    enabled: liveWallpaper !== null
                    onClicked: {
                        if (liveWallpaper && liveWallpaper.copyGithubIssue)
                            liveWallpaper.copyGithubIssue();

                    }
                }

                QtControls2.Button {
                    Kirigami.FormData.label: i18n("Setup wizard:")
                    text: i18n("Show setup wizard again")
                    onClicked: root.resetSetupWizard()
                }

                QtControls2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    text: i18n("Images decode to screen size. Inactive crossfade layers are released, and settings preview writes are deferred.")
                }

                Kirigami.Separator {
                    Kirigami.FormData.label: i18n("Blocklist")
                    Kirigami.FormData.isSection: true
                }

                QtControls2.Label {
                    Kirigami.FormData.label: i18n("Blocked IDs:")
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    text: wallpaperConfiguration ? i18n("%1 blocked wallpaper(s)", Wallhaven.parseBlockedIds(wallpaperConfiguration.BlockedIdsJson || "[]").length) : i18n("Apply Wallhaven as the wallpaper type to manage the blocklist.")
                }

                QtControls2.Button {
                    Kirigami.FormData.label: i18n("Clear blocklist:")
                    text: i18n("Clear blocklist")
                    enabled: liveWallpaper !== null
                    onClicked: {
                        if (liveWallpaper && liveWallpaper.clearBlockedIds)
                            liveWallpaper.clearBlockedIds();

                    }
                }

                QtControls2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    text: i18n("Block the current wallpaper from desktop Wallpaper Actions. Blocked IDs are skipped during search.")
                }

                Kirigami.Separator {
                    Kirigami.FormData.label: i18n("External Control")
                    Kirigami.FormData.isSection: true
                }

                QtControls2.CheckBox {
                    id: controlBusCheck

                    Kirigami.FormData.label: i18n("Control bus:")
                    text: i18n("Accept commands from plasmoid/CLI")
                }

                QtControls2.CheckBox {
                    id: syncAdvanceCheck

                    Kirigami.FormData.label: i18n("Sync advance:")
                    text: i18n("Advance all monitors in the same group together")
                }

                QtControls2.TextField {
                    id: syncGroupField

                    Kirigami.FormData.label: i18n("Sync group:")
                    placeholderText: i18n("default")
                    enabled: syncAdvanceCheck.checked
                }

                QtControls2.CheckBox {
                    id: syncProfilesCheck

                    Kirigami.FormData.label: i18n("Sync profiles:")
                    text: i18n("Remember search settings per sync group")
                    enabled: syncAdvanceCheck.checked
                }

                QtControls2.Button {
                    Kirigami.FormData.label: i18n("Save profile:")
                    text: i18n("Save search profile for this sync group")
                    enabled: liveWallpaper !== null && syncProfilesCheck.checked
                    onClicked: {
                        if (liveWallpaper && liveWallpaper.saveSyncProfileForCurrentGroup)
                            liveWallpaper.saveSyncProfileForCurrentGroup();
                    }
                }

                QtControls2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    text: i18n("Per-monitor profiles: set a different sync group and search on each screen, or the same group to advance together.")
                }

                QtControls2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    text: i18n("Use tools/wallhaven-ctl.sh, D-Bus (tools/wallhaven-dbus.py), or the Wallhaven Control plasmoid.")
                }

                Kirigami.Separator {
                    Kirigami.FormData.label: i18n("Global shortcuts")
                    Kirigami.FormData.isSection: true
                }

                QtControls2.Label {
                    Kirigami.FormData.label: i18n("Keyboard shortcuts:")
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: i18n("Install Meta+Alt+arrow global shortcuts with: ./dev-helper.sh install-shortcuts")
                }

                Kirigami.Separator {
                    Kirigami.FormData.label: i18n("Wallpaper History")
                    Kirigami.FormData.isSection: true
                }

                QtControls2.Button {
                    Kirigami.FormData.label: i18n("Refresh history:")
                    text: i18n("Refresh history gallery")
                    onClicked: root.refreshHistoryModel()
                }

                ColumnLayout {
                    Kirigami.FormData.label: i18n("Recent:")
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    QtControls2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        opacity: 0.7
                        visible: historyModel.count === 0
                        text: liveWallpaper === null
                            ? i18n("Apply Wallhaven as the wallpaper type to see recent wallpapers.")
                            : i18n("No recent wallpapers yet. They appear here as the slideshow advances.")
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        visible: historyModel.count > 0

                        Repeater {
                            model: historyModel

                            delegate: Item {
                                width: 88
                                height: 56

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        if (liveWallpaper && liveWallpaper.showHistoryWallpaper)
                                            liveWallpaper.showHistoryWallpaper(model.id);

                                    }
                                }

                                Image {
                                    anchors.fill: parent
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    source: model.thumbUrl
                                }

                            }

                        }

                    }

                }

                QtControls2.Button {
                    Kirigami.FormData.label: i18n("Clear history:")
                    text: i18n("Clear wallpaper history")
                    enabled: liveWallpaper !== null
                    onClicked: {
                        if (liveWallpaper && liveWallpaper.clearWallpaperHistory) {
                            liveWallpaper.clearWallpaperHistory();
                            root.refreshHistoryModel();
                        }
                    }
                }

                Kirigami.Separator {
                    Kirigami.FormData.label: i18n("Settings Backup")
                    Kirigami.FormData.isSection: true
                }

                QtControls2.Button {
                    Kirigami.FormData.label: i18n("Export:")
                    text: i18n("Copy settings to clipboard")
                    onClicked: root.exportSettingsToClipboard()
                }

                QtControls2.Button {
                    Kirigami.FormData.label: i18n("Export file:")
                    text: i18n("Save settings to file…")
                    enabled: liveWallpaper !== null
                    onClicked: exportSettingsDialog.open()
                }

                QtControls2.Button {
                    Kirigami.FormData.label: i18n("Import:")
                    text: i18n("Import settings from file…")
                    onClicked: importSettingsDialog.open()
                }

                Kirigami.Separator {
                    Kirigami.FormData.label: i18n("Time of Day")
                    Kirigami.FormData.isSection: true
                }

                QtControls2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    text: i18n("Time-of-day searches apply in Search mode only (6am–8pm day, otherwise night).")
                }

                QtControls2.CheckBox {
                    id: timeOfDayCheck

                    Kirigami.FormData.label: i18n("Time of day:")
                    text: i18n("Use separate day/night searches")
                }

                QtControls2.TextField {
                    id: daySearchField

                    Kirigami.FormData.label: i18n("Day search:")
                    placeholderText: i18n("6am–8pm")
                    enabled: timeOfDayCheck.checked
                }

                QtControls2.TextField {
                    id: nightSearchField

                    Kirigami.FormData.label: i18n("Night search:")
                    placeholderText: i18n("8pm–6am")
                    enabled: timeOfDayCheck.checked
                }

                Kirigami.Separator {
                    Kirigami.FormData.label: i18n("Weekday Schedule")
                    Kirigami.FormData.isSection: true
                }

                QtControls2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    text: i18n("Weekday/weekend searches apply in Search mode when time-of-day is disabled.")
                }

                QtControls2.CheckBox {
                    id: scheduleCheck

                    Kirigami.FormData.label: i18n("Week schedule:")
                    text: i18n("Use separate weekday/weekend searches")
                    enabled: !timeOfDayCheck.checked
                }

                QtControls2.TextField {
                    id: weekdaySearchField

                    Kirigami.FormData.label: i18n("Weekday search:")
                    placeholderText: i18n("Mon–Fri")
                    enabled: scheduleCheck.checked && !timeOfDayCheck.checked
                }

                QtControls2.TextField {
                    id: weekendSearchField

                    Kirigami.FormData.label: i18n("Weekend search:")
                    placeholderText: i18n("Sat–Sun")
                    enabled: scheduleCheck.checked && !timeOfDayCheck.checked
                }

                Kirigami.Separator {
                    Kirigami.FormData.label: i18n("Time Capsule")
                    Kirigami.FormData.isSection: true
                }

                QtControls2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    text: i18n("Auto-switch the search on a specific date. One per line: date|search query|optional label. MM-DD repeats every year (birthdays, holidays); YYYY-MM-DD fires once.")
                }

                QtControls2.TextArea {
                    id: timeCapsuleField

                    Kirigami.FormData.label: i18n("Time capsules:")
                    placeholderText: i18n("12-25|christmas snow|Holiday surprise\n2026-09-01|back to school city")
                    text: root.timeCapsuleText()
                    Binding on text {
                        when: !timeCapsuleField.activeFocus
                        value: root.timeCapsuleText()
                    }
                    onEditingFinished: root.persistTimeCapsules(text)
                }

            }

        }

    }

    FileDialog {
        id: importSettingsDialog

        title: i18n("Import Wallhaven Settings")
        nameFilters: [i18n("JSON files (*.json)")]
        fileMode: FileDialog.OpenFile
        onAccepted: settingsImportLoader.load(selectedFile)
    }

    FileDialog {
        id: exportSettingsDialog

        title: i18n("Export Wallhaven Settings")
        nameFilters: [i18n("JSON files (*.json)")]
        fileMode: FileDialog.SaveFile
        defaultSuffix: "json"
        onAccepted: {
            if (liveWallpaper && liveWallpaper.exportSettingsToFile) {
                liveWallpaper.exportSettingsToFile(selectedFile);
                importExportStatus.text = i18n("Settings exported to file.");
            }
        }
    }

    QtObject {
        id: settingsImportLoader

        function localPathFromUrl(fileUrl) {
            var path = String(fileUrl || "");
            if (path.indexOf("file://") === 0) {
                path = path.substring(7);
            }
            return decodeURIComponent(path);
        }

        function load(fileUrl) {
            if (liveWallpaper && liveWallpaper.importSettingsFromFile) {
                liveWallpaper.importSettingsFromFile(localPathFromUrl(fileUrl));
                importExportStatus.text = i18n("Importing settings…");
                return;
            }
            importExportStatus.text = i18n("Apply Wallhaven as the wallpaper type to import settings.");
        }

    }

    Connections {
        target: liveWallpaper
        enabled: liveWallpaper !== null
        ignoreUnknownSignals: true

        function onWallpaperHistoryEntriesChanged() {
            root.refreshHistoryModel();
        }

        function onDiskCacheEntryCountChanged() {
            root.refreshCacheModel();
        }
    }

    Connections {
        function onWallpaperHistoryJsonChanged() {
            root.refreshHistoryModel();
        }

        function onPreviewImageChanged() {
            filePreviewImage.source = "";
            filePreviewImage.source = root.previewFileUrl;
        }

        function onPreviewThumbUrlChanged() {
            thumbPreviewImage.source = "";
            thumbPreviewImage.source = root.previewThumbUrl;
        }

        function onPreviewWallpaperIdChanged() {
            thumbPreviewImage.source = "";
            thumbPreviewImage.source = root.previewThumbUrl;
        }

        function onPreviewAttributionChanged() {
            // Aspect may change between portrait/landscape wallpapers.
            thumbPreviewImage.source = "";
            thumbPreviewImage.source = root.previewThumbUrl;
        }

        target: wallpaperConfiguration
        enabled: wallpaperConfiguration !== null
    }

}

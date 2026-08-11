import QtQuick
import QtQuick.Controls as QtControls2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    property alias cfg_SearchText: searchTextField.text
    property alias cfg_ApiKey: apiKeyField.text
    property alias cfg_BrowseMode: browseModeCombo.currentValue
    property alias cfg_CollectionUser: collectionUserField.text
    property alias cfg_CollectionId: collectionIdField.text
    property alias cfg_RandomInterval: intervalSpin.value
    property alias cfg_CrossfadeMs: crossfadeSpin.value
    property alias cfg_ImageQuality: qualityCombo.currentValue
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
    property alias cfg_KenBurnsEnabled: kenBurnsCheck.checked
    property alias cfg_KenBurnsSpeed: kenBurnsSpeedSpin.value
    property alias cfg_ShowAttribution: attributionCheck.checked
    property alias cfg_ClicksToAdvance: clicksAdvanceSpin.value
    property alias cfg_ClicksToGoBack: clicksBackSpin.value
    property alias cfg_TimeOfDayEnabled: timeOfDayCheck.checked
    property alias cfg_DaySearch: daySearchField.text
    property alias cfg_NightSearch: nightSearchField.text

    Kirigami.FormLayout {
        Layout.fillWidth: true

        Kirigami.Separator {
            Kirigami.FormData.label: i18n("Search & Source")
            Kirigami.FormData.isSection: true
        }

        QtControls2.ComboBox {
            id: browseModeCombo
            Kirigami.FormData.label: i18n("Browse mode:")
            textRole: "label"
            valueRole: "value"
            model: [
                { label: i18n("Search"), value: "search" },
                { label: i18n("Collection"), value: "collection" },
                { label: i18n("Favorites"), value: "favorites" },
            ]
        }

        QtControls2.TextField {
            id: searchTextField
            Kirigami.FormData.label: i18n("Search string:")
            placeholderText: i18n("Tags, keywords, e.g. nature anime")
        }

        QtControls2.TextField {
            id: apiKeyField
            Kirigami.FormData.label: i18n("API key:")
            placeholderText: i18n("Optional; required for NSFW and favorites")
            echoMode: TextInput.Password
        }

        QtControls2.TextField {
            id: collectionUserField
            Kirigami.FormData.label: i18n("Collection user:")
            placeholderText: i18n("Username for collection/favorites override")
        }

        QtControls2.TextField {
            id: collectionIdField
            Kirigami.FormData.label: i18n("Collection ID:")
        }

        Kirigami.Separator {
            Kirigami.FormData.label: i18n("Filters")
            Kirigami.FormData.isSection: true
        }

        QtControls2.CheckBox { id: generalCheck; Kirigami.FormData.label: i18n("General:"); text: i18n("Enabled") }
        QtControls2.CheckBox { id: animeCheck; Kirigami.FormData.label: i18n("Anime:"); text: i18n("Enabled") }
        QtControls2.CheckBox { id: peopleCheck; Kirigami.FormData.label: i18n("People:"); text: i18n("Enabled") }
        QtControls2.CheckBox { id: sfwCheck; Kirigami.FormData.label: i18n("SFW:"); text: i18n("Enabled") }
        QtControls2.CheckBox { id: sketchyCheck; Kirigami.FormData.label: i18n("Sketchy:"); text: i18n("Enabled") }
        QtControls2.CheckBox { id: nsfwCheck; Kirigami.FormData.label: i18n("NSFW:"); text: i18n("Enabled") }

        QtControls2.TextField {
            id: minWidthField
            Kirigami.FormData.label: i18n("Min width:")
            placeholderText: i18n("Empty = screen width")
        }

        QtControls2.TextField {
            id: minHeightField
            Kirigami.FormData.label: i18n("Min height:")
            placeholderText: i18n("Empty = screen height")
        }

        QtControls2.TextField {
            id: resolutionsField
            Kirigami.FormData.label: i18n("Exact resolutions:")
            placeholderText: i18n("e.g. 1920x1080,2560x1440")
        }

        QtControls2.ComboBox {
            id: ratioCombo
            Kirigami.FormData.label: i18n("Ratio:")
            textRole: "label"
            valueRole: "value"
            model: [
                { label: i18n("All wide"), value: "landscape" },
                { label: "16×9", value: "16x9" },
                { label: "21×9", value: "21x9" },
                { label: "32×9", value: "32x9" },
                { label: "All portrait", value: "portrait" },
                { label: "9×16", value: "9x16" },
            ]
        }

        QtControls2.ComboBox {
            id: colorCombo
            Kirigami.FormData.label: i18n("Color:")
            textRole: "label"
            valueRole: "value"
            model: [
                { label: i18n("Any"), value: "" },
                { label: i18n("Blue"), value: "0066cc" },
                { label: i18n("Green"), value: "77cc33" },
                { label: i18n("Red"), value: "cc0000" },
                { label: i18n("Purple"), value: "663399" },
                { label: i18n("Black"), value: "000000" },
            ]
        }

        QtControls2.ComboBox {
            id: sortingsCombo
            Kirigami.FormData.label: i18n("API sorting:")
            textRole: "label"
            valueRole: "value"
            model: [
                { label: "random", value: "random" },
                { label: "date_added", value: "date_added" },
                { label: "relevance", value: "relevance" },
                { label: "views", value: "views" },
                { label: "favorites", value: "favorites" },
                { label: "toplist", value: "toplist" },
            ]
        }

        QtControls2.ComboBox {
            id: topRangeCombo
            Kirigami.FormData.label: i18n("Toplist range:")
            textRole: "label"
            valueRole: "value"
            model: [
                { label: "1d", value: "1d" },
                { label: "1w", value: "1w" },
                { label: "1M", value: "1M" },
                { label: "3M", value: "3M" },
                { label: "1y", value: "1y" },
            ]
        }

        QtControls2.ComboBox {
            id: localSortingsCombo
            Kirigami.FormData.label: i18n("Local sorting:")
            textRole: "label"
            valueRole: "value"
            model: [
                { label: i18n("Ascending"), value: "ascending" },
                { label: i18n("Descending"), value: "descending" },
                { label: i18n("Random"), value: "random" },
            ]
        }

        QtControls2.ComboBox {
            id: orderCombo
            Kirigami.FormData.label: i18n("API order:")
            textRole: "label"
            valueRole: "value"
            model: [
                { label: i18n("Descending"), value: "desc" },
                { label: i18n("Ascending"), value: "asc" },
            ]
        }

        QtControls2.CheckBox {
            id: blacklistCheck
            Kirigami.FormData.label: i18n("Account blacklist:")
            text: i18n("Apply Wallhaven tag blacklist")
        }

        QtControls2.CheckBox {
            id: dedupCheck
            Kirigami.FormData.label: i18n("Duplicates:")
            text: i18n("Avoid recent duplicates (session)")
        }

        Kirigami.Separator {
            Kirigami.FormData.label: i18n("Playback")
            Kirigami.FormData.isSection: true
        }

        QtControls2.SpinBox {
            id: intervalSpin
            Kirigami.FormData.label: i18n("Interval (min):")
            from: 0
            to: 10080
        }

        QtControls2.SpinBox {
            id: clicksAdvanceSpin
            Kirigami.FormData.label: i18n("Clicks forward:")
            from: 1
            to: 10
        }

        QtControls2.SpinBox {
            id: clicksBackSpin
            Kirigami.FormData.label: i18n("Clicks back:")
            from: 0
            to: 10
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
            model: [
                { label: i18n("Small"), value: "small" },
                { label: i18n("Large"), value: "large" },
                { label: i18n("Original"), value: "original" },
            ]
        }

        QtControls2.SpinBox {
            id: crossfadeSpin
            Kirigami.FormData.label: i18n("Crossfade (ms):")
            from: 0
            to: 3000
            stepSize: 100
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
        }

        QtControls2.CheckBox {
            id: attributionCheck
            Kirigami.FormData.label: i18n("Attribution:")
            text: i18n("Show overlay")
        }

        Kirigami.Separator {
            Kirigami.FormData.label: i18n("Time of Day")
            Kirigami.FormData.isSection: true
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
        }

        QtControls2.TextField {
            id: nightSearchField
            Kirigami.FormData.label: i18n("Night search:")
        }
    }
}

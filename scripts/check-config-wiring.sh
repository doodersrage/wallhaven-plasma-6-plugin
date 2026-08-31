#!/usr/bin/env bash
# Fail if user-facing settings are missing cfg_* bindings or engine.configObject() keys.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

MAIN_XML="${ROOT}/contents/config/main.xml"
CONFIG_QML="${ROOT}/contents/ui/config.qml"
MAIN_QML="${ROOT}/contents/ui/main.qml"

# Runtime / engine-managed — no settings UI alias required.
INTERNAL_KEYS=(
    SeenIdsJson DiskCacheIndexJson CacheNamespace
    PreviewImage PreviewWallpaperId PreviewThumbUrl PreviewAttribution PreviewWallpaperDetails
    ApiKeyValid CollectionRotationIndex
    WeatherResolvedLat WeatherResolvedLon WeatherTagCache
    TimeCapsuleLastAppliedDate
    TotalWallpapersViewed CurrentStreakDays LastViewDateStr
    BlockedIdsJson PinnedCacheIdsJson
    ConfigSchemaVersion
)

# Must appear in engine.configObject() or search/effects silently no-op.
CONFIG_OBJECT_REQUIRED=(
    PreferSharpMatches WeatherReactiveEnabled WeatherTagCache
    TagFavoritesJson TagBlocklistJson FileTypeFilter DedupEnabled
    BrowseMode CollectionRotationEnabled CollectionRotationJson
    ScheduleEnabled WeekdaySearch WeekendSearch
    OfflineOnlyMode MeteredCacheOnly WallpaperOfDayEnabled
    SmartOfflineEnabled OfflinePlaylistPinnedOnly PinnedCacheIdsJson
    SmartOfflineDayAware
)

extract_xml_keys() {
    grep -oP '(?<=entry name=")[^"]+' "${MAIN_XML}" | sort -u
}

extract_cfg_keys() {
    # Matches: property alias cfg_Foo, property string cfg_Foo, property int cfg_Foo, …
    grep -oP 'property\s+(?:alias|[A-Za-z0-9_]+)\s+cfg_\K[A-Za-z0-9]+' "${CONFIG_QML}" | sort -u
}

extract_config_object_keys() {
    awk '/function configObject\(\)/,/^        \}$/ {
        if (match($0, /([A-Za-z0-9_]+): cfg\./, m)) print m[1]
    }' "${MAIN_QML}" | sort -u
}

xml_keys="$(extract_xml_keys)"
cfg_keys="$(extract_cfg_keys)"
object_keys="$(extract_config_object_keys)"

errors=0

echo "==> Config wiring audit"

for key in "${CONFIG_OBJECT_REQUIRED[@]}"; do
    if ! grep -qx "${key}" <<< "${object_keys}"; then
        echo "ERROR: ${key} missing from engine.configObject() in contents/ui/main.qml" >&2
        errors=$((errors + 1))
    fi
done

while IFS= read -r key; do
    [[ -z "${key}" ]] && continue
    skip=0
    for internal in "${INTERNAL_KEYS[@]}"; do
        if [[ "${key}" == "${internal}" ]]; then
            skip=1
            break
        fi
    done
    [[ ${skip} -eq 1 ]] && continue
    if ! grep -qx "${key}" <<< "${cfg_keys}"; then
        echo "ERROR: ${key} in main.xml has no cfg_* binding in config.qml" >&2
        errors=$((errors + 1))
    fi
done <<< "${xml_keys}"

if [[ ${errors} -gt 0 ]]; then
    echo "==> Config wiring FAILED (${errors} error(s))" >&2
    exit 1
fi

echo "==> Config wiring OK"

// ControlCenterWidget.qml — Control Center shortcut tile: bolt icon with a
// live tooltip (remaining % + reset countdown). Click toggles the detail
// panel, right-click opens plugin settings.
//
// Follows the reference plugin's control-center pattern (NIconButtonHot).
import QtQuick
import Quickshell
import qs.Services.UI
import qs.Widgets
import "Logic.js" as Logic

NIconButtonHot {
  id: root

  property ShellScreen screen
  property var pluginApi: null

  readonly property var mainInstance: pluginApi ? pluginApi.mainInstance : null
  readonly property var entry: mainInstance ? mainInstance.entry : null
  readonly property bool hasKey: mainInstance ? mainInstance.hasKey : false
  readonly property real now: mainInstance ? mainInstance.now : 0

  readonly property var session: entry ? Logic.sectionByKey(entry, "session") : null
  readonly property int usedPct: session && session.percent !== null && session.percent !== undefined ? session.percent : -1
  readonly property int leftPct: usedPct >= 0 ? 100 - usedPct : -1

  icon: "bolt"

  function getTooltipText() {
    if (!pluginApi)
      return "AI Usage";
    if (!hasKey)
      return pluginApi.tr("desktop_widget.no_key");
    if (leftPct < 0)
      return pluginApi.tr("desktop_widget.loading");
    if (session && session.resetAt > 0) {
      var dur = Logic.formatDuration(Logic.remainingMs(session.resetAt, now), pluginApi.tr("units.h"), pluginApi.tr("units.m"));
      return pluginApi.tr("bar_widget.tooltip").replace("{percent}", String(leftPct)).replace("{duration}", dur);
    }
    return pluginApi.tr("desktop_widget.remaining").replace("{percent}", String(leftPct));
  }

  tooltipText: getTooltipText()

  onClicked: {
    if (pluginApi)
      pluginApi.togglePanel(screen);
  }

  onRightClicked: {
    if (pluginApi && pluginApi.manifest)
      BarService.openPluginSettings(screen, pluginApi.manifest);
  }
}

// DesktopWidget.qml — draggable desktop card: session usage bar with a live
// reset countdown, optional weekly quota row.
//
// Sizing follows the reference plugin: every dimension goes through
// widgetScale with Math.round.
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Modules.DesktopWidgets
import qs.Services.UI
import qs.Widgets
import "Logic.js" as Logic

DraggableDesktopWidget {
  id: root

  property var pluginApi: null

  showBackground: pluginApi && pluginApi.pluginSettings && pluginApi.pluginSettings.showBackground !== undefined ? pluginApi.pluginSettings.showBackground : (pluginApi && pluginApi.manifest ? pluginApi.manifest.metadata.defaultSettings.showBackground : true)

  readonly property var mainInstance: pluginApi ? pluginApi.mainInstance : null
  readonly property var entry: mainInstance ? mainInstance.entry : null
  readonly property string lastError: mainInstance ? mainInstance.lastError : ""
  readonly property bool fetching: mainInstance ? mainInstance.fetching : false
  readonly property bool hasKey: mainInstance ? mainInstance.hasKey : false
  readonly property real now: mainInstance ? mainInstance.now : 0
  readonly property bool showWeekly: mainInstance ? mainInstance.showWeekly : true

  readonly property var trFn: pluginApi ? function (key) {
    return pluginApi.tr(key);
  } : null
  readonly property string hUnit: trFn ? trFn("units.h") : "h"
  readonly property string mUnit: trFn ? trFn("units.m") : "m"

  readonly property var session: entry ? Logic.sectionByKey(entry, "session") : null
  readonly property var weekly: entry ? Logic.sectionByKey(entry, "weekly") : null

  // session.percent is USED percent; the card headlines what is LEFT.
  readonly property int usedPct: session && session.percent !== null && session.percent !== undefined ? session.percent : -1
  readonly property int leftPct: usedPct >= 0 ? 100 - usedPct : -1
  readonly property string plan: entry && entry.plan ? entry.plan : ""

  readonly property color accentColor: {
    if (!session)
      return Color.mOnSurfaceVariant;
    switch (session.severity) {
    case "critical":
      return Color.mError;
    case "high":
      return "#FFB020";
    case "mid":
      return Color.mPrimary;
    default:
      return Color.mTertiary;
    }
  }

  // Scaled dimensions
  readonly property int scaledMarginM: Math.round(Style.marginM * widgetScale)
  readonly property int scaledMarginS: Math.round(Style.marginS * widgetScale)
  readonly property int scaledMarginL: Math.round(Style.marginL * widgetScale)
  readonly property int scaledFontSizeS: Math.round(Style.fontSizeS * widgetScale)
  readonly property int scaledFontSizeM: Math.round(Style.fontSizeM * widgetScale)
  readonly property int scaledFontSizeL: Math.round(Style.fontSizeL * widgetScale)
  readonly property int scaledFontSizeXL: Math.round(Style.fontSizeXL * widgetScale)
  readonly property int scaledRadiusM: Math.round(Style.radiusM * widgetScale)
  readonly property int scaledBarHeight: Math.max(4, Math.round(8 * widgetScale))

  readonly property string resetLine: {
    if (!trFn)
      return "";
    if (!hasKey)
      return trFn("desktop_widget.no_key");
    if (!session)
      return fetching ? trFn("desktop_widget.loading") : (lastError !== "" ? trFn("desktop_widget.error") : trFn("desktop_widget.loading"));
    if (!(session.resetAt > 0))
      return "";
    var time = Qt.formatDateTime(new Date(session.resetAt), "HH:mm");
    var dur = Logic.formatDuration(Logic.remainingMs(session.resetAt, now), hUnit, mUnit);
    return trFn("desktop_widget.reset_in").replace("{duration}", dur) + " · " + trFn("desktop_widget.reset_at").replace("{time}", time);
  }

  implicitWidth: Math.round(260 * widgetScale)
  implicitHeight: contentCol.implicitHeight + scaledMarginM * 2

  Component.onCompleted: {
    if (pluginApi)
      Logger.i("AiUsage", "desktop widget initialized");
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    // Dragging is handled by DraggableDesktopWidget; only react to plain
    // clicks so the click-to-panel does not fight the drag gesture.
    onClicked: function (mouse) {
      if (mouse.button !== Qt.LeftButton)
        return;
      if (!root.hasKey && root.pluginApi) {
        BarService.openPluginSettings(root.screen, root.pluginApi.manifest);
        return;
      }
      if (root.pluginApi)
        root.pluginApi.openPanel(root.screen, root);
    }
  }

  ColumnLayout {
    id: contentCol
    anchors.fill: parent
    anchors.margins: scaledMarginM
    spacing: scaledMarginS

    // --- header: icon · title/plan … big remaining % -----------------------
    RowLayout {
      Layout.fillWidth: true
      spacing: scaledMarginS

      NIcon {
        icon: "bolt"
        color: root.accentColor
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        NText {
          Layout.fillWidth: true
          text: root.trFn ? root.trFn("desktop_widget.title") : "z.ai"
          color: Color.mOnSurface
          pointSize: root.scaledFontSizeM
          elide: Text.ElideRight
        }

        NText {
          Layout.fillWidth: true
          visible: root.plan !== ""
          text: root.plan
          color: Color.mOnSurfaceVariant
          pointSize: root.scaledFontSizeS
          elide: Text.ElideRight
        }
      }

      NText {
        visible: root.leftPct >= 0
        text: root.leftPct + "%"
        color: root.accentColor
        pointSize: root.scaledFontSizeXL
        font.bold: true
      }
    }

    // --- session bar -------------------------------------------------------
    UsageBar {
      Layout.fillWidth: true
      Layout.preferredHeight: root.scaledBarHeight
      visible: root.usedPct >= 0
      pct: root.usedPct
      severity: root.session ? root.session.severity : "low"
    }

    // --- reset line / state ------------------------------------------------
    NText {
      Layout.fillWidth: true
      visible: text !== ""
      text: root.resetLine
      color: root.hasKey ? Color.mOnSurfaceVariant : Color.mError
      pointSize: root.scaledFontSizeS
      elide: Text.ElideRight
    }

    NText {
      Layout.fillWidth: true
      visible: !root.hasKey && root.trFn !== null
      text: root.trFn ? root.trFn("desktop_widget.no_key_hint") : ""
      color: Color.mOnSurfaceVariant
      pointSize: root.scaledFontSizeS
      opacity: 0.7
      elide: Text.ElideRight
    }

    // --- optional weekly row ------------------------------------------------
    RowLayout {
      Layout.fillWidth: true
      visible: root.showWeekly && root.weekly !== null
      spacing: scaledMarginS

      NText {
        Layout.fillWidth: true
        text: root.trFn ? root.trFn("panel.weekly_label") : ""
        color: Color.mOnSurfaceVariant
        pointSize: root.scaledFontSizeS
        elide: Text.ElideRight
      }

      NText {
        visible: root.weekly && root.weekly.value !== ""
        text: root.weekly ? root.weekly.value : ""
        color: Color.mOnSurface
        pointSize: root.scaledFontSizeS
        font.bold: true
      }
    }
  }
}

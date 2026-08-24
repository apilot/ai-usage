// BarWidget.qml — compact bar capsule: bolt icon + remaining % (+ mini bar on
// wide bars). Click opens the panel.
//
// Layout follows the reference plugin's bar widget (capsule metrics from
// Style, vertical/horizontal awareness).
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets
import "Logic.js" as Logic

Item {
  id: root

  property var pluginApi: null

  property ShellScreen screen
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  // Bar positioning properties
  readonly property string screenName: screen ? screen.name : ""
  readonly property string barPosition: screenName !== "" ? Settings.getBarPositionForScreen(screenName) : ""
  readonly property bool isVertical: barPosition === "left" || barPosition === "right"
  readonly property real barHeight: screenName !== "" ? Style.getBarHeightForScreen(screenName) : 30
  readonly property real capsuleHeight: screenName !== "" ? Style.getCapsuleHeightForScreen(screenName) : 24
  readonly property real barFontSize: screenName !== "" ? Style.getBarFontSizeForScreen(screenName) : 11

  readonly property var mainInstance: pluginApi ? pluginApi.mainInstance : null
  readonly property var entry: mainInstance ? mainInstance.entry : null
  readonly property bool hasKey: mainInstance ? mainInstance.hasKey : false
  readonly property real now: mainInstance ? mainInstance.now : 0

  readonly property var session: entry ? Logic.sectionByKey(entry, "session") : null
  readonly property int usedPct: session && session.percent !== null && session.percent !== undefined ? session.percent : -1
  readonly property int leftPct: usedPct >= 0 ? 100 - usedPct : -1

  readonly property color contentColor: mouseArea.containsMouse ? Color.mOnHover : Color.mOnSurface

  readonly property string capsuleText: {
    if (!hasKey)
      return "…";
    if (leftPct < 0)
      return "…";
    return leftPct + "%";
  }

  readonly property string tooltipText: {
    if (!pluginApi || !hasKey || !(session && session.resetAt > 0))
      return "z.ai";
    var dur = Logic.formatDuration(Logic.remainingMs(session.resetAt, now), pluginApi.tr("units.h"), pluginApi.tr("units.m"));
    return pluginApi.tr("bar_widget.tooltip").replace("{percent}", String(leftPct)).replace("{duration}", dur);
  }

  readonly property real contentWidth: root.isVertical ? root.capsuleHeight : horizontalRow.implicitWidth + Style.marginM * 2
  readonly property real contentHeight: root.capsuleHeight

  implicitWidth: contentWidth
  implicitHeight: contentHeight

  // Visual capsule - pixel-perfect centered
  Rectangle {
    id: visualCapsule
    x: Style.pixelAlignCenter(parent.width, width)
    y: Style.pixelAlignCenter(parent.height, height)
    width: root.contentWidth
    height: root.contentHeight
    radius: Style.radiusL
    color: mouseArea.containsMouse ? Color.mHover : Style.capsuleColor
    border.color: Style.capsuleBorderColor
    border.width: Style.capsuleBorderWidth

    Row {
      id: horizontalRow
      anchors.centerIn: parent
      spacing: Style.marginS
      visible: !root.isVertical

      NIcon {
        anchors.verticalCenter: parent.verticalCenter
        icon: "bolt"
        applyUiScale: false
        color: root.contentColor
      }

      NText {
        anchors.verticalCenter: parent.verticalCenter
        text: root.capsuleText
        color: root.contentColor
        pointSize: root.barFontSize
        applyUiScale: false
      }
    }

    Column {
      anchors.centerIn: parent
      spacing: 2
      visible: root.isVertical

      NIcon {
        anchors.horizontalCenter: parent.horizontalCenter
        icon: "bolt"
        applyUiScale: false
        color: root.contentColor
      }

      NText {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.capsuleText
        color: root.contentColor
        pointSize: Math.max(7, root.barFontSize - 2)
        applyUiScale: false
      }
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    onClicked: function (mouse) {
      if (mouse.button === Qt.LeftButton) {
        if (root.pluginApi)
          root.pluginApi.openPanel(root.screen, root);
      }
    }
  }
}

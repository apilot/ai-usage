// BarWidget.qml v2 — compact bar capsule: gauge icon + active provider
// remaining % (balance string for money vendors). Click opens the panel.
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
  readonly property var activeEntry: mainInstance ? mainInstance.activeEntry : null
  readonly property bool hasProviders: mainInstance ? mainInstance.providers.length > 0 : false

  readonly property int leftPct: mainInstance && activeEntry ? mainInstance.leftPercent(activeEntry) : -1

  readonly property color contentColor: mouseArea.containsMouse ? Color.mOnHover : Color.mOnSurface

  readonly property string capsuleText: {
    if (!hasProviders)
      return "…";
    if (leftPct >= 0)
      return leftPct + "%";
    if (activeEntry) {
      var h = mainInstance.headlineSection(activeEntry);
      if (h && h.value !== "")
        return h.value;
    }
    return "…";
  }

  readonly property string tooltipText: {
    if (!pluginApi || !mainInstance || !hasProviders)
      return "AI";
    var label = mainInstance.displayLabel(mainInstance.activeProvider);
    if (!activeEntry)
      return label;
    var h = mainInstance.headlineSection(activeEntry);
    if (h && h.resetAt > 0) {
      var dur = Logic.formatDuration(Logic.remainingMs(h.resetAt, mainInstance.now), pluginApi.tr("units.h"), pluginApi.tr("units.m"));
      return label + " · " + pluginApi.tr("bar_widget.tooltip").replace("{percent}", String(leftPct)).replace("{duration}", dur);
    }
    if (h && h.value !== "")
      return label + " · " + h.value;
    return label;
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
        icon: "gauge"
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
        icon: "gauge"
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

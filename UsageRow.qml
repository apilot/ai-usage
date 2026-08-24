// UsageRow.qml — one metric row: label … value%, usage bar, optional detail
// and live reset countdown.
//
// Ported from ai-usagebar (MIT) kde-plasmoid/package/contents/ui/UsageRow.qml
// to qs.Commons: PlasmaComponents.Label → NText, Kirigami.Units → Style.*.
// `section` is a Logic.js section object ({type,key,percent,resetAt,severity,…}).
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import "Logic.js" as Logic

ColumnLayout {
  id: item

  property var section: null
  property string label: ""
  property string detail: ""
  property real now: 0            // ms; updated by the parent's tick timer
  property bool showBar: true
  property var tr: null           // pluginApi.tr
  property string hUnit: "h"
  property string mUnit: "m"

  readonly property bool isMetric: section && section.type === "metric"
  readonly property int clampedPct: isMetric && section.percent !== null && section.percent !== undefined ? Math.max(0, Math.min(100, section.percent)) : 0
  readonly property real resetMsLeft: isMetric && section.resetAt > 0 ? Logic.remainingMs(section.resetAt, now) : 0
  readonly property string resetText: {
    if (!isMetric || !(section.resetAt > 0) || !tr)
      return "";
    var time = Qt.formatDateTime(new Date(section.resetAt), "HH:mm");
    var dur = Logic.formatDuration(resetMsLeft, hUnit, mUnit);
    var tpl = String(tr("panel.resets"));
    return tpl.replace("{time}", time).replace("{duration}", dur);
  }

  readonly property color valueColor: isMetric && section.severity === "critical" ? Color.mError : Color.mOnSurface

  spacing: 0

  RowLayout {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginS
    spacing: Style.marginS

    NText {
      Layout.fillWidth: true
      text: item.label
      color: Color.mOnSurface
      pointSize: Style.fontSizeM
      elide: Text.ElideRight
    }

    NText {
      visible: text !== ""
      text: {
        if (!item.isMetric)
          return "";
        return item.section.percent !== null && item.section.percent !== undefined ? item.section.percent + "%" : item.section.value;
      }
      color: item.valueColor
      pointSize: Style.fontSizeL
      font.bold: true
    }
  }

  UsageBar {
    Layout.fillWidth: true
    Layout.topMargin: Math.round(Style.marginS / 2)
    visible: item.showBar && item.isMetric && item.section.percent !== null && item.section.percent !== undefined
    pct: item.clampedPct
    severity: item.isMetric ? item.section.severity : "low"
  }

  NText {
    Layout.fillWidth: true
    visible: text !== ""
    text: item.detail
    color: Color.mOnSurfaceVariant
    pointSize: Style.fontSizeS
    opacity: 0.8
    wrapMode: Text.WordWrap
  }

  NText {
    Layout.fillWidth: true
    visible: text !== ""
    text: item.resetText
    color: Color.mOnSurfaceVariant
    pointSize: Style.fontSizeS
    opacity: 0.8
  }
}

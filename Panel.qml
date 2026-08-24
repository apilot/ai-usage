// Panel.qml — full report panel: header (plan + refresh), status surface
// when something is wrong, session/weekly usage rows, MCP-tools breakdown
// and a "updated N ago" footer.
//
// Structure ported from ai-usagebar (MIT) kde-plasmoid FullRepresentation.qml;
// themed with qs.Commons tokens, content laid out like the reference todo
// plugin's Panel entry point.
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Services.UI
import qs.Widgets
import "Logic.js" as Logic

Item {
  id: root

  property var pluginApi: null

  readonly property var geometryPlaceholder: panelContainer
  property real contentPreferredWidth: 380 * Style.uiScaleRatio
  property real contentPreferredHeight: contentCol.implicitHeight + Style.marginL * 2
  readonly property bool allowAttach: true
  anchors.fill: parent

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
  readonly property var tools: entry ? Logic.sectionByKey(entry, "tools") : null

  readonly property string statusMessage: {
    if (!trFn)
      return "";
    if (!hasKey)
      return trFn("panel.no_key");
    if (!entry && fetching)
      return trFn("panel.never");
    if (!entry && lastError !== "")
      return lastError;
    return "";
  }

  function updatedText() {
    if (!trFn || !entry)
      return "";
    var ago = Logic.formatDuration(Date.now() - entry.fetchedAt, hUnit, mUnit);
    var text = trFn("panel.updated").replace("{duration}", ago);
    if (lastError !== "")
      text += trFn("panel.cached");
    return text;
  }

  Rectangle {
    id: panelContainer
    anchors.fill: parent
    color: "transparent"
    radius: Style.radiusM

    ColumnLayout {
      id: contentCol
      anchors.fill: parent
      anchors.margins: Style.marginM
      spacing: Style.marginS

      // --- header ----------------------------------------------------------
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        NIcon {
          icon: "bolt"
          color: Color.mPrimary
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 0

          NText {
            Layout.fillWidth: true
            text: root.trFn ? root.trFn("panel.header") : ""
            color: Color.mOnSurface
            pointSize: Style.fontSizeXL
            font.bold: true
            elide: Text.ElideRight
          }

          NText {
            Layout.fillWidth: true
            visible: root.entry && root.entry.plan !== ""
            text: root.entry && root.entry.plan ? (root.trFn ? root.trFn("panel.plan").replace("{plan}", root.entry.plan) : root.entry.plan) : ""
            color: Color.mOnSurfaceVariant
            pointSize: Style.fontSizeS
            elide: Text.ElideRight
          }
        }

        NIconButton {
          icon: "refresh"
          enabled: !root.fetching && root.hasKey
          onClicked: {
            if (root.mainInstance)
              root.mainInstance.fetchNow();
          }
        }
      }

      // --- status surface ----------------------------------------------------
      Rectangle {
        Layout.fillWidth: true
        visible: root.statusMessage !== ""
        implicitHeight: statusText.implicitHeight + Style.marginM * 2
        radius: Style.radiusS
        color: Qt.rgba(Color.mError.r, Color.mError.g, Color.mError.b, 0.09)
        border.width: 1
        border.color: Qt.rgba(Color.mError.r, Color.mError.g, Color.mError.b, 0.35)

        NText {
          id: statusText
          anchors.fill: parent
          anchors.margins: Style.marginS
          text: root.statusMessage
          color: Color.mOnSurface
          pointSize: Style.fontSizeS
          wrapMode: Text.WordWrap
        }
      }

      // --- usage rows ---------------------------------------------------------
      NDivider {
        Layout.fillWidth: true
        visible: root.session !== null || root.weekly !== null
      }

      NText {
        Layout.fillWidth: true
        visible: root.session !== null || root.weekly !== null
        text: root.trFn ? root.trFn("panel.section_title") : ""
        color: Color.mOnSurfaceVariant
        pointSize: Style.fontSizeXS
      }

      UsageRow {
        Layout.fillWidth: true
        visible: root.session !== null
        section: root.session
        label: root.trFn ? root.trFn("panel.session_label") : ""
        detail: {
          if (!root.trFn || !root.session || root.session.percent === null || root.session.percent === undefined)
            return "";
          return root.trFn("panel.remaining").replace("{percent}", String(100 - root.session.percent));
        }
        now: root.now
        tr: root.trFn
        hUnit: root.hUnit
        mUnit: root.mUnit
      }

      UsageRow {
        Layout.fillWidth: true
        visible: root.showWeekly && root.weekly !== null
        section: root.weekly
        label: root.trFn ? root.trFn("panel.weekly_label") : ""
        detail: {
          if (!root.trFn || !root.weekly || root.weekly.detail === "")
            return "";
          return root.weekly.value + " · −" + root.weekly.detail;
        }
        now: root.now
        tr: root.trFn
        hUnit: root.hUnit
        mUnit: root.mUnit
      }

      // --- MCP tools breakdown --------------------------------------------------
      ColumnLayout {
        Layout.fillWidth: true
        visible: root.showWeekly && root.tools !== null
        spacing: 0

        NText {
          Layout.fillWidth: true
          Layout.topMargin: Style.marginS
          text: root.trFn ? root.trFn("panel.tools_label") : ""
          color: Color.mOnSurfaceVariant
          pointSize: Style.fontSizeXS
        }

        Repeater {
          model: root.tools ? root.tools.body : []

          NText {
            required property string modelData
            Layout.fillWidth: true
            Layout.topMargin: Style.marginXXS
            text: modelData
            color: Color.mOnSurfaceVariant
            pointSize: Style.fontSizeS
            opacity: 0.8
          }
        }
      }

      NText {
        Layout.fillWidth: true
        visible: text !== ""
        horizontalAlignment: Text.AlignHCenter
        text: root.updatedText()
        color: Color.mOnSurfaceVariant
        pointSize: Style.fontSizeXS
        opacity: 0.8
      }
    }
  }
}

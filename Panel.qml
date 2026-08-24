// Panel.qml v2 — provider tabs (ported from ai-usagebar FullRepresentation's
// vendor tab strip, failing providers stay visible with a ⚠), full metrics of
// the selected provider, MCP/breakdown blocks, updated-N-ago footer.
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

  property string selectedId: ""

  readonly property var mainInstance: pluginApi ? pluginApi.mainInstance : null
  readonly property var providers: mainInstance ? mainInstance.providers : []
  readonly property var entries: mainInstance ? mainInstance.entries : ({})
  readonly property var errors: mainInstance ? mainInstance.errors : ({})
  readonly property var fetching: mainInstance ? mainInstance.fetching : ({})
  readonly property real now: mainInstance ? mainInstance.now : 0

  readonly property string currentId: {
    if (selectedId !== "" && providers.some(function (p) { return p.id === selectedId; }))
      return selectedId;
    return mainInstance ? mainInstance.activeProviderId : "";
  }
  readonly property var currentProvider: {
    for (var i = 0; i < providers.length; i++) {
      if (providers[i].id === currentId)
        return providers[i];
    }
    return null;
  }
  readonly property var currentEntry: entries[currentId] !== undefined ? entries[currentId] : null
  readonly property string currentError: errors[currentId] !== undefined ? errors[currentId] : ""

  readonly property var trFn: pluginApi ? function (key) {
    return pluginApi.tr(key);
  } : null
  readonly property string hUnit: trFn ? trFn("units.h") : "h"
  readonly property string mUnit: trFn ? trFn("units.m") : "m"

  readonly property var validInfo: {
    if (!currentProvider || !currentProvider.validUntil)
      return null;
    var days = Logic.daysLeft(currentProvider.validUntil, now);
    return days === null ? null : {
      date: Qt.formatDateTime(new Date(Logic.parseValidUntilDate(currentProvider.validUntil)), "dd.MM"),
      days: days,
      soon: Logic.isExpiringSoon(days)
    };
  }

  function metricLabel(key) {
    if (!trFn)
      return "";
    if (key === "session")
      return trFn("panel.session_label");
    if (key === "weekly")
      return trFn("panel.weekly_label");
    if (key === "balance")
      return trFn("panel.balance_label");
    return key;
  }

  function updatedText() {
    if (!trFn || !currentEntry)
      return "";
    var ago = Logic.formatDuration(Date.now() - currentEntry.fetchedAt, hUnit, mUnit);
    var text = trFn("panel.updated").replace("{duration}", ago);
    if (currentError !== "")
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

      // --- header: title + refresh -----------------------------------------
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        NIcon {
          icon: "gauge"
          color: Color.mPrimary
        }

        NText {
          Layout.fillWidth: true
          text: root.trFn ? root.trFn("panel.header") : ""
          color: Color.mOnSurface
          pointSize: Style.fontSizeXL
          font.bold: true
          elide: Text.ElideRight
        }

        NIconButton {
          icon: "refresh"
          enabled: !root.fetching[root.currentId] && root.currentProvider !== null
          onClicked: {
            if (root.mainInstance && root.currentProvider)
              root.mainInstance.fetchProvider(root.currentProvider);
          }
        }
      }

      // --- provider tabs (failing stay visible, ported from vendor-tabs) ----
      RowLayout {
        Layout.fillWidth: true
        visible: root.providers.length > 1
        spacing: Style.marginXS

        Repeater {
          model: root.providers

          delegate: Rectangle {
            id: tab
            required property var modelData
            readonly property bool active: modelData.id === root.currentId
            readonly property bool failing: (root.errors[modelData.id] !== undefined && root.errors[modelData.id] !== "") || (root.entries[modelData.id] === undefined && modelData.enabled)
            readonly property var m: root.mainInstance

            Layout.fillWidth: true
            Layout.preferredHeight: Style.fontSizeL + Style.marginS * 2
            radius: Style.radiusS
            color: active ? Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.18) : Color.mSurfaceVariant
            border.width: active ? 1 : 0
            border.color: Color.mPrimary
            opacity: modelData.enabled ? 1 : 0.4

            MouseArea {
              anchors.fill: parent
              acceptedButtons: Qt.LeftButton
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.selectedId = tab.modelData.id
            }

            RowLayout {
              anchors.centerIn: parent
              spacing: Style.marginXS

              ProviderChip {
                monogram: tab.m ? tab.m.chipFor(tab.modelData).monogram : "?"
                chipColor: tab.m ? tab.m.chipFor(tab.modelData).color : Color.mOnSurfaceVariant
                size: Style.fontSizeM
              }

              NText {
                text: tab.m ? tab.m.displayLabel(tab.modelData) : ""
                color: tab.active ? Color.mOnSurface : Color.mOnSurfaceVariant
                pointSize: Style.fontSizeS
                font.bold: tab.active
                elide: Text.ElideRight
              }

              NText {
                visible: tab.failing
                text: "⚠"
                color: Color.mError
                pointSize: Style.fontSizeS
              }
            }
          }
        }
      }

      // --- status surface ------------------------------------------------------
      Rectangle {
        Layout.fillWidth: true
        visible: root.providers.length === 0 || root.currentError !== "" || (root.currentEntry === null && root.fetching[root.currentId])
        implicitHeight: statusText.implicitHeight + Style.marginM * 2
        radius: Style.radiusS
        color: Qt.rgba(Color.mError.r, Color.mError.g, Color.mError.b, 0.09)
        border.width: 1
        border.color: Qt.rgba(Color.mError.r, Color.mError.g, Color.mError.b, 0.35)

        NText {
          id: statusText
          anchors.fill: parent
          anchors.margins: Style.marginS
          text: {
            if (!root.trFn)
              return "";
            if (root.providers.length === 0)
              return root.trFn("panel.no_providers");
            if (root.currentProvider && (!root.currentProvider.apiKey || root.currentProvider.apiKey === ""))
              return root.trFn("panel.no_key");
            if (root.currentError !== "")
              return root.currentError;
            if (root.currentEntry === null)
              return root.trFn("panel.never");
            return "";
          }
          color: Color.mOnSurface
          pointSize: Style.fontSizeS
          wrapMode: Text.WordWrap
        }
      }

      // --- valid until -----------------------------------------------------------
      NText {
        Layout.fillWidth: true
        visible: root.validInfo !== null
        text: root.validInfo && root.trFn ? root.trFn("desktop_widget.until").replace("{date}", root.validInfo.date).replace("{days}", root.validInfo.days) : ""
        color: root.validInfo && root.validInfo.soon ? "#FFB020" : Color.mOnSurfaceVariant
        pointSize: Style.fontSizeS
      }

      // --- metrics of the selected provider -----------------------------------------
      NDivider {
        Layout.fillWidth: true
        visible: root.currentEntry !== null
      }

      NText {
        Layout.fillWidth: true
        visible: root.currentEntry !== null
        text: root.trFn ? root.trFn("panel.section_title") : ""
        color: Color.mOnSurfaceVariant
        pointSize: Style.fontSizeXS
      }

      Repeater {
        model: root.currentEntry ? root.currentEntry.sections : []

        delegate: ColumnLayout {
          id: secRow
          required property var modelData

          Layout.fillWidth: true

          Loader {
            Layout.fillWidth: true
            active: secRow.modelData.type === 'metric'
            sourceComponent: UsageRow {
              Layout.fillWidth: true
              section: secRow.modelData
              label: root.metricLabel(secRow.modelData.key)
              detail: secRow.modelData.key === "session" && root.trFn && secRow.modelData.percent !== null && secRow.modelData.percent !== undefined ? root.trFn("panel.remaining").replace("{percent}", String(100 - secRow.modelData.percent)) : secRow.modelData.detail
              now: root.now
              tr: root.trFn
              hUnit: root.hUnit
              mUnit: root.mUnit
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            visible: secRow.modelData.type === 'block'
            spacing: 0

            NText {
              Layout.fillWidth: true
              Layout.topMargin: Style.marginS
              visible: text !== ""
              text: secRow.modelData.key === 'tools' ? (root.trFn ? root.trFn("panel.tools_label") : "") : ""
              color: Color.mOnSurfaceVariant
              pointSize: Style.fontSizeXS
            }

            Repeater {
              model: secRow.modelData.type === 'block' ? secRow.modelData.body : []

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

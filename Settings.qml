// Settings.qml v2 — provider CRUD:
//   list   — chip + display name + key mask + enabled toggle + delete
//            (click on a row makes the provider active)
//   add    — type combo + API key (action button = add & fetch) + optional
//            display name / plan override / valid-until date
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Services.UI
import qs.Widgets
import "Logic.js" as Logic

ColumnLayout {
  id: root

  property var pluginApi: null

  readonly property var mainInstance: pluginApi ? pluginApi.mainInstance : null

  // add-provider form state
  property string newType: "zai"
  property string newApiKey: ""
  property string newLabel: ""
  property string newPlanLabel: ""
  property string newValidUntil: ""

  spacing: Style.marginL

  Component.onCompleted: {
    Logger.i("AiUsage", "settings UI loaded");
  }

  function settingsObj() {
    return pluginApi ? pluginApi.pluginSettings : null;
  }

  function persist() {
    if (pluginApi && pluginApi.saveSettings)
      pluginApi.saveSettings();
    if (mainInstance)
      mainInstance.loadProviders();
  }

  function providerTypes() {
    var types = [];
    for (var key in Logic.PROVIDERS)
      types.push(key);
    return types;
  }

  function keyMask(key) {
    if (!key || key.length < 4)
      return "••••";
    return "•••" + key.substring(key.length - 3);
  }

  function addProvider() {
    var s = settingsObj();
    if (!s || newApiKey === "")
      return;
    var until = newValidUntil.trim();
    if (until !== "" && Logic.parseValidUntilDate(until) === null)
      until = "";
    var id = Logic.newProviderId(newType, s.providers.map(function (p) { return p.id; }));
    s.providers.push({
      id: id,
      type: newType,
      apiKey: newApiKey.trim(),
      label: newLabel.trim(),
      planLabel: newPlanLabel.trim(),
      validUntil: until,
      enabled: true
    });
    s.activeProviderId = id;
    persist();
    if (mainInstance) {
      var added = null;
      for (var i = 0; i < s.providers.length; i++) {
        if (s.providers[i].id === id)
          added = s.providers[i];
      }
      if (added)
        mainInstance.fetchProvider(added);
    }
    newApiKey = "";
    newLabel = "";
    newPlanLabel = "";
    newValidUntil = "";
  }

  function removeProvider(id) {
    var s = settingsObj();
    if (!s)
      return;
    var idx = -1;
    for (var i = 0; i < s.providers.length; i++) {
      if (s.providers[i].id === id)
        idx = i;
    }
    if (idx < 0)
      return;
    s.providers.splice(idx, 1);
    if (s.activeProviderId === id)
      s.activeProviderId = s.providers.length > 0 ? s.providers[0].id : "";
    persist();
  }

  function setEnabled(id, enabled) {
    var s = settingsObj();
    if (!s)
      return;
    for (var i = 0; i < s.providers.length; i++) {
      if (s.providers[i].id === id) {
        s.providers[i].enabled = enabled;
        break;
      }
    }
    persist();
  }

  // --- refresh interval (global) ------------------------------------------

  NComboBox {
    Layout.fillWidth: true
    label: pluginApi ? pluginApi.tr("settings.refresh.label") : ""
    description: pluginApi ? pluginApi.tr("settings.refresh.description") : ""
    model: [1, 5, 10, 15, 30, 60].map(function (m) {
      return { key: m, name: String(m) };
    })
    currentKey: {
      var m = Number(settingsObj() ? settingsObj().refreshMinutes : 5);
      return isFinite(m) && m >= 1 ? Math.min(60, Math.round(m)) : 5;
    }
    onSelected: function (key) {
      settingsObj().refreshMinutes = key;
      persist();
    }
  }

  // --- provider list --------------------------------------------------------

  NText {
    Layout.fillWidth: true
    text: pluginApi ? pluginApi.tr("settings.providers_label") : ""
    color: Color.mOnSurfaceVariant
    pointSize: Style.fontSizeXS
  }

  Repeater {
    model: mainInstance ? mainInstance.providers : []

    delegate: Rectangle {
      id: prow
      required property var modelData

      Layout.fillWidth: true
      readonly property bool active: modelData.id === (root.mainInstance ? root.mainInstance.activeProviderId : "")
      implicitHeight: Style.fontSizeL + Style.marginM * 2.5
      radius: Style.radiusS
      color: prow.active ? Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.12) : Color.mSurfaceVariant
      border.width: prow.active ? 1 : 0
      border.color: Color.mPrimary
      opacity: modelData.enabled ? 1 : 0.45

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          if (root.mainInstance)
            root.mainInstance.setActive(prow.modelData.id);
        }
      }

      RowLayout {
        anchors.fill: parent
        anchors.margins: Style.marginS
        spacing: Style.marginS

        ProviderChip {
          monogram: root.mainInstance ? root.mainInstance.chipFor(prow.modelData).monogram : "?"
          chipColor: root.mainInstance ? root.mainInstance.chipFor(prow.modelData).color : Color.mOnSurfaceVariant
          size: Style.fontSizeL
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 0

          NText {
            Layout.fillWidth: true
            text: root.mainInstance ? root.mainInstance.displayLabel(prow.modelData) : ""
            color: Color.mOnSurface
            pointSize: Style.fontSizeM
            font.bold: prow.active
            elide: Text.ElideRight
          }

          NText {
            Layout.fillWidth: true
            text: root.keyMask(prow.modelData.apiKey) + (prow.modelData.validUntil ? " · " + prow.modelData.validUntil : "")
            color: Color.mOnSurfaceVariant
            pointSize: Style.fontSizeXS
            elide: Text.ElideRight
          }
        }

        NToggle {
          label: ""
          description: ""
          checked: prow.modelData.enabled
          onToggled: function (checked) {
            root.setEnabled(prow.modelData.id, checked);
          }
        }

        NIconButton {
          icon: "trash"
          onClicked: root.removeProvider(prow.modelData.id)
        }
      }
    }
  }

  // --- add provider -----------------------------------------------------------

  NDivider {
    Layout.fillWidth: true
  }

  NText {
    Layout.fillWidth: true
    text: pluginApi ? pluginApi.tr("settings.add_provider.label") : ""
    color: Color.mOnSurfaceVariant
    pointSize: Style.fontSizeXS
  }

  NComboBox {
    Layout.fillWidth: true
    label: pluginApi ? pluginApi.tr("settings.provider.type") : ""
    model: root.providerTypes().map(function (t) {
      return { key: t, name: Logic.PROVIDERS[t].name };
    })
    currentKey: root.newType
    onSelected: function (key) {
      root.newType = key;
    }
  }

  NInputAction {
    Layout.fillWidth: true
    label: pluginApi ? pluginApi.tr("settings.api_key.label") : ""
    description: pluginApi ? pluginApi.tr("settings.api_key.description") : ""
    placeholderText: "sk-…"
    text: root.newApiKey
    actionButtonText: pluginApi ? pluginApi.tr("settings.add_provider.action") : "Add"
    actionButtonIcon: "plus"
    onTextChanged: root.newApiKey = text
    onActionClicked: root.addProvider()
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginS

    NTextInput {
      Layout.fillWidth: true
      label: pluginApi ? pluginApi.tr("settings.provider.label_field") : ""
      placeholderText: ""
      text: root.newLabel
      onTextChanged: root.newLabel = text
    }

    NTextInput {
      Layout.fillWidth: true
      label: pluginApi ? pluginApi.tr("settings.provider.plan_field") : ""
      placeholderText: "pro"
      text: root.newPlanLabel
      onTextChanged: root.newPlanLabel = text
    }
  }

  NTextInput {
    Layout.fillWidth: true
    label: pluginApi ? pluginApi.tr("settings.provider.valid_until") : ""
    placeholderText: "2026-09-15"
    text: root.newValidUntil
    onTextChanged: root.newValidUntil = text
  }

  // --- widget background ---------------------------------------------------------

  NToggle {
    Layout.fillWidth: true
    label: pluginApi ? pluginApi.tr("settings.background.label") : ""
    description: pluginApi ? pluginApi.tr("settings.background.description") : ""
    checked: settingsObj() ? settingsObj().showBackground : true
    onToggled: function (checked) {
      settingsObj().showBackground = checked;
      persist();
    }
  }
}

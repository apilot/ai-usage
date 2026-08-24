// Settings.qml — API key (with a "test" action that forces a fetch),
// refresh interval, weekly quota visibility, widget background.
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root

  property var pluginApi: null

  readonly property var mainInstance: pluginApi ? pluginApi.mainInstance : null

  property string valueApiKey: pluginApi && pluginApi.pluginSettings && pluginApi.pluginSettings.apiKey !== undefined ? pluginApi.pluginSettings.apiKey : ""
  property int valueRefreshMinutes: {
    var m = Number(pluginApi && pluginApi.pluginSettings ? pluginApi.pluginSettings.refreshMinutes : 5);
    return isFinite(m) && m >= 1 ? Math.min(60, Math.round(m)) : 5;
  }
  property bool valueShowWeekly: pluginApi && pluginApi.pluginSettings && pluginApi.pluginSettings.showWeekly !== undefined ? pluginApi.pluginSettings.showWeekly : true
  property bool valueShowBackground: pluginApi && pluginApi.pluginSettings && pluginApi.pluginSettings.showBackground !== undefined ? pluginApi.pluginSettings.showBackground : true

  spacing: Style.marginL

  Component.onCompleted: {
    Logger.i("AiUsage", "settings UI loaded");
  }

  function persist(key, value) {
    if (!pluginApi || !pluginApi.pluginSettings)
      return;
    pluginApi.pluginSettings[key] = value;
    pluginApi.saveSettings();
  }

  NInputAction {
    Layout.fillWidth: true
    label: pluginApi ? pluginApi.tr("settings.api_key.label") : ""
    description: pluginApi ? pluginApi.tr("settings.api_key.description") : ""
    placeholderText: "••••••••••••"
    text: root.valueApiKey
    actionButtonText: pluginApi ? pluginApi.tr("panel.refresh") : "Test"
    actionButtonIcon: "bolt"
    onTextChanged: {
      root.valueApiKey = text;
    }
    onEditingFinished: {
      root.persist("apiKey", root.valueApiKey);
    }
    onActionClicked: {
      root.persist("apiKey", root.valueApiKey);
      if (root.mainInstance)
        root.mainInstance.fetchNow();
    }
  }

  NComboBox {
    Layout.fillWidth: true
    label: pluginApi ? pluginApi.tr("settings.refresh.label") : ""
    description: pluginApi ? pluginApi.tr("settings.refresh.description") : ""
    model: [1, 5, 10, 15, 30, 60].map(function (m) {
      return {
        key: m,
        name: String(m)
      };
    })
    currentKey: root.valueRefreshMinutes
    onSelected: function (key) {
      root.valueRefreshMinutes = key;
      root.persist("refreshMinutes", key);
    }
  }

  NToggle {
    Layout.fillWidth: true
    label: pluginApi ? pluginApi.tr("settings.show_weekly.label") : ""
    description: pluginApi ? pluginApi.tr("settings.show_weekly.description") : ""
    checked: root.valueShowWeekly
    onToggled: function (checked) {
      root.valueShowWeekly = checked;
      root.persist("showWeekly", checked);
    }
  }

  NToggle {
    Layout.fillWidth: true
    label: pluginApi ? pluginApi.tr("settings.background.label") : ""
    description: pluginApi ? pluginApi.tr("settings.background.description") : ""
    checked: root.valueShowBackground
    onToggled: function (checked) {
      root.valueShowBackground = checked;
      root.persist("showBackground", checked);
    }
  }
}

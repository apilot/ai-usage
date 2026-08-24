// UsageBar.qml — severity-colored usage bar with animated fill.
//
// Ported from ai-usagebar (MIT) kde-plasmoid/package/contents/ui/UsageBar.qml
// to Noctalia's qs.Commons design tokens: Kirigami.Units → Style.*,
// Kirigami.Theme colors → Color.* severity map (with one amber bridge color
// for "high", which the Noctalia palette lacks).
import QtQuick
import qs.Commons

Item {
  id: root

  required property int pct
  property string severity: "low"

  readonly property int clampedPct: Math.max(0, Math.min(100, root.pct))

  // low → mint, mid → yellow (primary), high → amber, critical → error
  readonly property color severityColor: {
    switch (root.severity) {
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

  implicitHeight: 8
  implicitWidth: 120

  Rectangle {
    id: track
    anchors.fill: parent
    radius: height / 2
    color: Color.mOnSurfaceVariant
    opacity: 0.25

    Rectangle {
      width: Math.round(parent.width * root.clampedPct / 100)
      height: parent.height
      radius: parent.radius
      color: root.severityColor

      // Switching metrics reads as a transition rather than a jump.
      Behavior on width {
        NumberAnimation {
          duration: 160
          easing.type: Easing.OutCubic
        }
      }
    }
  }
}

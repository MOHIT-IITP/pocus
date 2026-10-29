import QtQuick
import qs.Commons

// One compact metric in the heatmap page summary row.
Item {
  id: root

  property string label: ""
  property string value: ""
  property color valueColor: Color.foreground
  property color labelColor: Util.alpha(Color.foreground, 0.30)

  implicitHeight: labelText.implicitHeight + valueText.implicitHeight + Style.space(3)
  height: implicitHeight

  Text {
    id: labelText
    width: parent.width
    textFormat: Text.PlainText
    text: root.label
    color: root.labelColor
    font.family: Style.font.family
    font.pixelSize: Math.max(7, Style.font.caption - 2)
    font.bold: true
    font.letterSpacing: Style.spaceReal(0.7)
    elide: Text.ElideRight
  }

  Text {
    id: valueText
    y: labelText.implicitHeight + Style.space(3)
    width: parent.width
    textFormat: Text.PlainText
    text: root.value
    color: root.valueColor
    font.family: Style.font.family
    font.pixelSize: Style.font.heading
    font.bold: true
    elide: Text.ElideRight
  }
}

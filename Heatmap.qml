import QtQuick
import qs.Commons
import "Pocus.js" as Pocus

// GitHub-style contribution grid, sized compactly to the panel. Data comes straight
// from Pocus.buildHeatmap(); this component lays it out, supports smooth horizontal
// swiping across pages, and reports hover/selection back to the panel footer.
Item {
  id: root

  property var weeks: []
  property var monthLabels: []
  property int weekCount: 52
  property color ink: Color.foreground
  property string activeKey: ""
  property string hoveredKey: ""

  signal dayHovered(string key)
  signal daySelected(string key)
  signal swipeStarted(real startX)
  signal swipeMoved(real currentX)
  signal swipeEnded(real currentX)

  readonly property var levelAlphas: [0.05, 0.18, 0.38, 0.66, 0.92]
  readonly property real labelWidth: Style.space(8)
  readonly property real labelGap: Style.space(3)
  readonly property real cellGap: Math.max(1.4, Math.min(2.0, Style.spaceReal(1.8)))
  readonly property real maxCellSize: Style.spaceReal(6.5)
  readonly property real cellSize: {
    var available = width - labelWidth - labelGap - cellGap * (weekCount - 1)
    var fit = Math.floor(available / Math.max(1, weekCount))
    return Math.max(3.0, Math.min(maxCellSize, fit))
  }
  readonly property real gridWidth: labelWidth + labelGap + cellSize * weekCount + cellGap * (weekCount - 1)
  readonly property real gridX: Math.max(0, Math.round((width - gridWidth) / 2))
  readonly property real gridHeight: cellSize * 7 + cellGap * 6
  readonly property real monthHeight: Style.space(11)

  implicitHeight: monthHeight + gridHeight

  function reportHover(key) {
    var next = String(key || "")
    if (next === hoveredKey) return
    hoveredKey = next
    dayHovered(next)
  }

  // Month labels
  Item {
    x: root.gridX
    width: root.gridWidth
    height: root.monthHeight

    Repeater {
      model: root.monthLabels

      Text {
        required property var modelData
        x: Math.max(0, Math.min(parent.width - width,
          root.labelWidth + root.labelGap + modelData.column * (root.cellSize + root.cellGap)))
        textFormat: Text.PlainText
        text: modelData.text
        color: root.ink
        opacity: 0.34
        font.family: Style.font.family
        font.pixelSize: Math.max(7, Style.font.caption - 2)
        font.bold: true
      }
    }
  }

  // Days grid
  Row {
    x: root.gridX
    y: root.monthHeight
    spacing: 0

    Column {
      width: root.labelWidth
      spacing: root.cellGap

      Repeater {
        model: Pocus.WEEKDAY_LABELS

        Text {
          required property var modelData
          required property int index
          width: root.labelWidth
          height: root.cellSize
          textFormat: Text.PlainText
          text: root.cellSize < 8.5
            ? ((index === 0 || index === 2 || index === 4) ? modelData : "")
            : modelData
          color: root.ink
          opacity: 0.30
          font.family: Style.font.family
          font.pixelSize: Math.max(6, Math.min(8, root.cellSize - 0.5))
          font.bold: true
          horizontalAlignment: Text.AlignLeft
          verticalAlignment: Text.AlignVCenter
        }
      }
    }

    Item {
      width: root.labelGap
      height: 1
    }

    Row {
      spacing: root.cellGap

      Repeater {
        model: root.weeks

        Column {
          id: weekColumn
          required property var modelData
          spacing: root.cellGap

          Repeater {
            model: weekColumn.modelData.days

            Rectangle {
              id: dayCell
              required property var modelData
              readonly property bool future: modelData.future === true
              readonly property bool selected: root.activeKey === modelData.key
              readonly property bool hovered: root.hoveredKey === modelData.key

              width: root.cellSize
              height: root.cellSize
              radius: Math.max(1, Math.round(root.cellSize * 0.22))
              color: future
                ? Util.alpha(root.ink, 0.025)
                : Util.alpha(root.ink, root.levelAlphas[modelData.level] || 0.05)
              border.width: (selected || hovered) && !future ? 1 : 0
              border.color: Util.alpha(root.ink, selected ? 0.95 : 0.65)
            }
          }
        }
      }
    }
  }

  // Unified mouse area for hover, click, and horizontal swipe
  MouseArea {
    id: gridMouse
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    cursorShape: (dayUnderMouse && !dayUnderMouse.future) ? Qt.PointingHandCursor : Qt.ArrowCursor

    property real pressX: 0
    property real pressY: 0
    property bool dragging: false
    property var dayUnderMouse: null

    function dayAt(mx, my) {
      var relX = mx - (root.gridX + root.labelWidth + root.labelGap)
      var relY = my - root.monthHeight
      if (relX < 0 || relY < 0) return null

      var step = root.cellSize + root.cellGap
      if (step <= 0) return null

      var col = Math.floor(relX / step)
      var row = Math.floor(relY / step)

      if (col < 0 || col >= root.weeks.length || row < 0 || row >= 7) return null

      var cellX = relX - col * step
      var cellY = relY - row * step
      if (cellX > root.cellSize || cellY > root.cellSize) return null

      var week = root.weeks[col]
      if (!week || !week.days || row >= week.days.length) return null
      return week.days[row]
    }

    onPositionChanged: function(mouse) {
      if (pressed) {
        var dx = mouse.x - pressX
        var dy = mouse.y - pressY
        if (!dragging && (Math.abs(dx) > 6 || Math.abs(dy) > 6)) {
          dragging = true
          root.swipeStarted(pressX)
        }
        if (dragging) {
          root.swipeMoved(mouse.x)
          return
        }
      }

      var day = dayAt(mouse.x, mouse.y)
      dayUnderMouse = day
      if (day && !day.future) {
        root.reportHover(day.key)
      } else {
        root.reportHover("")
      }
    }

    onPressed: function(mouse) {
      pressX = mouse.x
      pressY = mouse.y
      dragging = false
    }

    onReleased: function(mouse) {
      if (dragging) {
        dragging = false
        root.swipeEnded(mouse.x)
      } else {
        var day = dayAt(mouse.x, mouse.y)
        if (day && !day.future) {
          root.daySelected(day.key)
        }
      }
    }

    onExited: {
      dayUnderMouse = null
      if (!pressed) root.reportHover("")
    }

    onCanceled: {
      dayUnderMouse = null
      if (dragging) {
        dragging = false
        root.swipeEnded(pressX)
      }
    }
  }
}

import QtQuick
import qs.Commons

// A compact line-and-dot chart in the Pocus visual language. Values are
// minutes; hover is reported to the panel, which owns the footer detail.
Item {
  id: root

  property var values: []
  property var labels: []
  property color lineColor: Color.foreground
  property color dotColor: Color.accent
  property color labelColor: Color.foreground
  property bool areaFill: false
  property int hoveredIndex: -1

  signal hovered(int index)

  readonly property int count: values ? values.length : 0
  readonly property real padX: Style.space(5)
  readonly property real padTop: Style.space(4)
  readonly property real padBottom: Style.space(14)
  readonly property real plotWidth: Math.max(1, width - padX * 2)
  readonly property real plotHeight: Math.max(1, height - padTop - padBottom)
  readonly property real step: count > 1 ? plotWidth / (count - 1) : 0
  readonly property real maxValue: {
    var max = 0
    for (var i = 0; i < count; i++) max = Math.max(max, Number(values[i]) || 0)
    return Math.max(30, max * 1.12)
  }

  function xFor(index) {
    return padX + index * step
  }

  function yFor(value) {
    var ratio = Math.max(0, Number(value) || 0) / maxValue
    return padTop + plotHeight - ratio * plotHeight
  }

  onValuesChanged: canvas.requestPaint()
  onHoveredIndexChanged: canvas.requestPaint()
  onWidthChanged: canvas.requestPaint()
  onHeightChanged: canvas.requestPaint()
  onLineColorChanged: canvas.requestPaint()
  onDotColorChanged: canvas.requestPaint()
  onMaxValueChanged: canvas.requestPaint()

  Canvas {
    id: canvas
    anchors.fill: parent

    function tint(color, alpha) {
      return Qt.rgba(color.r, color.g, color.b, alpha)
    }

    onPaint: {
      var ctx = getContext("2d")
      var w = width
      var h = height
      ctx.clearRect(0, 0, w, h)

      var n = root.count
      var baselineY = root.padTop + root.plotHeight

      // Baseline.
      ctx.beginPath()
      ctx.moveTo(root.padX, baselineY)
      ctx.lineTo(w - root.padX, baselineY)
      ctx.strokeStyle = tint(root.labelColor, 0.10)
      ctx.lineWidth = 1
      ctx.stroke()

      if (n === 0) return

      // Optional soft fill under the line.
      if (root.areaFill && n > 1) {
        ctx.beginPath()
        ctx.moveTo(root.xFor(0), baselineY)
        for (var i = 0; i < n; i++) {
          ctx.lineTo(root.xFor(i), root.yFor(root.values[i]))
        }
        ctx.lineTo(root.xFor(n - 1), baselineY)
        ctx.closePath()
        ctx.fillStyle = tint(root.lineColor, 0.045)
        ctx.fill()
      }

      // Line.
      if (n > 1) {
        ctx.beginPath()
        ctx.moveTo(root.xFor(0), root.yFor(root.values[0]))
        for (var j = 1; j < n; j++) {
          ctx.lineTo(root.xFor(j), root.yFor(root.values[j]))
        }
        ctx.strokeStyle = tint(root.lineColor, 0.68)
        ctx.lineWidth = Math.max(1, Style.spaceReal(1.4))
        ctx.lineJoin = "round"
        ctx.lineCap = "round"
        ctx.stroke()
      }

      // Hover guide.
      if (root.hoveredIndex >= 0 && root.hoveredIndex < n) {
        var hx = root.xFor(root.hoveredIndex)
        ctx.beginPath()
        ctx.moveTo(hx, root.padTop)
        ctx.lineTo(hx, baselineY)
        ctx.strokeStyle = tint(root.labelColor, 0.16)
        ctx.lineWidth = 1
        ctx.stroke()
      }

      // Dots.
      for (var k = 0; k < n; k++) {
        var isHovered = k === root.hoveredIndex
        var radius = isHovered ? Math.max(2.8, Style.spaceReal(3.2)) : Math.max(1.8, Style.spaceReal(2.2))
        ctx.beginPath()
        ctx.arc(root.xFor(k), root.yFor(root.values[k]), radius, 0, Math.PI * 2)
        ctx.fillStyle = tint(root.dotColor, isHovered ? 1 : (k === n - 1 ? 0.92 : 0.78))
        ctx.fill()

        if (isHovered) {
          ctx.beginPath()
          ctx.arc(root.xFor(k), root.yFor(root.values[k]), radius + 2.2, 0, Math.PI * 2)
          ctx.strokeStyle = tint(root.dotColor, 0.35)
          ctx.lineWidth = 1
          ctx.stroke()
        }
      }
    }
  }

  Repeater {
    model: root.labels

    Text {
      required property var modelData
      required property int index

      readonly property real labelWidth: Math.max(Style.space(12), root.step)
      x: Math.max(0, Math.min(root.width - width, root.xFor(index) - width / 2))
      y: root.height - root.padBottom + Style.space(1)
      width: labelWidth
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: modelData
      color: root.labelColor
      opacity: index === root.count - 1 ? 0.9 : 0.38
      font.family: Style.font.family
      font.pixelSize: Math.max(7, Style.font.caption - 1)
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.NoButton

    onPositionChanged: function(mouse) {
      if (root.count === 0) return
      var index = 0
      if (root.count > 1 && root.step > 0) {
        index = Math.round((mouse.x - root.padX) / root.step)
      }
      index = Math.max(0, Math.min(root.count - 1, index))
      if (root.hoveredIndex !== index) {
        root.hoveredIndex = index
        root.hovered(index)
      }
    }

    onExited: {
      if (root.hoveredIndex !== -1) {
        root.hoveredIndex = -1
        root.hovered(-1)
      }
    }
  }
}

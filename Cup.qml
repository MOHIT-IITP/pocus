import QtQuick
import qs.Commons

// A small mug that fills while Pocus is tracking and drains when it stops.
// The liquid surface waves and bubbles rise while the panel is open; the bar
// passes animateWaves: false so it stays a cheap, static state indicator.
Item {
  id: root

  property real level: 0          // 0 = empty, 1 = full
  property bool active: false
  property bool animateWaves: true
  property color ink: Color.foreground
  property color liquid: Color.accent

  property real shownLevel: 0
  property real phase: 0

  implicitWidth: 76
  implicitHeight: 90

  Behavior on shownLevel {
    NumberAnimation {
      duration: 780
      easing.type: Easing.InOutCubic
    }
  }

  onLevelChanged: shownLevel = level
  Component.onCompleted: shownLevel = level
  onShownLevelChanged: canvas.requestPaint()
  onInkChanged: canvas.requestPaint()
  onLiquidChanged: canvas.requestPaint()
  onWidthChanged: canvas.requestPaint()
  onHeightChanged: canvas.requestPaint()

  Timer {
    interval: 40
    repeat: true
    running: root.animateWaves && root.active && root.visible
    onTriggered: {
      root.phase += 0.10
      canvas.requestPaint()
    }
  }

  Canvas {
    id: canvas
    anchors.fill: parent

    function tint(color, alpha) {
      return Qt.rgba(color.r, color.g, color.b, alpha)
    }

    function bodyPath(ctx, bodyX, topY, topW, bottomW, bodyH, bottomR) {
      var bottomY = topY + bodyH
      var bottomX = bodyX + (topW - bottomW) / 2
      var topRight = bodyX + topW
      var bottomRight = bottomX + bottomW

      ctx.beginPath()
      ctx.moveTo(bodyX, topY)
      ctx.lineTo(bottomX, bottomY - bottomR)
      ctx.quadraticCurveTo(bottomX, bottomY, bottomX + bottomR, bottomY)
      ctx.lineTo(bottomRight - bottomR, bottomY)
      ctx.quadraticCurveTo(bottomRight, bottomY, bottomRight, bottomY - bottomR)
      ctx.lineTo(topRight, topY)
    }

    function ellipsePath(ctx, cx, cy, rx, ry) {
      ctx.save()
      ctx.translate(cx, cy)
      ctx.scale(1, ry / Math.max(0.001, rx))
      ctx.beginPath()
      ctx.arc(0, 0, rx, 0, Math.PI * 2)
      ctx.restore()
    }

    onPaint: {
      var ctx = getContext("2d")
      var w = width
      var h = height
      if (w <= 0 || h <= 0) return

      ctx.clearRect(0, 0, w, h)

      var stroke = Math.max(1, w * 0.028)
      var bodyX = w * 0.12
      var topY = h * 0.12
      var topW = w * 0.58
      var bottomW = w * 0.49
      var bodyH = h * 0.80
      var bottomR = Math.max(1, w * 0.09)
      var rimRX = topW / 2
      var rimRY = Math.max(1, h * 0.030)
      var fullY = topY + rimRY * 1.6
      var emptyY = topY + bodyH - rimRY * 0.4
      var surfaceY = emptyY - Math.max(0, Math.min(1, root.shownLevel)) * (emptyY - fullY)
      var level = Math.max(0, Math.min(1, root.shownLevel))

      var ink = root.ink
      var liquid = root.liquid

      // Handle, behind the body.
      var handleX = bodyX + topW - w * 0.015
      var handleTop = topY + bodyH * 0.26
      ctx.strokeStyle = tint(ink, 0.55)
      ctx.lineWidth = stroke * 1.25
      ctx.lineCap = "round"
      ctx.beginPath()
      ctx.moveTo(handleX, handleTop)
      ctx.bezierCurveTo(
        handleX + w * 0.24, handleTop - h * 0.03,
        handleX + w * 0.24, handleTop + h * 0.28,
        handleX, handleTop + h * 0.33
      )
      ctx.stroke()

      // Liquid, clipped to the body.
      if (level > 0.002) {
        ctx.save()
        bodyPath(ctx, bodyX, topY, topW, bottomW, bodyH, bottomR)
        ctx.clip()

        var bottomY = topY + bodyH + 2
        var amplitude = root.active && root.animateWaves ? Math.max(0.6, h * 0.016) : 0
        var steps = 22
        var left = bodyX - 2
        var right = bodyX + topW + 2

        ctx.beginPath()
        ctx.moveTo(left, surfaceY)
        for (var i = 1; i <= steps; i++) {
          var x = left + (right - left) * (i / steps)
          var y = surfaceY + Math.sin(root.phase + i * 0.55) * amplitude
          ctx.lineTo(x, y)
        }
        ctx.lineTo(right, bottomY)
        ctx.lineTo(left, bottomY)
        ctx.closePath()
        ctx.fillStyle = tint(liquid, 0.42)
        ctx.fill()

        // A brighter line makes the surface read at small sizes.
        ctx.beginPath()
        ctx.moveTo(left, surfaceY)
        for (var j = 1; j <= steps; j++) {
          var sx = left + (right - left) * (j / steps)
          var sy = surfaceY + Math.sin(root.phase + j * 0.55) * amplitude
          ctx.lineTo(sx, sy)
        }
        ctx.strokeStyle = tint(liquid, 0.80)
        ctx.lineWidth = Math.max(0.8, stroke * 0.7)
        ctx.stroke()

        // Bubbles drift from the bottom to the surface.
        if (root.active && root.animateWaves && h > 24) {
          var bubbleCount = 4
          for (var b = 0; b < bubbleCount; b++) {
            var travel = (root.phase * 0.22 + b * 0.27) % 1
            var bx = bodyX + topW * (0.22 + 0.19 * b)
            var by = emptyY - travel * (emptyY - surfaceY)
            var radius = Math.max(0.7, w * (0.008 + 0.004 * (b % 2)))
            ctx.beginPath()
            ctx.arc(bx, by, radius, 0, Math.PI * 2)
            ctx.fillStyle = tint(ink, 0.22 * (1 - travel))
            ctx.fill()
          }
        }

        // Inner left highlight.
        ctx.beginPath()
        ctx.moveTo(bodyX + topW * 0.12, fullY + h * 0.05)
        ctx.lineTo(bodyX + topW * 0.12, emptyY - h * 0.06)
        ctx.strokeStyle = tint(ink, 0.10)
        ctx.lineWidth = Math.max(0.8, stroke * 0.7)
        ctx.stroke()

        ctx.restore()
      }

      // Body outline.
      bodyPath(ctx, bodyX, topY, topW, bottomW, bodyH, bottomR)
      ctx.strokeStyle = tint(ink, 0.68)
      ctx.lineWidth = stroke
      ctx.lineJoin = "round"
      ctx.stroke()

      // Rim.
      ellipsePath(ctx, bodyX + rimRX, topY, rimRX, rimRY)
      ctx.strokeStyle = tint(ink, 0.60)
      ctx.lineWidth = stroke
      ctx.stroke()

      // Steam curls while actively filling.
      if (root.active && root.animateWaves && h > 34) {
        var curls = [0.30, 0.50, 0.70]
        for (var s = 0; s < curls.length; s++) {
          var cx = bodyX + topW * curls[s]
          var startY = topY - rimRY * 1.4
          var wobble = Math.sin(root.phase * 0.8 + s * 1.9) * h * 0.014
          ctx.beginPath()
          ctx.moveTo(cx, startY)
          ctx.bezierCurveTo(
            cx + wobble, startY - h * 0.055,
            cx - wobble, startY - h * 0.095,
            cx + wobble * 0.4, startY - h * 0.145
          )
          ctx.strokeStyle = tint(ink, 0.16)
          ctx.lineWidth = Math.max(0.8, stroke * 0.8)
          ctx.lineCap = "round"
          ctx.stroke()
        }
      }
    }
  }
}

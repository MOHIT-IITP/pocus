import QtQuick
import qs.Commons
import qs.Ui
import "Pocus.js" as Pocus

// Pocus panel — a live timer, a cup that fills while tracking, a 14-day
// trend, and a 52-week heatmap. The two data views share a swipe strip at
// the bottom of the card.
Panel {
  id: root
  moduleName: "io.github.mohiitp.pocus"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  readonly property var barIdentity: hostWidget || root
  readonly property var service: hostWidget ? hostWidget.service : null

  readonly property bool tracking: service ? service.running : false
  readonly property var history: service ? service.history : ({})
  readonly property string todayKey: service ? service.todayKey : Pocus.dateKey(new Date())
  readonly property int pMinutes: service ? service.todayProductiveMinutes : 0
  readonly property int oMinutes: service ? service.todayOffMinutes : 0
  readonly property int pSeconds: service ? Math.floor(service.productiveSeconds) : 0
  readonly property int oSeconds: service ? Math.floor(service.offSeconds) : 0
  readonly property int currentPSeconds: service ? Math.floor(service.currentProductiveSeconds) : 0
  readonly property int currentOSeconds: service ? Math.floor(service.currentOffSeconds) : 0
  readonly property int goalMinutes: service ? service.goalMinutes : 240
  readonly property int todaySeconds: pSeconds + oSeconds

  readonly property real goalRatio: goalMinutes > 0
    ? Math.min(1, (pSeconds / 60) / goalMinutes)
    : 0
  readonly property int goalPercent: Math.round(goalRatio * 100)
  readonly property real balanceRatio: todaySeconds > 0 ? pSeconds / todaySeconds : 0

  readonly property var trend: Pocus.buildTrend(history, todayKey, pMinutes * 60, oMinutes * 60, 14)
  readonly property var heatmap: Pocus.buildHeatmap(history, todayKey, pMinutes * 60, oMinutes * 60, 52)
  readonly property var best: Pocus.bestDay(history, todayKey, pMinutes * 60, oMinutes * 60)

  readonly property var productiveValues: Pocus.series(root.trend.days, "p")
  readonly property var offValues: Pocus.series(root.trend.days, "o")
  readonly property var dayLabels: {
    var out = []
    for (var i = 0; i < root.trend.days.length; i++) out.push(root.trend.days[i].label)
    return out
  }

  readonly property color fg: Color.popups.text
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property color muted: Util.alpha(fg, 0.55)
  readonly property color faint: Util.alpha(fg, 0.30)
  readonly property color hairline: Util.alpha(fg, 0.10)
  readonly property color cardFill: Util.alpha(fg, 0.035)
  readonly property color hoverFill: Util.alpha(fg, 0.07)

  readonly property real uiScale: 0.9
  function s(px) { return Style.space(Number(px) * root.uiScale) }
  function fs(px) { return Math.max(9, Math.round(Style.spaceReal(Number(px)) * root.uiScale)) }

  readonly property var heatmapLevels: [0.05, 0.18, 0.38, 0.66, 0.92]

  property int page: 0
  property real pageOffset: 0
  property bool draggingPage: false
  property real pressX: 0
  property int graphHoverIndex: -1
  property string heatmapHoverKey: ""
  property string pinnedDayKey: ""
  property bool resetArmed: false

  readonly property string graphHoveredKey: {
    if (graphHoverIndex < 0 || graphHoverIndex >= trend.days.length) return ""
    return trend.days[graphHoverIndex].key
  }
  readonly property string heatmapActiveKey: heatmapHoverKey !== "" ? heatmapHoverKey : pinnedDayKey

  readonly property string currentPText: Pocus.formatHMS(root.currentPSeconds)
  readonly property string currentOText: Pocus.formatHMS(root.currentOSeconds)
  readonly property string totalPText: Pocus.formatHMS(root.pSeconds)
  readonly property string totalOText: Pocus.formatHMS(root.oSeconds)

  readonly property string timerText: root.tracking
    ? root.currentPText
    : root.currentOText
  readonly property string modeLabel: root.tracking ? "CURRENT PRODUCTIVE SESSION" : "CURRENT UNPRODUCTIVE TIME"

  readonly property string graphFooter: {
    if (graphHoveredKey !== "") return root.daySummary(graphHoveredKey)
    return "TODAY · " + Pocus.formatDuration(root.pSeconds) + " productive · "
      + Pocus.formatDuration(root.oSeconds) + " off"
  }

  readonly property string heatmapFooter: {
    if (heatmapActiveKey !== "") return root.daySummary(heatmapActiveKey)
    if (root.heatmap.activeDays === 0) return "No time logged yet"
    return "WK " + Pocus.pad2(root.heatmap.weekNumber) + " · "
      + Pocus.formatDuration(root.heatmap.weekProductive) + " this week · best "
      + root.heatmap.bestStreak + "d"
  }

  function daySummary(key) {
    var entry = Pocus.mergedDay(root.history, root.todayKey, root.pMinutes * 60, root.oMinutes * 60, key)
    return Pocus.formatDay(key) + " · " + Pocus.formatDuration(entry.p) + " productive · "
      + Pocus.formatDuration(entry.o) + " off"
  }

  function startPageDrag(startX) {
    if (pageAnim.running) pageAnim.stop()
    root.pressX = startX
    root.pageOffset = 0
    root.draggingPage = false
  }

  function updatePageDrag(currentX) {
    var dx = currentX - root.pressX
    if (!root.draggingPage && Math.abs(dx) > 6) {
      root.draggingPage = true
    }
    if (!root.draggingPage) return

    var pageWidth = pageViewport.pageWidth
    if (root.page === 0) {
      if (dx > 0) {
        root.pageOffset = Math.min(root.s(36), dx * 0.12)
      } else {
        root.pageOffset = Math.max(-pageWidth, dx)
      }
    } else {
      if (dx < 0) {
        root.pageOffset = Math.max(-root.s(36), dx * 0.12)
      } else {
        root.pageOffset = Math.min(pageWidth, dx)
      }
    }
    pages.x = -root.page * pageWidth + root.pageOffset
  }

  function endPageDrag(currentX) {
    var dx = currentX - root.pressX
    var wasDragging = root.draggingPage
    root.draggingPage = false

    var pageWidth = pageViewport.pageWidth
    var threshold = Math.max(root.s(36), pageWidth * 0.12)
    var targetPage = root.page

    if (wasDragging) {
      if (root.page === 0 && dx < -threshold) {
        targetPage = 1
      } else if (root.page === 1 && dx > threshold) {
        targetPage = 0
      }
    }

    animateToPage(targetPage)
  }

  function animateToPage(targetIndex) {
    var target = Math.max(0, Math.min(1, targetIndex))
    root.page = target
    root.pageOffset = 0
    root.graphHoverIndex = -1
    root.heatmapHoverKey = ""

    pageAnim.stop()
    pageAnim.from = pages.x
    pageAnim.to = -target * pageViewport.pageWidth
    pageAnim.restart()
  }

  function setPage(index) {
    var next = Math.max(0, Math.min(1, Number(index) || 0))
    if (next === root.page && pages.x === -next * pageViewport.pageWidth) return
    animateToPage(next)
  }

  function openPage(index) {
    root.setPage(index)
    root.open()
  }

  function armReset() {
    if (!root.service) return
    if (root.resetArmed) {
      root.resetArmed = false
      resetArmTimer.stop()
      root.service.resetToday()
      return
    }
    root.resetArmed = true
    resetArmTimer.restart()
  }

  function toggleTimer() {
    if (root.service) root.service.toggleTracking()
  }

  function open() {
    root.graphHoverIndex = -1
    root.heatmapHoverKey = ""
    root.pinnedDayKey = ""
    root.resetArmed = false
    root.pageOffset = 0
    root.draggingPage = false
    pageAnim.stop()
    pages.x = -root.page * pageViewport.pageWidth
    resetArmTimer.stop()
    controller.show()
  }

  function close() {
    root.graphHoverIndex = -1
    root.heatmapHoverKey = ""
    root.pinnedDayKey = ""
    root.resetArmed = false
    root.pageOffset = 0
    root.draggingPage = false
    pageAnim.stop()
    pages.x = -root.page * pageViewport.pageWidth
    resetArmTimer.stop()
    controller.hide()
  }

  function toggle() { opened ? close() : open() }

  function closeForPopoutSwitch() {
    popoutSwitchClosing = true
    close()
    Qt.callLater(function() { popoutSwitchClosing = false })
  }

  function switchPanel(direction) {
    return bar && typeof bar.switchPanelFrom === "function"
      ? bar.switchPanelFrom(root.barIdentity, direction)
      : false
  }

  Timer {
    id: resetArmTimer
    interval: 3000
    repeat: false
    onTriggered: root.resetArmed = false
  }


  KeyboardPanel {
    id: popup
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    padding: root.s(14)
    contentWidth: popup.fittedContentWidth(root.s(500))
    contentHeight: popup.fittedContentHeight(content.implicitHeight, root.s(900))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onCloseRequested: root.close()
      onActivateRequested: {
        if (root.resetArmed) root.armReset()
        else root.toggleTimer()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dx > 0) root.setPage(1)
        else if (dx < 0) root.setPage(0)
      }
      onDeleteRequested: root.armReset()
      onTextKey: function(text) {
        if (text === "r" || text === "R") root.armReset()
        else if (text === "g" || text === "G" || text === "1") root.setPage(0)
        else if (text === "m" || text === "M" || text === "2") root.setPage(1)
      }

      Column {
        id: content
        width: parent.width
        spacing: root.s(8)

        // ------------------------------------------------------- header
        Item {
          width: parent.width
          height: root.s(20)

          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.s(6)

            Rectangle {
              width: root.s(6)
              height: width
              radius: width / 2
              anchors.verticalCenter: parent.verticalCenter
              color: root.tracking ? root.accent : root.faint
            }

            Text {
              textFormat: Text.PlainText
              text: "POCUS"
              color: root.fg
              font.family: Style.font.family
              font.pixelSize: root.fs(11)
              font.bold: true
              font.letterSpacing: root.s(1.4)
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              textFormat: Text.PlainText
              text: "PRODUCTIVE TIME"
              color: root.faint
              font.family: Style.font.family
              font.pixelSize: root.fs(8)
              font.bold: true
              font.letterSpacing: root.s(1.1)
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.s(5)

            Text {
              textFormat: Text.PlainText
              text: root.tracking ? "TRACKING" : "OFF TIME"
              color: root.tracking ? root.fg : root.muted
              font.family: Style.font.family
              font.pixelSize: root.fs(9)
              font.bold: true
              font.letterSpacing: root.s(0.9)
              anchors.verticalCenter: parent.verticalCenter
            }
          }
        }

        // ---------------------------------------------------- timer card
        Rectangle {
          id: mainCard
          width: parent.width
          height: root.s(142)
          radius: root.s(8)
          color: root.cardFill
          border.width: 1
          border.color: root.hairline

          Item {
            anchors.fill: parent
            anchors.margins: root.s(12)

            Column {
              id: timerColumn
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - cupColumn.width - root.s(12)
              spacing: root.s(3)

              Row {
                spacing: root.s(5)
                anchors.left: parent.left

                Rectangle {
                  width: root.s(6)
                  height: width
                  radius: width / 2
                  anchors.verticalCenter: parent.verticalCenter
                  color: root.tracking ? root.accent : root.muted
                }

                Text {
                  textFormat: Text.PlainText
                  text: root.modeLabel
                  color: root.tracking ? root.accent : root.muted
                  font.family: Style.font.family
                  font.pixelSize: root.fs(8.5)
                  font.bold: true
                  font.letterSpacing: root.s(1.0)
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.timerText
                color: root.fg
                font.family: Style.font.family
                font.pixelSize: root.fs(38)
                font.bold: true
                font.letterSpacing: root.s(0.8)
                renderType: Text.NativeRendering
              }

              Row {
                spacing: root.s(8)
                width: parent.width

                Column {
                  spacing: 1
                  Text {
                    textFormat: Text.PlainText
                    text: "TOTAL PRODUCTIVE"
                    color: root.faint
                    font.family: Style.font.family
                    font.pixelSize: root.fs(7)
                    font.bold: true
                    font.letterSpacing: root.s(0.4)
                  }
                  Text {
                    textFormat: Text.PlainText
                    text: Pocus.formatDuration(root.pSeconds)
                    color: root.fg
                    font.family: Style.font.family
                    font.pixelSize: root.fs(11)
                    font.bold: true
                  }
                }

                Rectangle {
                  width: 1
                  height: root.s(18)
                  color: root.hairline
                  anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                  spacing: 1
                  Text {
                    textFormat: Text.PlainText
                    text: "CURRENT FOCUS"
                    color: root.tracking ? root.accent : root.faint
                    font.family: Style.font.family
                    font.pixelSize: root.fs(7)
                    font.bold: true
                    font.letterSpacing: root.s(0.4)
                  }
                  Text {
                    textFormat: Text.PlainText
                    text: Pocus.formatDuration(root.currentPSeconds)
                    color: root.tracking ? root.accent : root.muted
                    font.family: Style.font.family
                    font.pixelSize: root.fs(11)
                    font.bold: true
                  }
                }

                Rectangle {
                  width: 1
                  height: root.s(18)
                  color: root.hairline
                  anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                  spacing: 1
                  Text {
                    textFormat: Text.PlainText
                    text: "CURRENT OFF"
                    color: !root.tracking ? root.fg : root.faint
                    font.family: Style.font.family
                    font.pixelSize: root.fs(7)
                    font.bold: true
                    font.letterSpacing: root.s(0.4)
                  }
                  Text {
                    textFormat: Text.PlainText
                    text: Pocus.formatDuration(root.currentOSeconds)
                    color: !root.tracking ? root.fg : root.muted
                    font.family: Style.font.family
                    font.pixelSize: root.fs(11)
                    font.bold: true
                  }
                }
              }

              Item { width: parent.width; height: root.s(3) }

              Row {
                spacing: root.s(6)

                Rectangle {
                  id: playButton
                  width: root.s(46)
                  height: root.s(30)
                  radius: root.s(5)
                  color: root.tracking
                    ? Util.alpha(root.accent, 0.16)
                    : (playMouse.containsMouse ? root.hoverFill : "transparent")
                  border.width: 1
                  border.color: root.tracking
                    ? Util.alpha(root.accent, 0.60)
                    : (playMouse.containsMouse ? Util.alpha(root.fg, 0.35) : root.hairline)

                  Behavior on color { ColorAnimation { duration: 120 } }

                  Text {
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: root.tracking ? "󰏤" : "▶"
                    color: root.tracking ? root.accent : root.fg
                    font.family: Style.font.family
                    font.pixelSize: root.fs(12)
                  }

                  MouseArea {
                    id: playMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleTimer()
                  }

                  PanelToolTip {
                    visible: playMouse.containsMouse
                    text: root.tracking ? "Pause tracking" : "Start tracking"
                  }
                }

                Rectangle {
                  id: resetButton
                  width: root.resetArmed ? root.s(58) : root.s(46)
                  height: root.s(30)
                  radius: root.s(5)
                  color: root.resetArmed
                    ? Util.alpha(root.urgent, 0.16)
                    : (resetMouse.containsMouse ? root.hoverFill : "transparent")
                  border.width: 1
                  border.color: root.resetArmed
                    ? Util.alpha(root.urgent, 0.60)
                    : (resetMouse.containsMouse ? Util.alpha(root.fg, 0.35) : root.hairline)

                  Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                  Behavior on color { ColorAnimation { duration: 120 } }

                  Text {
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: root.resetArmed ? "SURE?" : "✕"
                    color: root.resetArmed ? root.urgent : root.fg
                    font.family: Style.font.family
                    font.pixelSize: root.resetArmed ? root.fs(8) : root.fs(13)
                    font.bold: root.resetArmed
                    font.letterSpacing: root.resetArmed ? root.s(0.6) : 0
                  }

                  MouseArea {
                    id: resetMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.armReset()
                  }

                  PanelToolTip {
                    visible: resetMouse.containsMouse
                    text: root.resetArmed
                      ? "Click again to clear today's counters"
                      : "Clear today's counters"
                  }
                }
              }
            }

            Column {
              id: cupColumn
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: root.s(98)
              spacing: root.s(4)

              Cup {
                id: cup
                width: root.s(64)
                height: root.s(74)
                x: (parent.width - width) / 2
                level: root.tracking ? 1 : 0
                active: root.tracking
                animateWaves: root.opened
                ink: root.fg
                liquid: root.accent
              }

              Rectangle {
                width: parent.width
                height: root.s(4)
                radius: height / 2
                color: root.hairline

                Rectangle {
                  width: parent.width * root.goalRatio
                  height: parent.height
                  radius: height / 2
                  color: Util.alpha(root.accent, 0.60)

                  Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                }
              }

              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: root.goalPercent + "% OF " + Pocus.formatDuration(root.goalMinutes * 60)
                color: root.faint
                font.family: Style.font.family
                font.pixelSize: root.fs(8)
                font.bold: true
                font.letterSpacing: root.s(0.4)
              }
            }
          }
        }

        // -------------------------------------------------- view header
        Item {
          width: parent.width
          height: root.s(18)

          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.s(8)

            Rectangle {
              height: root.s(18)
              width: tab0Text.width + root.s(8)
              radius: root.s(3)
              color: tab0Mouse.containsMouse ? root.hoverFill : "transparent"
              Behavior on color { ColorAnimation { duration: 120 } }

              Text {
                id: tab0Text
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "PRODUCTIVE TREND"
                color: root.page === 0 ? root.fg : (tab0Mouse.containsMouse ? root.fg : root.faint)
                font.family: Style.font.family
                font.pixelSize: root.fs(9)
                font.bold: root.page === 0
                font.letterSpacing: root.s(0.9)
              }

              MouseArea {
                id: tab0Mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setPage(0)
              }
            }

            Text {
              text: "·"
              color: root.faint
              anchors.verticalCenter: parent.verticalCenter
              font.pixelSize: root.fs(9)
            }

            Rectangle {
              height: root.s(18)
              width: tab1Text.width + root.s(8)
              radius: root.s(3)
              color: tab1Mouse.containsMouse ? root.hoverFill : "transparent"
              Behavior on color { ColorAnimation { duration: 120 } }

              Text {
                id: tab1Text
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "PRODUCTIVE HEATMAP"
                color: root.page === 1 ? root.fg : (tab1Mouse.containsMouse ? root.fg : root.faint)
                font.family: Style.font.family
                font.pixelSize: root.fs(9)
                font.bold: root.page === 1
                font.letterSpacing: root.s(0.9)
              }

              MouseArea {
                id: tab1Mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setPage(1)
              }
            }
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.page === 0
              ? "LAST 14 DAYS"
              : "52 WEEKS · WK " + Pocus.pad2(root.heatmap.weekNumber)
            color: root.faint
            font.family: Style.font.family
            font.pixelSize: root.fs(8)
            font.bold: true
            font.letterSpacing: root.s(0.7)
          }
        }

        // --------------------------------------------------- page views
        Item {
          id: pageViewport
          width: parent.width
          height: Math.ceil(Math.max(graphColumn.implicitHeight, heatmapColumn.implicitHeight))
          clip: true

          readonly property real pageWidth: width
          onPageWidthChanged: {
            if (!pageAnim.running && !root.draggingPage) {
              pages.x = -root.page * pageWidth
            }
          }

          NumberAnimation {
            id: pageAnim
            target: pages
            property: "x"
            duration: 220
            easing.type: Easing.OutCubic
          }

          MouseArea {
            id: viewportMouseArea
            anchors.fill: parent
            hoverEnabled: false
            acceptedButtons: Qt.LeftButton

            onPressed: function(mouse) { root.startPageDrag(mouse.x) }
            onPositionChanged: function(mouse) { root.updatePageDrag(mouse.x) }
            onReleased: function(mouse) { root.endPageDrag(mouse.x) }
            onCanceled: { root.endPageDrag(root.pressX) }
            onWheel: function(wheel) {
              var dx = wheel.angleDelta.x !== 0 ? wheel.angleDelta.x : wheel.pixelDelta.x
              if (dx < -30) {
                root.setPage(1)
              } else if (dx > 30) {
                root.setPage(0)
              }
            }
          }

          Row {
            id: pages
            width: pageViewport.pageWidth * 2
            height: pageViewport.height
            x: -root.page * pageViewport.pageWidth

            // ------------------------------------------------- graph page
            Item {
              width: pageViewport.pageWidth
              height: pageViewport.height

              Column {
                id: graphColumn
                width: parent.width
                spacing: root.s(3)

                Item {
                  width: parent.width
                  height: root.s(14)

                  Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: "PRODUCTIVE"
                    color: root.fg
                    font.family: Style.font.family
                    font.pixelSize: root.fs(8)
                    font.bold: true
                    font.letterSpacing: root.s(0.9)
                  }

                  Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: "PEAK " + Pocus.formatDuration(root.trend.maxProductive * 60)
                    color: root.faint
                    font.family: Style.font.family
                    font.pixelSize: root.fs(8)
                  }
                }

                TrendChart {
                  id: graphTrend
                  width: parent.width
                  height: root.s(72)
                  values: root.productiveValues
                  labels: root.dayLabels
                  lineColor: root.fg
                  dotColor: root.fg
                  labelColor: root.fg
                  areaFill: true
                  onHovered: function(index) { root.graphHoverIndex = index }
                }

                Item {
                  width: parent.width
                  height: root.s(14)

                  Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: "OFF TIME"
                    color: root.muted
                    font.family: Style.font.family
                    font.pixelSize: root.fs(8)
                    font.bold: true
                    font.letterSpacing: root.s(0.9)
                  }

                  Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: "PEAK " + Pocus.formatDuration(root.trend.maxOff * 60)
                    color: root.faint
                    font.family: Style.font.family
                    font.pixelSize: root.fs(8)
                  }
                }

                TrendChart {
                  width: parent.width
                  height: root.s(56)
                  values: root.offValues
                  labels: root.dayLabels
                  lineColor: Util.alpha(root.fg, 0.55)
                  dotColor: Util.alpha(root.fg, 0.55)
                  labelColor: root.fg
                  onHovered: function(index) { root.graphHoverIndex = index }
                }

                Item {
                  width: parent.width
                  height: root.s(18)

                  Text {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: root.graphFooter
                    color: root.muted
                    font.family: Style.font.family
                    font.pixelSize: root.fs(9)
                    elide: Text.ElideRight
                  }
                }
              }
            }

            // ----------------------------------------------- heatmap page
            Item {
              width: pageViewport.pageWidth
              height: pageViewport.height

              Column {
                id: heatmapColumn
                width: parent.width
                spacing: root.s(8)

                Row {
                  id: statsRow
                  width: parent.width
                  height: implicitHeight
                  spacing: root.s(7)

                  Stat {
                    width: (parent.width - parent.spacing * 3) / 4
                    label: "TODAY"
                    value: Pocus.formatDuration(root.pSeconds)
                    valueColor: root.fg
                    labelColor: root.faint
                  }

                  Stat {
                    width: (parent.width - parent.spacing * 3) / 4
                    label: "THIS WEEK"
                    value: Pocus.formatDuration(root.heatmap.weekProductive)
                    valueColor: root.fg
                    labelColor: root.faint
                  }

                  Stat {
                    width: (parent.width - parent.spacing * 3) / 4
                    label: "BEST DAY"
                    value: Pocus.formatDuration(root.best.seconds)
                    valueColor: root.fg
                    labelColor: root.faint
                  }

                  Stat {
                    width: (parent.width - parent.spacing * 3) / 4
                    label: "STREAK"
                    value: root.heatmap.streak + "d"
                    valueColor: root.fg
                    labelColor: root.faint
                  }
                }

                Item {
                  width: parent.width
                  height: root.s(32)

                  Row {
                    width: parent.width
                    anchors.top: parent.top

                    Text {
                      id: balanceTitle
                      textFormat: Text.PlainText
                      text: "TODAY'S BALANCE"
                      color: root.faint
                      font.family: Style.font.family
                      font.pixelSize: root.fs(8)
                      font.bold: true
                      font.letterSpacing: root.s(0.8)
                    }

                    Item {
                      width: Math.max(0, parent.width - balanceTitle.width - balancePercent.width)
                      height: 1
                    }

                    Text {
                      id: balancePercent
                      textFormat: Text.PlainText
                      text: Math.round(root.balanceRatio * 100) + "% PRODUCTIVE"
                      color: root.muted
                      font.family: Style.font.family
                      font.pixelSize: root.fs(8)
                      font.bold: true
                      font.letterSpacing: root.s(0.5)
                    }
                  }

                  Rectangle {
                    y: root.s(14)
                    width: parent.width
                    height: root.s(5)
                    radius: height / 2
                    color: root.hairline

                    Rectangle {
                      width: parent.width * root.balanceRatio
                      height: parent.height
                      radius: height / 2
                      color: Util.alpha(root.accent, 0.65)

                      Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                    }
                  }

                  Row {
                    y: root.s(22)
                    width: parent.width

                    Text {
                      id: productiveTodayLabel
                      textFormat: Text.PlainText
                      text: Pocus.formatDuration(root.pSeconds) + " productive"
                      color: root.muted
                      font.family: Style.font.family
                      font.pixelSize: root.fs(8)
                    }

                    Item {
                      width: Math.max(0, parent.width - productiveTodayLabel.width - offLabel.width)
                      height: 1
                    }

                    Text {
                      id: offLabel
                      textFormat: Text.PlainText
                      text: Pocus.formatDuration(root.oSeconds) + " off"
                      color: root.faint
                      font.family: Style.font.family
                      font.pixelSize: root.fs(8)
                    }
                  }
                }

                Heatmap {
                  id: heatmapItem
                  width: parent.width
                  height: implicitHeight
                  weeks: root.heatmap.weeks
                  monthLabels: root.heatmap.monthLabels
                  weekCount: 52
                  ink: root.fg
                  activeKey: root.heatmapActiveKey
                  onDayHovered: function(key) { root.heatmapHoverKey = key }
                  onDaySelected: function(key) {
                    root.pinnedDayKey = root.pinnedDayKey === key ? "" : key
                  }
                  onSwipeStarted: function(startX) { root.startPageDrag(startX) }
                  onSwipeMoved: function(currX) { root.updatePageDrag(currX) }
                  onSwipeEnded: function(currX) { root.endPageDrag(currX) }
                }

                Item {
                  width: parent.width
                  height: root.s(18)

                  Text {
                    anchors.left: parent.left
                    anchors.right: legendRow.left
                    anchors.rightMargin: root.s(10)
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: root.heatmapFooter
                    color: root.muted
                    font.family: Style.font.family
                    font.pixelSize: root.fs(9)
                    elide: Text.ElideRight
                  }

                  Row {
                    id: legendRow
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: root.s(4)
                    height: root.s(14)

                    Text {
                      textFormat: Text.PlainText
                      text: "LESS"
                      color: root.faint
                      font.family: Style.font.family
                      font.pixelSize: root.fs(7.5)
                      font.bold: true
                      font.letterSpacing: root.s(0.5)
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    Repeater {
                      model: root.heatmapLevels

                      Rectangle {
                        required property var modelData
                        width: root.s(7)
                        height: width
                        radius: Math.max(1, Math.round(width * 0.22))
                        color: Util.alpha(root.fg, modelData)
                        anchors.verticalCenter: parent.verticalCenter
                      }
                    }

                    Text {
                      textFormat: Text.PlainText
                      text: "MORE"
                      color: root.faint
                      font.family: Style.font.family
                      font.pixelSize: root.fs(7.5)
                      font.bold: true
                      font.letterSpacing: root.s(0.5)
                      anchors.verticalCenter: parent.verticalCenter
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

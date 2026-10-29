import QtQuick
import qs.Commons
import qs.Ui
import "Pocus.js" as Pocus

// Pocus bar widget: a tiny mug that fills while tracking, plus today's
// productive total. Left click opens the panel, right click toggles the
// timer, middle click opens straight to the heatmap.
BarWidget {
  id: root
  moduleName: "io.github.mohiitp.pocus"

  readonly property string pluginId: "io.github.mohiitp.pocus"

  // The service is mounted separately from the widget and can arrive a beat
  // later, so bind lazily and poll until it exists.
  property var service: null
  property var uiOpenFn: null
  property var uiCloseFn: null
  property var uiToggleFn: null
  property var uiIsOpenFn: null
  property var uiOpenPageFn: null

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool tracking: service ? service.running : false
  readonly property color foreground: bar ? bar.barForeground : Color.foreground

  readonly property string barText: service ? Pocus.formatDuration(service.productiveSeconds) : "0m"
  readonly property string tooltipText: {
    if (!service) return "Pocus"
    var totalP = Pocus.formatDuration(service.productiveSeconds)
    var currP = Pocus.formatDuration(service.currentProductiveSeconds)
    var currO = Pocus.formatDuration(service.currentOffSeconds)
    if (service.running) {
      return "Pocus · " + totalP + " total productive · " + currP + " current focus · click to open"
    }
    return "Pocus · " + totalP + " total productive · " + currO + " current off · click to open"
  }

  visible: !vertical
  implicitWidth: contentRow.implicitWidth + Style.space(12)
  implicitHeight: barSize

  function bindService() {
    if (root.service) return
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.serviceFor !== "function") return
    root.service = root.bar.shell.serviceFor(root.pluginId)
  }

  function registerUi() {
    if (!root.service) return

    root.uiOpenFn = function() { root.open() }
    root.uiCloseFn = function() { root.close() }
    root.uiToggleFn = function() { root.toggle() }
    root.uiIsOpenFn = function() { return root.opened }
    root.uiOpenPageFn = function(index) { root.openPage(index) }

    root.service.uiOpen = root.uiOpenFn
    root.service.uiClose = root.uiCloseFn
    root.service.uiToggle = root.uiToggleFn
    root.service.uiIsOpen = root.uiIsOpenFn
    root.service.uiOpenPage = root.uiOpenPageFn
    root.syncSettings()
  }

  function unregisterUi() {
    if (!root.service) return
    if (root.service.uiOpen === root.uiOpenFn) root.service.uiOpen = null
    if (root.service.uiClose === root.uiCloseFn) root.service.uiClose = null
    if (root.service.uiToggle === root.uiToggleFn) root.service.uiToggle = null
    if (root.service.uiIsOpen === root.uiIsOpenFn) root.service.uiIsOpen = null
    if (root.service.uiOpenPage === root.uiOpenPageFn) root.service.uiOpenPage = null
  }

  function syncSettings() {
    if (!root.service) return
    var hours = Number(root.setting("goalHours", 4))
    if (!isFinite(hours) || hours <= 0) hours = 4
    root.service.setGoalMinutes(Math.round(hours * 60))
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = button
    target.hostWidget = root
  }

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function openPage(index) { if (panelLoader.item && panelLoader.item.openPage) panelLoader.item.openPage(index) }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  onBarChanged: {
    unregisterUi()
    root.service = null
    bindService()
  }
  onSettingsChanged: syncSettings()
  onServiceChanged: registerUi()

  Component.onCompleted: bindService()
  Component.onDestruction: unregisterUi()

  Timer {
    interval: 500
    repeat: true
    running: root.service === null
    onTriggered: root.bindService()
  }

  Loader {
    id: panelLoader
    active: true
    visible: false
    source: Qt.resolvedUrl("Panel.qml")
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  Item {
    id: button
    anchors.fill: parent

    Row {
      id: contentRow
      anchors.centerIn: parent
      spacing: Style.space(4)

      Cup {
        width: Style.space(12)
        height: Style.space(15)
        level: root.tracking ? 1 : 0
        active: root.tracking
        animateWaves: false
        ink: root.foreground
        liquid: root.foreground
      }

      Text {
        textFormat: Text.PlainText
        text: root.barText
        color: root.foreground
        opacity: root.tracking ? 0.95 : 0.62
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        renderType: Text.NativeRendering
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor

      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) {
          if (root.service) root.service.toggleTracking()
        } else if (mouse.button === Qt.MiddleButton) {
          root.openPage(1)
        } else {
          root.toggle()
        }
      }

      onEntered: if (root.bar) root.bar.showTooltip(root, root.tooltipText)
      onExited: if (root.bar) root.bar.hideTooltip(root)
    }
  }
}

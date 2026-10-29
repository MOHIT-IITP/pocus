import QtQuick
import Quickshell
import Quickshell.Io
import "Pocus.js" as Pocus

// Pocus service — owns the productive/off counters, persists a year of daily
// history, and survives bar rebuilds. The timer is a single on/off switch:
// while it runs, every second is productive; while it does not, every second
// is off time. Time lost to suspend or a frozen shell is never counted.
Item {
  id: service
  width: 0
  height: 0
  visible: false

  // Injected by the Omarchy shell when a service entry point is mounted.
  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: home + "/.local/state/omarchy"
  readonly property string statePath: stateDir + "/pocus.json"

  property bool stateDirectoryReady: false
  property bool hydrated: false
  property bool pendingSave: false

  property bool running: false
  property real productiveSeconds: 0
  property real offSeconds: 0
  property real currentProductiveSeconds: 0
  property real currentOffSeconds: 0
  property int goalMinutes: 240
  property double lastTickMs: 0
  property var history: ({})
  property string todayKey: Pocus.dateKey(new Date())

  property int ticksSinceSave: 0

  // Deltas longer than this are treated as a stall or a suspend: the shell
  // was not observing the machine, so neither counter should invent time.
  readonly property int maxTickMs: 15000
  readonly property int saveEveryTicks: 30

  readonly property int todayProductiveMinutes: Math.floor(productiveSeconds / 60)
  readonly property int todayOffMinutes: Math.floor(offSeconds / 60)
  readonly property int activeDays: Object.keys(history).length
  readonly property real goalRatio: goalMinutes > 0
    ? Math.min(1, productiveSeconds / (goalMinutes * 60))
    : 0
  readonly property int goalPercent: Math.round(goalRatio * 100)
  readonly property string productiveLabel: Pocus.formatHMS(productiveSeconds)
  readonly property string offLabel: Pocus.formatHMS(offSeconds)
  readonly property string currentProductiveLabel: Pocus.formatHMS(currentProductiveSeconds)
  readonly property string currentOffLabel: Pocus.formatHMS(currentOffSeconds)

  // Panel lifecycle hooks, registered by the bar widget, so IPC can summon the
  // UI without hunting for the right widget.
  property var uiOpen: null
  property var uiClose: null
  property var uiToggle: null
  property var uiIsOpen: null
  property var uiOpenPage: null

  function clampGoal(value) {
    var minutes = Math.round(Number(value))
    if (!isFinite(minutes) || minutes <= 0) minutes = 240
    return Math.max(15, Math.min(1440, minutes))
  }

  function sanitizeHistory(raw) {
    var clean = {}
    if (!raw || typeof raw !== "object") return clean

    for (var key in raw) {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(String(key))) continue
      var entry = Pocus.normalizeEntry(raw[key])
      if (entry.p === 0 && entry.o === 0) continue
      clean[key] = entry
    }

    return clean
  }

  function commitToday() {
    var p = Math.round(productiveSeconds)
    var o = Math.round(offSeconds)
    if (p <= 0 && o <= 0) return

    var next = {}
    for (var day in history) next[day] = history[day]
    next[todayKey] = Pocus.addEntry(next[todayKey], p, o)
    history = next
  }

  function loadState(raw) {
    if (hydrated) return

    var data = {}
    try { data = JSON.parse(raw || "{}") || {} }
    catch (error) { data = {} }

    var now = Date.now()
    var nowKey = Pocus.dateKey(new Date(now))
    var historyIn = sanitizeHistory(data.history)
    var savedKey = String(data.todayKey || "")

    var savedP = Math.max(0, Number(data.productiveSeconds) || 0)
    var savedO = Math.max(0, Number(data.offSeconds) || 0)
    var savedCurrP = Math.max(0, Number(data.currentProductiveSeconds) || 0)
    var savedCurrO = Math.max(0, Number(data.currentOffSeconds) || 0)

    // The file may be a day (or a week) old. Commit the saved day as it was
    // left, then start today from zero; the time the shell was down is not
    // guessed at.
    if (/^\d{4}-\d{2}-\d{2}$/.test(savedKey) && savedKey !== nowKey) {
      if (savedP + savedO > 0) {
        historyIn[savedKey] = Pocus.addEntry(historyIn[savedKey], savedP, savedO)
      }
      savedP = 0
      savedO = 0
      savedCurrP = 0
      savedCurrO = 0
    } else if (savedKey !== nowKey) {
      savedP = 0
      savedO = 0
      savedCurrP = 0
      savedCurrO = 0
    }

    // Today's live counters are authoritative; never read them twice.
    delete historyIn[nowKey]

    history = Pocus.prune(historyIn, nowKey, 400)
    productiveSeconds = savedP
    offSeconds = savedO
    currentProductiveSeconds = savedCurrP
    currentOffSeconds = savedCurrO
    running = data.running === true
    goalMinutes = clampGoal(data.goalMinutes)
    todayKey = nowKey
    lastTickMs = now
    hydrated = true

    // Normalise the file now that stale days have been folded in.
    saveState()
  }

  function saveState() {
    if (!hydrated) return
    if (!stateDirectoryReady) {
      pendingSave = true
      return
    }

    pendingSave = false
    ticksSinceSave = 0

    stateFile.setText(JSON.stringify({
      version: 1,
      running: running,
      todayKey: todayKey,
      productiveSeconds: Math.round(productiveSeconds),
      offSeconds: Math.round(offSeconds),
      currentProductiveSeconds: Math.round(currentProductiveSeconds),
      currentOffSeconds: Math.round(currentOffSeconds),
      goalMinutes: goalMinutes,
      history: history
    }, null, 2) + "\n")
  }

  function rollDayIfNeeded(now) {
    var key = Pocus.dateKey(new Date(now))
    if (key === todayKey) return false

    commitToday()
    todayKey = key
    productiveSeconds = 0
    offSeconds = 0
    currentProductiveSeconds = 0
    currentOffSeconds = 0
    history = Pocus.prune(history, key, 400)
    saveState()
    return true
  }

  function tick() {
    if (!hydrated) return

    var now = Date.now()
    var delta = now - lastTickMs
    lastTickMs = now

    // A sleep, a resume, or a busy loop leaves a hole in observations. Count
    // nothing for it rather than inventing hours of productive time.
    if (!isFinite(delta) || delta < 0 || delta > maxTickMs) delta = 0

    rollDayIfNeeded(now)

    var seconds = delta / 1000
    if (running) {
      productiveSeconds += seconds
      currentProductiveSeconds += seconds
    } else {
      offSeconds += seconds
      currentOffSeconds += seconds
    }

    ticksSinceSave += 1
    if (ticksSinceSave >= saveEveryTicks) saveState()
  }

  function start() {
    if (!hydrated || running) return
    tick()  // assign the elapsed off time before the switch
    running = true
    currentProductiveSeconds = 0
    lastTickMs = Date.now()
    saveState()
  }

  function pause() {
    if (!hydrated || !running) return
    tick()  // assign the elapsed productive time before the switch
    running = false
    currentOffSeconds = 0
    lastTickMs = Date.now()
    saveState()
  }

  function toggleTracking() {
    if (running) pause()
    else start()
  }

  function resetToday() {
    if (!hydrated) return
    productiveSeconds = 0
    offSeconds = 0
    currentProductiveSeconds = 0
    currentOffSeconds = 0
    saveState()
  }

  function resetAll() {
    if (!hydrated) return
    running = false
    productiveSeconds = 0
    offSeconds = 0
    currentProductiveSeconds = 0
    currentOffSeconds = 0
    history = ({})
    lastTickMs = Date.now()
    saveState()
  }

  function setGoalMinutes(value) {
    var next = clampGoal(value)
    if (next === goalMinutes) return
    goalMinutes = next
    saveState()
  }

  function statusJson() {
    return JSON.stringify({
      version: 1,
      running: running,
      todayKey: todayKey,
      productiveSeconds: Math.round(productiveSeconds),
      offSeconds: Math.round(offSeconds),
      currentProductiveSeconds: Math.round(currentProductiveSeconds),
      currentOffSeconds: Math.round(currentOffSeconds),
      productive: productiveLabel,
      off: offLabel,
      currentProductive: currentProductiveLabel,
      currentOff: currentOffLabel,
      productiveMinutes: todayProductiveMinutes,
      offMinutes: todayOffMinutes,
      goalMinutes: goalMinutes,
      goalPercent: goalPercent,
      activeDays: activeDays
    })
  }

  FileView {
    id: stateFile
    path: service.statePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: service.loadState(text())
    onLoadFailed: service.loadState("")
  }

  Process {
    id: stateDirectoryProcess
    command: ["mkdir", "-p", service.stateDir]
    onExited: {
      service.stateDirectoryReady = true
      if (service.pendingSave) service.saveState()
    }
  }

  Timer {
    interval: 1000
    repeat: true
    running: service.hydrated
    triggeredOnStart: false
    onTriggered: service.tick()
  }

  // A cheap second guard for a laptop that stayed awake through midnight with
  // the tick timer starved.
  Timer {
    interval: 60000
    repeat: true
    running: service.hydrated
    onTriggered: service.rollDayIfNeeded(Date.now())
  }

  IpcHandler {
    target: "pocus"

    function open(): void {
      if (typeof service.uiOpen === "function") service.uiOpen()
    }
    function close(): void {
      if (typeof service.uiClose === "function") service.uiClose()
    }
    function toggle(): void {
      if (typeof service.uiToggle === "function") service.uiToggle()
    }
    function graph(): void {
      if (typeof service.uiOpenPage === "function") service.uiOpenPage(0)
    }
    function heatmap(): void {
      if (typeof service.uiOpenPage === "function") service.uiOpenPage(1)
    }
    function start(): void { service.start() }
    function pause(): void { service.pause() }
    function toggleTimer(): void { service.toggleTracking() }
    function reset(): void { service.resetToday() }
    function resetAll(): void { service.resetAll() }
    function clear(): void { service.resetAll() }
    function setGoal(minutes: string): void { service.setGoalMinutes(Number(minutes)) }
    function status(): string { return service.statusJson() }
  }

  Component.onCompleted: stateDirectoryProcess.running = true
  Component.onDestruction: service.saveState()
}

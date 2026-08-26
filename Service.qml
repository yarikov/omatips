import QtQuick
import Quickshell
import Quickshell.Io
import "TipModel.js" as TipModel

Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")
  readonly property string stateDir: stateHome + "/omarchy/omatips"
  readonly property string statePath: stateDir + "/state.json"
  readonly property string stateBackupPath: statePath + ".bak"
  readonly property string tipsPath: manifest && manifest.__sourceDir ? manifest.__sourceDir + "/tips.json" : ""

  property var tips: []
  property var studyState: TipModel.defaultState()
  property double nowMs: Date.now()
  property double notificationSnoozedUntil: 0
  property bool storageReady: false
  property bool tipsReady: false
  property bool initialized: false
  property bool recoveringState: false
  property string lastValidStateRaw: ""
  property bool actionBusy: false

  readonly property var lockService: shell && shell.firstPartyServiceFor
    ? shell.firstPartyServiceFor("omarchy.lock") : null
  readonly property var idleService: shell && shell.firstPartyServiceFor
    ? shell.firstPartyServiceFor("omarchy.idle") : null
  readonly property bool sessionActive: (!lockService || !lockService.locked)
    && (!idleService || !idleService.idledThisCycle)
  readonly property int totalTips: tips.length
  readonly property int introducedCount: Number(studyState.nextNewIndex || 0)
  readonly property var dueReviews: TipModel.dueReviews(studyState, tips, nowMs)
  readonly property int dueReviewCount: dueReviews.length
  readonly property var nextNewItem: TipModel.nextNew(studyState, tips, nowMs)
  readonly property var studyItems: TipModel.studyQueue(studyState, tips, nowMs)
  readonly property var currentItem: studyItems.length > 0 ? studyItems[0] : null
  readonly property var currentTip: currentItem ? currentItem.tip : null
  readonly property bool hasStudyItem: currentItem !== null
  readonly property double nextDueAt: TipModel.nextDueAt(studyState, tips, nowMs)
  readonly property string nextDueLabel: nextDueAt < 0 ? "No reviews scheduled" : TipModel.formatWait(Math.max(0, nextDueAt - nowMs))

  function maybeInitialize() {
    if (initialized || !storageReady || !tipsReady) return
    initialized = true
    stateFile.reload()
  }

  function persist() {
    var serialized = JSON.stringify(studyState, null, 2) + "\n"
    if (lastValidStateRaw !== "" && lastValidStateRaw !== serialized)
      stateBackupFile.setText(lastValidStateRaw)
    stateFile.setText(serialized)
    lastValidStateRaw = serialized
  }

  function applyPrimaryState(raw) {
    nowMs = Date.now()
    studyState = TipModel.parseState(raw, tips, nowMs)
    var serialized = JSON.stringify(studyState, null, 2) + "\n"
    if (String(raw) !== serialized) {
      stateBackupFile.setText(String(raw))
      stateFile.setText(serialized)
    }
    lastValidStateRaw = serialized
    Qt.callLater(checkQueue)
  }

  function applyBackupState(raw) {
    nowMs = Date.now()
    studyState = TipModel.parseState(raw, tips, nowMs)
    lastValidStateRaw = JSON.stringify(studyState, null, 2) + "\n"
    stateFile.setText(lastValidStateRaw)
    Qt.callLater(checkQueue)
  }

  function startNewCourse() {
    nowMs = Date.now()
    studyState = TipModel.defaultState()
    lastValidStateRaw = ""
    persist()
    Qt.callLater(checkQueue)
  }

  function recoverStoredState() {
    if (recoveringState) return
    recoveringState = true
    console.warn("OmaTips: primary state unavailable or invalid; trying backup")
    stateBackupFile.reload()
  }

  function stateWithNotification(notificationDate) {
    return {
      schemaVersion: studyState.schemaVersion,
      nextNewIndex: studyState.nextNewIndex,
      cards: studyState.cards,
      lastNotificationDate: notificationDate
    }
  }

  function checkQueue() {
    if (!initialized || !tipsReady) return
    nowMs = Date.now()
    var now = new Date(nowMs)
    var today = TipModel.localDateKey(now)
    if (!currentItem || !sessionActive || !TipModel.withinNotificationHours(now)
        || !TipModel.shouldNotifyToday(studyState, today)
        || nowMs < notificationSnoozedUntil || notificationProcess.running) return
    studyState = stateWithNotification(today)
    persist()
    sendNotification()
  }

  function reviewCurrent(rating) {
    if (!currentTip) return false
    nowMs = Date.now()
    var result = TipModel.review(studyState, tips, currentTip.id, rating, nowMs)
    if (!result.reviewed) return false
    studyState = result.state
    notificationSnoozedUntil = nowMs + 5 * 60 * 1000
    persist()
    return true
  }

  function sendNotification() {
    if (!currentTip || notificationProcess.running) return
    notificationProcess.command = [
      "notify-send",
      "--app-name=OmaTips",
      "--icon=dialog-information",
      "--expire-time=12000",
      "--action=default=Study now",
      "OmaTips",
      "Time to study your cards."
    ]
    notificationProcess.running = true
  }

  function runAction(tip) {
    if (!tip || !TipModel.validAction(tip.action) || actionBusy) return false
    var action = tip.action
    var argv = action.kind === "copy" ? ["wl-copy", action.text] : action.argv
    actionBusy = true
    actionProcess.command = argv
    actionProcess.running = true
    return true
  }

  Process {
    id: storageInit
    command: ["mkdir", "-p", root.stateDir]
    onExited: function(exitCode) {
      if (exitCode === 0) stateBackupInit.running = true
      else console.warn("OmaTips: could not create state directory")
    }
  }

  Process {
    id: stateBackupInit
    command: ["touch", root.stateBackupPath]
    onExited: function(exitCode) {
      root.storageReady = exitCode === 0
      if (!root.storageReady) console.warn("OmaTips: could not initialize state backup")
      root.maybeInitialize()
    }
  }

  FileView {
    id: tipsFile
    path: root.tipsPath
    printErrors: false
    onLoaded: {
      root.tips = TipModel.parseTips(text())
      root.tipsReady = root.tips.length > 0
      if (!root.tipsReady) console.warn("OmaTips: tips.json must contain at least one valid tip")
      root.maybeInitialize()
    }
    onLoadFailed: {
      if (root.tipsPath !== "") console.warn("OmaTips: could not load " + root.tipsPath)
    }
  }

  FileView {
    id: stateFile
    path: root.statePath
    atomicWrites: true
    printErrors: false
    onLoaded: {
      if (!root.initialized) return
      if (TipModel.validStoredState(text())) root.applyPrimaryState(text())
      else root.recoverStoredState()
    }
    onLoadFailed: {
      if (root.initialized) root.recoverStoredState()
    }
  }

  FileView {
    id: stateBackupFile
    path: root.stateBackupPath
    atomicWrites: true
    printErrors: false
    onLoaded: {
      if (!root.recoveringState) return
      root.recoveringState = false
      if (TipModel.validStoredState(text())) {
        console.warn("OmaTips: restored study progress from backup")
        root.applyBackupState(text())
      } else {
        console.warn("OmaTips: backup state is invalid; starting a new course")
        root.startNewCourse()
      }
    }
    onLoadFailed: {
      if (!root.recoveringState) return
      root.recoveringState = false
      console.warn("OmaTips: no readable state backup; starting a new course")
      root.startNewCourse()
    }
  }

  Timer {
    interval: 30000
    running: root.initialized
    repeat: true
    onTriggered: root.checkQueue()
  }

  Connections {
    target: root.lockService
    ignoreUnknownSignals: true
    function onLockedChanged() {
      if (!root.lockService.locked) root.checkQueue()
    }
  }

  Connections {
    target: root.idleService
    ignoreUnknownSignals: true
    function onIdledThisCycleChanged() {
      if (!root.idleService.idledThisCycle) root.checkQueue()
    }
  }

  Process {
    id: notificationProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (TipModel.opensPluginForNotificationAction(text) && root.shell)
          root.shell.summon("yarikov.omatips", "{}")
      }
    }
  }

  Process {
    id: actionProcess
    onExited: function() { root.actionBusy = false }
  }

  Component.onCompleted: storageInit.running = true
}

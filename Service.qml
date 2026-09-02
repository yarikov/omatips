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
  readonly property int maxStateBytes: TipModel.MAX_STATE_BYTES
  readonly property string tipsPath: manifest && manifest.__sourceDir ? manifest.__sourceDir + "/tips.json" : ""
  readonly property string stateReadPath: manifest && manifest.__sourceDir ? manifest.__sourceDir + "/state_read.py" : ""
  readonly property string stateWritePath: manifest && manifest.__sourceDir ? manifest.__sourceDir + "/state_write.py" : ""

  property var tips: []
  property var studyState: TipModel.defaultState()
  property double nowMs: Date.now()
  property double notificationSnoozedUntil: 0
  property bool storageReady: false
  property bool tipsReady: false
  property bool initializationStarted: false
  property bool initialized: false
  property bool recoveringState: false
  property bool primaryStateMissing: false
  property bool stateStorageBlocked: false
  property bool actionBusy: false
  property bool removalBusy: false
  property string removalError: ""

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
  readonly property var panelSession: studyState.panelSession || ({
    tipId: "", answerRevealed: false, cursorTarget: "",
    preferredRating: "again", confirmationAction: "", confirmationOrigin: ""
  })
  readonly property string activeTipId: String(panelSession.tipId || "")
  readonly property var currentItem: TipModel.selectedStudyItem(
    studyItems, nextNewItem, activeTipId)
  readonly property var currentTip: currentItem ? currentItem.tip : null
  readonly property bool hasStudyItem: currentItem !== null
  readonly property double nextDueAt: TipModel.nextDueAt(studyState, tips, nowMs)
  readonly property bool courseCompleted: initialized && tipsReady
    && TipModel.courseCompleted(studyState, tips, nowMs)
  readonly property string nextDueLabel: nextDueAt < 0 ? "No reviews scheduled" : TipModel.formatWait(Math.max(0, nextDueAt - nowMs))

  function maybeInitialize() {
    if (initializationStarted || !storageReady || !tipsReady) return
    initializationStarted = true
    stateReadProcess.running = true
  }

  function persist() {
    if (stateStorageBlocked) return false
    studyState.storageRevision = Number(studyState.storageRevision || 0) + 1
    var serialized = JSON.stringify(studyState) + "\n"
    if (!TipModel.stateSizeAllowed(TipModel.utf8ByteLength(serialized))) {
      blockStateStorage("serialized state exceeds the size limit")
      return false
    }
    stateWriteProcess.command = ["/usr/bin/python3", stateWritePath, "commit",
      statePath, stateBackupPath, String(maxStateBytes),
      String(studyState.storageRevision), Qt.btoa(serialized)]
    stateWriteProcess.startDetached()
    return true
  }

  function applyPrimaryState(raw) {
    nowMs = Date.now()
    studyState = TipModel.parseState(raw, tips, nowMs)
    initialized = true
    var serialized = JSON.stringify(studyState) + "\n"
    if (String(raw) !== serialized) persist()
    Qt.callLater(checkQueue)
  }

  function startNewCourse() {
    nowMs = Date.now()
    studyState = TipModel.defaultState()
    initialized = true
    persist()
    Qt.callLater(checkQueue)
  }

  function recoverStoredState(primaryMissing) {
    if (recoveringState) return
    recoveringState = true
    primaryStateMissing = primaryMissing === true
    console.warn("OmaTips: primary state unavailable or invalid; trying backup")
    stateBackupReadProcess.running = true
  }

  function applyBackupState(raw) {
    nowMs = Date.now()
    studyState = TipModel.parseState(raw, tips, nowMs)
    initialized = true
    recoveringState = false
    persist()
    console.warn("OmaTips: restored study progress from backup")
    Qt.callLater(checkQueue)
  }

  function restartCourse() {
    if (!initialized || stateStorageBlocked || removalBusy) return false
    nowMs = Date.now()
    var next = TipModel.defaultState()
    next.storageRevision = Number(studyState.storageRevision || 0)
    next.lastNotificationDate = TipModel.studyDayKey(new Date(nowMs))
    studyState = next
    notificationSnoozedUntil = nowMs + 5 * 60 * 1000
    removalError = ""
    persist()
    return true
  }

  function removePlugin() {
    if (!initialized || removalBusy) return false
    removalBusy = true
    stateStorageBlocked = true
    removalError = ""
    var revision = Number(studyState.storageRevision || 0) + 1
    stateDeleteProcess.command = ["/usr/bin/python3", stateWritePath, "delete",
      statePath, stateBackupPath, String(maxStateBytes), String(revision)]
    stateDeleteProcess.running = true
    return true
  }

  function blockStateStorage(message) {
    stateStorageBlocked = true
    console.error("OmaTips: " + message + "; state storage is disabled")
  }

  function stateWithNotification(notificationDate) {
    return {
      schemaVersion: studyState.schemaVersion,
      storageRevision: studyState.storageRevision,
      nextNewIndex: studyState.nextNewIndex,
      cards: studyState.cards,
      lastNotificationDate: notificationDate,
      panelSession: studyState.panelSession
    }
  }

  function savePanelSession(tipId, answerRevealed, cursorTarget,
                            preferredRating, confirmationAction, confirmationOrigin) {
    if (!initialized || stateStorageBlocked) return false
    studyState = TipModel.withPanelSession(studyState, tips, tipId,
      answerRevealed, cursorTarget, preferredRating,
      confirmationAction, confirmationOrigin, nowMs)
    return persist()
  }

  function recordPanelOpened(openedTipId) {
    if (!initialized || stateStorageBlocked) return
    var tipId = String(openedTipId || "")
    if (tipId === "" && currentTip) tipId = currentTip.id
    var previous = panelSession
    savePanelSession(tipId,
      previous.tipId === tipId && previous.answerRevealed === true,
      previous.tipId === tipId ? previous.cursorTarget : "showAnswer",
      previous.tipId === tipId ? previous.preferredRating : "again",
      previous.tipId === tipId ? previous.confirmationAction : "",
      previous.tipId === tipId ? previous.confirmationOrigin : "")
    nowMs = Date.now()
    var now = new Date(nowMs)
    var studyDay = TipModel.studyDayKey(now)
    if (!TipModel.shouldNotifyToday(studyState, studyDay)) return
    studyState = stateWithNotification(studyDay)
    persist()
  }

  function checkQueue() {
    if (!initialized || !tipsReady || stateStorageBlocked) return
    nowMs = Date.now()
    var now = new Date(nowMs)
    var studyDay = TipModel.studyDayKey(now)
    if (!currentItem || !sessionActive || !TipModel.withinNotificationHours(now)
        || !TipModel.shouldNotifyToday(studyState, studyDay)
        || nowMs < notificationSnoozedUntil || notificationProcess.running) return
    studyState = stateWithNotification(studyDay)
    persist()
    sendNotification()
  }

  function reviewCurrent(rating) {
    if (!initialized || !currentTip || stateStorageBlocked) return false
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
      "omarchy-notification-send",
      "--app-name=OmaTips",
      "--glyph=󰌵",
      "--urgency=normal",
      "OmaTips",
      "Time to study your cards.",
      "--exec",
      "omarchy-shell",
      "shell",
      "summon",
      "yarikov.omatips",
      "{}"
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
      root.storageReady = exitCode === 0
      if (!root.storageReady) console.warn("OmaTips: could not create state directory")
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

  Process {
    id: stateWriteProcess
  }

  Process {
    id: stateReadProcess
    command: ["/usr/bin/timeout", "2s", "/usr/bin/python3", root.stateReadPath,
      root.statePath, String(root.maxStateBytes)]
    stdout: StdioCollector {
      id: stateReadOutput
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (!root.initializationStarted || root.initialized) return
      if (exitCode === 10) {
        root.recoverStoredState(true)
      } else if (exitCode !== 0) {
        root.recoverStoredState(false)
      } else if (stateReadOutput.data === null || stateReadOutput.data === undefined) {
        root.recoverStoredState(false)
      } else if (!TipModel.stateSizeAllowed(stateReadOutput.data.byteLength)) {
        root.recoverStoredState(false)
      } else if (TipModel.validStoredState(stateReadOutput.text)) {
        root.applyPrimaryState(stateReadOutput.text)
      } else {
        root.recoverStoredState(false)
      }
    }
  }

  Process {
    id: stateBackupReadProcess
    command: ["/usr/bin/timeout", "2s", "/usr/bin/python3", root.stateReadPath,
      root.stateBackupPath, String(root.maxStateBytes)]
    stdout: StdioCollector {
      id: stateBackupReadOutput
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (!root.recoveringState || root.initialized) return
      if (exitCode === 0 && stateBackupReadOutput.data !== null
          && stateBackupReadOutput.data !== undefined
          && TipModel.stateSizeAllowed(stateBackupReadOutput.data.byteLength)
          && TipModel.validStoredState(stateBackupReadOutput.text)) {
        root.applyBackupState(stateBackupReadOutput.text)
      } else if (root.primaryStateMissing && exitCode === 10) {
        root.recoveringState = false
        console.warn("OmaTips: no stored state; starting a new course")
        root.startNewCourse()
      } else {
        root.blockStateStorage("primary state and backup are unavailable or invalid")
      }
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

  Process { id: notificationProcess }

  Process {
    id: actionProcess
    onExited: function() { root.actionBusy = false }
  }

  Process {
    id: stateDeleteProcess
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.removalBusy = false
        root.removalError = "Could not delete course progress. OmaTips was not uninstalled."
        return
      }
      pluginRemoveProcess.startDetached()
    }
  }

  Process {
    id: pluginRemoveProcess
    command: ["/usr/bin/omarchy", "plugin", "remove", "yarikov.omatips", "--yes"]
  }

  Component.onCompleted: storageInit.running = true
}

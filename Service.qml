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
  readonly property int maxStateBytes: TipModel.MAX_STATE_BYTES
  readonly property string tipsPath: manifest && manifest.__sourceDir ? manifest.__sourceDir + "/tips.json" : ""
  readonly property string stateReadPath: manifest && manifest.__sourceDir ? manifest.__sourceDir + "/state_read.py" : ""

  property var tips: []
  property var studyState: TipModel.defaultState()
  property double nowMs: Date.now()
  property double notificationSnoozedUntil: 0
  property bool storageReady: false
  property bool tipsReady: false
  property bool initialized: false
  property bool stateStorageBlocked: false
  property bool stateWriteInProgress: false
  property string queuedStateRaw: ""
  property string writingStateRaw: ""
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
    if (initialized || !storageReady || !tipsReady) return
    initialized = true
    stateReadProcess.running = true
  }

  function persist() {
    if (stateStorageBlocked) return false
    var serialized = JSON.stringify(studyState, null, 2) + "\n"
    if (!TipModel.stateSizeAllowed(TipModel.utf8ByteLength(serialized))) {
      blockStateStorage("serialized state exceeds the size limit")
      return false
    }
    queuedStateRaw = serialized
    beginStateWrite()
    return true
  }

  function beginStateWrite() {
    if (stateStorageBlocked || stateWriteInProgress || queuedStateRaw === "") return
    stateWriteInProgress = true
    writingStateRaw = queuedStateRaw
    queuedStateRaw = ""
    stateFile.setText(writingStateRaw)
  }

  function finishStateWrite() {
    writingStateRaw = ""
    stateWriteInProgress = false
    beginStateWrite()
  }

  function applyPrimaryState(raw) {
    nowMs = Date.now()
    studyState = TipModel.parseState(raw, tips, nowMs)
    var serialized = JSON.stringify(studyState, null, 2) + "\n"
    if (String(raw) !== serialized) persist()
    Qt.callLater(checkQueue)
  }

  function startNewCourse() {
    nowMs = Date.now()
    studyState = TipModel.defaultState()
    persist()
    Qt.callLater(checkQueue)
  }

  function restartCourse() {
    if (!initialized || stateStorageBlocked || removalBusy) return false
    nowMs = Date.now()
    var next = TipModel.defaultState()
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
    removalError = ""
    stateDeleteProcess.running = true
    return true
  }

  function blockStateStorage(message) {
    stateStorageBlocked = true
    queuedStateRaw = ""
    console.error("OmaTips: " + message + "; state storage is disabled")
  }

  function stateWithNotification(notificationDate) {
    return {
      schemaVersion: studyState.schemaVersion,
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
    if (!currentTip || stateStorageBlocked) return false
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

  FileView {
    id: stateFile
    path: root.statePath
    atomicWrites: true
    preload: false
    blockAllReads: true
    printErrors: false
    onSaved: root.finishStateWrite()
    onSaveFailed: root.blockStateStorage("could not write state")
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
      if (!root.initialized) return
      if (exitCode === 10) {
        console.warn("OmaTips: no stored state; starting a new course")
        root.startNewCourse()
      } else if (exitCode !== 0) {
        root.blockStateStorage("state is not a readable regular file")
      } else if (stateReadOutput.data === null || stateReadOutput.data === undefined) {
        root.blockStateStorage("state produced no readable data")
      } else if (!TipModel.stateSizeAllowed(stateReadOutput.data.byteLength)) {
        root.blockStateStorage("state exceeds the size limit")
      } else if (TipModel.validStoredState(stateReadOutput.text)) {
        root.applyPrimaryState(stateReadOutput.text)
      } else {
        root.blockStateStorage("state is invalid")
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
    command: ["/usr/bin/rm", "-f", "--", root.statePath]
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

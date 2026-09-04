import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "TipModel.js" as TipModel
import "PanelNavigation.js" as Navigation

Panel {
  id: root
  moduleName: "yarikov.omatips"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  property string confirmationAction: ""
  property string confirmationOrigin: ""
  property string cursorTarget: ""
  property bool answerRevealed: false
  property string preferredRating: "again"

  readonly property var studyItem: service ? service.currentItem : null
  readonly property var tip: studyItem ? studyItem.tip : null
  readonly property string currentTipId: tip && tip.id ? String(tip.id) : ""
  readonly property var barIdentity: hostWidget || root
  readonly property bool courseCompleted: !!(service && service.courseCompleted)
  readonly property bool confirmationOpen: confirmationAction !== ""
  readonly property var navigationRows: confirmationOpen
    ? [["cancel", "confirm"]]
    : courseCompleted
      ? [["restart", "uninstall"]]
      : !answerRevealed
        ? [["showAnswer"]]
        : actionLabel() !== ""
          ? [["action"], ["again", "hard", "good", "easy"]]
          : [["again", "hard", "good", "easy"]]

  function openLatest() {
    if (!service || (!service.hasStudyItem && !service.courseCompleted)) return
    if (service.hasStudyItem) service.recordPanelOpened(currentTipId)
    if (!Navigation.contains(navigationRows, cursorTarget)) resetCursor()
    controller.show()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function open() { openLatest() }
  function close() {
    controller.hide()
  }
  function grade(rating) {
    if (!service || !answerRevealed) return
    preferredRating = rating
    // Clear the answer before reviewCurrent() changes currentItem. The service
    // updates its state synchronously, so otherwise the next tip can be
    // rendered for one frame with the previous tip's answer visible.
    answerRevealed = false
    cursorTarget = "showAnswer"
    service.reviewCurrent(rating)
  }
  function ratingIntervalLabel(rating) {
    var card = studyItem ? studyItem.card : null
    var now = service ? service.nowMs : 0
    return TipModel.ratingIntervalLabel(card, rating, now)
  }
  function runAction() {
    if (service && tip && tip.action) service.runAction(tip)
  }
  function actionLabel() {
    var currentTip = tip
    var action = currentTip ? currentTip.action : null
    return action && action.label ? String(action.label) : ""
  }
  function requestConfirmation(action) {
    confirmationOrigin = cursorTarget
    confirmationAction = action
    cursorTarget = "confirm"
    persistPanelSession()
  }
  function cancelConfirmation() {
    confirmationAction = ""
    cursorTarget = Navigation.contains(navigationRows, confirmationOrigin)
      ? confirmationOrigin : Navigation.first(navigationRows)
    confirmationOrigin = ""
    persistPanelSession()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  function confirmSelection() {
    var action = confirmationAction
    confirmationAction = ""
    confirmationOrigin = ""
    if (!service) return
    if (action === "restart") {
      preferredRating = "again"
      answerRevealed = false
      service.restartCourse()
    }
    else if (action === "uninstall") service.removePlugin()
  }
  function revealAnswer() {
    if (!service || !service.hasStudyItem || answerRevealed) return
    answerRevealed = true
    cursorTarget = Navigation.contains(navigationRows, preferredRating)
      ? preferredRating : "again"
    persistPanelSession()
  }
  function persistPanelSession() {
    if (service && (currentTipId !== "" || courseCompleted))
      service.savePanelSession(currentTipId, answerRevealed, cursorTarget,
        preferredRating, confirmationAction, confirmationOrigin)
  }
  function restorePanelSession() {
    var session = service ? service.panelSession : null
    if (session && session.tipId === currentTipId
        && (currentTipId !== "" || courseCompleted)) {
      answerRevealed = session.answerRevealed === true
      preferredRating = ["again", "hard", "good", "easy"].indexOf(
        session.preferredRating) !== -1 ? session.preferredRating : "again"
      confirmationAction = session.confirmationAction || ""
      confirmationOrigin = session.confirmationOrigin || ""
      cursorTarget = Navigation.contains(navigationRows, session.cursorTarget)
        ? session.cursorTarget : Navigation.first(navigationRows)
    } else {
      answerRevealed = false
      preferredRating = "again"
      confirmationAction = ""
      confirmationOrigin = ""
      resetCursor()
    }
  }
  function schedulePanelSessionRestore() {
    restoreSessionTimer.restart()
  }

  Timer {
    id: restoreSessionTimer
    interval: 0
    onTriggered: root.restorePanelSession()
  }
  function resetCursor() {
    cursorTarget = Navigation.first(navigationRows)
  }
  function setCursor(target) {
    if (Navigation.contains(navigationRows, target)) {
      cursorTarget = target
      persistPanelSession()
    }
  }
  function moveCursor(dx, dy) {
    cursorTarget = Navigation.move(navigationRows, cursorTarget, dx, dy)
    persistPanelSession()
  }
  function activateCurrent() {
    if (!Navigation.contains(navigationRows, cursorTarget)) resetCursor()
    if (cursorTarget === "showAnswer") revealAnswer()
    else if (cursorTarget === "action") runAction()
    else if (["again", "hard", "good", "easy"].indexOf(cursorTarget) !== -1)
      grade(cursorTarget)
    else if (cursorTarget === "restart") requestConfirmation("restart")
    else if (cursorTarget === "uninstall") requestConfirmation("uninstall")
    else if (cursorTarget === "cancel") cancelConfirmation()
    else if (cursorTarget === "confirm") confirmSelection()
  }

  onCurrentTipIdChanged: {
    confirmationAction = ""
    confirmationOrigin = ""
    restoreSessionTimer.restart()
  }

  Connections {
    target: root.service
    function onCurrentItemChanged() {
      Qt.callLater(function() {
        if (root.opened && (!root.service
            || (!root.service.hasStudyItem && !root.service.courseCompleted))) root.close()
      })
    }
    function onCourseCompletedChanged() {
      root.answerRevealed = false
      root.schedulePanelSessionRestore()
    }
    function onPanelSessionChanged() { root.schedulePanelSessionRestore() }
  }

  KeyboardPanel {
    id: popup
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(520))
    contentHeight: popup.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onActivateRequested: root.activateCurrent()
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onCloseRequested: {
        if (root.confirmationOpen) root.cancelConfirmation()
        else root.close()
      }
      onTabRequested: function(direction) {
        if (root.confirmationOpen) root.moveCursor(direction, 0)
        else if (root.bar && typeof root.bar.switchPanelFrom === "function")
          root.bar.switchPanelFrom(root.barIdentity, direction)
      }
      onTextKey: function(text) {
        if (root.confirmationOpen || root.courseCompleted || !root.answerRevealed) return
        if (text === "1") root.grade("again")
        else if (text === "2") root.grade("hard")
        else if (text === "3") root.grade("good")
        else if (text === "4") root.grade("easy")
      }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: content
          width: parent.width
          spacing: Style.space(12)

          Column {
            id: studyContent
            width: parent.width
            spacing: Style.space(12)
            visible: !root.courseCompleted

            Row {
              width: parent.width
              spacing: Style.space(8)

              Text {
                text: root.studyItem && root.studyItem.isNew ? "NEW OMARCHY TIP" : "REVIEW"
                color: Color.accent
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - progress.implicitWidth - parent.spacing * 2); height: 1 }

              Text {
                id: progress
                text: root.service ? TipModel.studyPositionLabel(root.studyItem, root.service.totalTips) : ""
                color: root.bar ? root.bar.foreground : Color.foreground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
              }
            }

            Text {
              width: parent.width
              text: root.tip ? String(root.tip.category).toUpperCase() : "LOADING"
              color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.35)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
            }

            Text {
              width: parent.width
              text: root.tip ? root.tip.title : "Preparing your study queue…"
              color: root.bar ? root.bar.foreground : Color.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
              wrapMode: Text.WordWrap
            }

            Button {
              width: parent.width
              visible: !root.answerRevealed
              text: "Show answer"
              foreground: root.bar ? root.bar.foreground : Color.foreground
              accent: Color.accent
              bordered: true
              hasCursor: root.cursorTarget === "showAnswer"
              onHovered: function(isHovered) {
                if (isHovered) root.setCursor("showAnswer")
              }
              onClicked: root.revealAnswer()
            }

            BorderSurface {
              width: parent.width
              implicitHeight: exampleText.implicitHeight + Style.space(20)
              visible: root.answerRevealed
                && !!(root.tip && (root.tip.shortcut || root.tip.command))
              color: Style.normalFillFor(root.bar ? root.bar.foreground : Color.foreground, Color.accent)
              borderSpec: Border.controlSpec("normal", root.bar ? root.bar.foreground : Color.foreground, Color.accent)
              radius: Style.cornerRadius

              Text {
                id: exampleText
                anchors.fill: parent
                anchors.margins: Style.space(10)
                text: root.tip ? (root.tip.shortcut || root.tip.command || "") : ""
                color: root.bar ? root.bar.foreground : Color.foreground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                wrapMode: Text.WrapAnywhere
                verticalAlignment: Text.AlignVCenter
              }
            }

            Button {
              visible: root.answerRevealed && root.actionLabel() !== ""
              text: root.actionLabel()
              foreground: root.bar ? root.bar.foreground : Color.foreground
              bordered: true
              hasCursor: root.cursorTarget === "action"
              enabled: !!root.service && !root.service.actionBusy
              onHovered: function(isHovered) {
                if (isHovered) root.setCursor("action")
              }
              onClicked: root.runAction()
            }

            Text {
              width: parent.width
              visible: root.answerRevealed
              text: "How well did you remember this?"
              color: root.bar ? root.bar.foreground : Color.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              horizontalAlignment: Text.AlignHCenter
            }

            Row {
              width: parent.width
              spacing: Style.space(6)
              visible: root.answerRevealed

              Repeater {
                model: [
                  { rating: "again", label: "1 · Again" },
                  { rating: "hard", label: "2 · Hard" },
                  { rating: "good", label: "3 · Good" },
                  { rating: "easy", label: "4 · Easy" }
                ]

                Button {
                  required property var modelData
                  width: (studyContent.width - 3 * Style.space(6)) / 4
                  text: modelData.label + "  " + root.ratingIntervalLabel(modelData.rating)
                  foreground: root.bar ? root.bar.foreground : Color.foreground
                  accent: Color.accent
                  bordered: true
                  hasCursor: root.cursorTarget === modelData.rating
                  onHovered: function(isHovered) {
                    if (isHovered) root.setCursor(modelData.rating)
                  }
                  onClicked: root.grade(modelData.rating)
                }
              }
            }

            Text {
              width: parent.width
              text: root.answerRevealed ? "Press 1–4 to rate · Esc to close" : "Esc to close"
              color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.55)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(14)
            visible: root.courseCompleted

            Text {
              width: parent.width
              text: "COURSE COMPLETE"
              color: Color.accent
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
              horizontalAlignment: Text.AlignHCenter
            }

            Text {
              width: parent.width
              text: "Congratulations, Omarchy Hero!"
              color: root.bar ? root.bar.foreground : Color.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              text: "You’ve mastered all 229 OmaTips lessons. You’re now an Omarchy Hotkey Master."
              color: root.bar ? root.bar.foreground : Color.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.bodySmall
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              Button {
                width: (parent.width - parent.spacing) / 2
                text: "Start again"
                foreground: root.bar ? root.bar.foreground : Color.foreground
                accent: Color.accent
                bordered: true
                hasCursor: root.cursorTarget === "restart"
                enabled: !!root.service && !root.service.removalBusy
                onHovered: function(isHovered) {
                  if (isHovered) root.setCursor("restart")
                }
                onClicked: root.requestConfirmation("restart")
              }

              Button {
                width: (parent.width - parent.spacing) / 2
                text: "Uninstall OmaTips"
                foreground: root.bar ? root.bar.foreground : Color.foreground
                bordered: true
                hasCursor: root.cursorTarget === "uninstall"
                enabled: !!root.service && !root.service.removalBusy
                onHovered: function(isHovered) {
                  if (isHovered) root.setCursor("uninstall")
                }
                onClicked: root.requestConfirmation("uninstall")
              }
            }

            Text {
              width: parent.width
              visible: !!(root.service && root.service.removalError)
              text: root.service ? root.service.removalError : ""
              color: Color.urgent
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              text: "Esc to close"
              color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.55)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
            }
          }
        }
      }

      Item {
        id: confirmDialog
        anchors.fill: parent
        visible: root.confirmationOpen
        z: 10

        Rectangle {
          anchors.fill: parent
          color: Util.alpha(Color.background, 0.7)

          MouseArea {
            anchors.fill: parent
            onClicked: root.cancelConfirmation()
          }

          BorderSurface {
            id: confirmCard
            width: Math.min(parent.width - Style.space(32), Style.space(370))
            height: contentTopInset + contentBottomInset + confirmMessage.implicitHeight
              + Style.space(20) + confirmButtons.implicitHeight
            anchors.centerIn: parent
            color: Color.background
            borderSpec: Border.flat(Color.accent, Style.normalBorderWidth)
            padding: Style.space(18)
            radius: Style.cornerRadius

            MouseArea { anchors.fill: parent; onClicked: {} }

            Item {
              anchors.fill: parent
              anchors.topMargin: confirmCard.contentTopInset
              anchors.rightMargin: confirmCard.contentRightInset
              anchors.bottomMargin: confirmCard.contentBottomInset
              anchors.leftMargin: confirmCard.contentLeftInset

              Text {
                id: confirmMessage
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                text: root.confirmationAction === "restart"
                  ? "Start the course again? Your current progress will be erased."
                  : "Uninstall OmaTips and delete all course progress?"
                color: root.bar ? root.bar.foreground : Color.foreground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.title
                wrapMode: Text.WordWrap
              }

              Row {
                id: confirmButtons
                width: parent.width
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                spacing: Style.space(10)
                readonly property real buttonHeight: Math.max(cancelButton.implicitHeight, actionButton.implicitHeight)

                Button {
                  id: cancelButton
                  width: (confirmButtons.width - confirmButtons.spacing) / 2
                  height: confirmButtons.buttonHeight
                  text: "Cancel"
                  foreground: root.bar ? root.bar.foreground : Color.foreground
                  bordered: true
                  hasCursor: root.cursorTarget === "cancel"
                  onHovered: function(isHovered) {
                    if (isHovered) root.setCursor("cancel")
                  }
                  onClicked: root.cancelConfirmation()
                }

                Button {
                  id: actionButton
                  width: (confirmButtons.width - confirmButtons.spacing) / 2
                  height: confirmButtons.buttonHeight
                  text: root.confirmationAction === "restart" ? "Start again" : "Uninstall"
                  foreground: root.bar ? root.bar.foreground : Color.foreground
                  accent: Color.urgent
                  bordered: true
                  hasCursor: root.cursorTarget === "confirm"
                  onHovered: function(isHovered) {
                    if (isHovered) root.setCursor("confirm")
                  }
                  onClicked: root.confirmSelection()
                }
              }
            }
          }
        }
      }
    }
  }
}

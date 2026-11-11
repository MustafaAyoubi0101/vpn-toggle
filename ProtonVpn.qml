import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "mustafa.protonvpn"

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // -1 follows real state; 0/1 is optimistic while connect/disconnect catches up.
  property int _desired: -1
  property bool connected: false
  property string statusLabel: ""
  property string statusText: ""
  property string lastError: ""
  property bool _notifyOnStatus: false

  readonly property bool active: _desired === -1 ? connected : (_desired === 1)
  readonly property bool busy: statusProc.running || actionProc.running
  readonly property int refreshIntervalSec: {
    var n = parseInt(String(setting("refreshIntervalSec", 5)), 10)
    if (!isFinite(n)) n = 5
    return Math.max(2, Math.min(120, n))
  }
  readonly property string tooltip: {
    if (actionProc.running) {
      return active
        ? strings.t("tooltip.connecting")
        : strings.t("tooltip.disconnecting")
    }
    if (busy) return strings.t("tooltip.busy")
    return active ? strings.t("tooltip.connected") : strings.t("tooltip.disconnected")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function showStatus() {
    root._notifyOnStatus = true
    root.refresh()
  }

  function notifyStatus() {
    var body = root.statusText !== ""
      ? root.statusText
      : (root.lastError !== "" ? root.lastError : strings.t("status.disconnected"))
    Quickshell.execDetached(["notify-send", "-a", "Proton VPN", "Proton VPN", body])
  }

  function toggle() {
    if (actionProc.running) return
    var next = !root.active
    root._desired = next ? 1 : 0
    root.lastError = ""
    actionProc.command = ["protonvpn", next ? "connect" : "disconnect"]
    actionProc.running = true
  }

  function parseStatus(text) {
    var out = String(text || "").replace(/\s+$/, "")
    root.statusText = out
    var isConnected = /Status:\s*Connected/i.test(out)
    root.connected = isConnected
    if (isConnected) {
      var match = out.match(/Server:\s*(.+)/i)
      root.statusLabel = match ? String(match[1]).trim() : "Connected"
    } else {
      root.statusLabel = ""
    }
    if (root._desired !== -1 && ((root._desired === 1) === isConnected))
      root._desired = -1
  }

  Process {
    id: statusProc
    command: ["protonvpn", "status"]
    stdout: StdioCollector {
      id: statusStdout
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: statusStderr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      var stdout = String(statusStdout.text || "")
      var stderr = String(statusStderr.text || "")
      if (exitCode === 0 || /Status:/i.test(stdout) || stdout.trim() !== "") {
        root.parseStatus(stdout)
        root.lastError = ""
      } else if (stderr !== "") {
        root.statusText = ""
        root.lastError = stderr.replace(/\s+$/, "")
      }
      if (root._notifyOnStatus) {
        root._notifyOnStatus = false
        root.notifyStatus()
      }
    }
  }

  Process {
    id: actionProc
    command: ["protonvpn", "status"]
    stdout: StdioCollector {
      id: actionStdout
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: actionStderr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      var stdout = String(actionStdout.text || "")
      var stderr = String(actionStderr.text || "")
      if (exitCode !== 0 && stderr !== "")
        root.lastError = stderr.split("\n")[0]
      // Reconcile with real state after connect/disconnect finishes.
      root.refresh()
      Qt.callLater(function() {
        statusFollowup.restart()
      })
    }
  }

  // Connect can take a few seconds after the CLI returns; poll briefly.
  Timer {
    id: statusFollowup
    interval: 1500
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // nf-md-shield-key / VPN-like shield
    text: root.active ? "󰒃" : "󰦝"
    active: root.active
    useActiveColor: false
    dimmed: !root.active
    tooltipText: root.tooltip
    onPressed: function(button) {
      if (button === Qt.RightButton) {
        root.toggle()
        return
      }
      if (button === Qt.LeftButton)
        root.showStatus()
    }
  }
}

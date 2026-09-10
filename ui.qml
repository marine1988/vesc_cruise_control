import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Vedder.vesc.commands 1.0
import Vedder.vesc.utility 1.0

Item {
    id: root
    anchors.fill: parent

    property Commands mCommands: VescIf.commands()
    property bool loaded: false
    property bool saving: false
    property string cruiseState: "off"
    property string lastCancel: "none"
    property bool legalLocked: false

    function sendCode(str) {
        mCommands.sendCustomAppData(str + "\0")
    }

    function getSettings() {
        loaded = false
        sendCode("(send-settings)")
    }

    function setReal(field, value, decimals) {
        var number = Number(value)
        if (Number.isFinite(number)) {
            field.text = number.toFixed(decimals)
        }
    }

    function readReal(field, decimals) {
        var number = Number(field.text)
        if (!Number.isFinite(number)) {
            number = 0
        }
        return number.toFixed(decimals)
    }

    // cruise <enabled> <hold> <deadband> <min km/h> <max km/h> <legal> <debug>
    function applySettingsLine(line) {
        var parts = line.split(" ")

        if (parts[0] !== "cruise" || parts.length < 8) {
            return
        }

        cruiseEnabled.checked = parts[1] === "true"
        setReal(cruiseHoldSec, parts[2], 1)
        setReal(cruiseDeadband, parts[3], 2)
        setReal(cruiseMinSpeed, parts[4], 1)
        setReal(cruiseMaxSpeed, parts[5], 1)
        legalEnabled.checked = parts[6] === "true"
        debugEnabled.checked = parts[7] === "true"
        loaded = true
    }

    // state <off|engaging|on|cancelling> <last cancel> <locked|unlocked>
    function applyStateLine(line) {
        var parts = line.split(" ")

        if (parts[0] !== "state" || parts.length < 4) {
            return
        }

        cruiseState = parts[1]
        lastCancel = parts[2]
        legalLocked = parts[3] === "locked"
    }

    function stateText() {
        if (cruiseState === "engaging") {
            return "Engaging..."
        }
        if (cruiseState === "on") {
            return "Cruise on"
        }
        if (cruiseState === "cancelling") {
            return "Cancelling..."
        }
        return "Cruise off"
    }

    function stateColor() {
        if (cruiseState === "on") {
            return "#2ecc71"
        }
        if (cruiseState === "engaging") {
            return "#f1c40f"
        }
        if (cruiseState === "cancelling") {
            return "#e67e22"
        }
        return "#95a5a6"
    }

    function saveSettings() {
        if (!loaded || saving) {
            return
        }

        saving = true
        sendCode("(save-cruise-settings "
            + (cruiseEnabled.checked ? "true" : "false")
            + " " + readReal(cruiseHoldSec, 1)
            + " " + readReal(cruiseDeadband, 2)
            + " " + readReal(cruiseMinSpeed, 1)
            + " " + readReal(cruiseMaxSpeed, 1)
            + " " + (legalEnabled.checked ? "true" : "false")
            + " " + (debugEnabled.checked ? "true" : "false")
            + ")")
    }

    Component.onCompleted: {
        getSettings()
    }

    // Lisp may still be starting up, keep asking until it answers
    Timer {
        interval: 2000
        repeat: true
        running: !loaded && !saving
        onTriggered: sendCode("(send-settings)")
    }

    // The script never pushes anything on its own, it answers. A reply leaves by the port that
    // asked, and on a scooter with a display on the UART the port that spoke last is the display,
    // so a script that talked unprompted is what made the display show wrong speed and temperature.
    // Asking for the state keeps that traffic between VESC Tool and the script.
    Timer {
        interval: 1000
        repeat: true
        running: loaded && !saving
        onTriggered: sendCode("(send-state)")
    }

    Connections {
        target: mCommands

        function onCustomAppDataReceived(data) {
            var message = data.toString().trim()

            // The lisp tags every reply, so the UI never mistakes a load or a reset for a save.
            // "saved" comes after the cruise/state lines the lisp already sent, so there is
            // nothing to ask for here; asking again is what made the status repeat forever.
            if (message === "saved") {
                saving = false
                VescIf.emitStatusMessage("Settings saved.", true)
            } else if (message === "loaded") {
                saving = false
            } else if (message === "reset") {
                saving = false
                VescIf.emitStatusMessage("Defaults restored.", true)
            } else if (message === "err") {
                saving = false
                VescIf.emitStatusMessage("Saving failed.", false)
            } else if (message === "state-poll") {
                // The reply to the periodic state request: the state line next to it is the point
            } else if (message.indexOf("state ") === 0) {
                applyStateLine(message)
            } else {
                applySettingsLine(message)
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 6
        spacing: 4

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth
            clip: true

            ColumnLayout {
                width: parent.width
                spacing: 2

                Label {
                    Layout.topMargin: 2
                    Layout.bottomMargin: 2
                    font.bold: true
                    font.pixelSize: 14
                    text: "Cruise Control"
                }

                CheckBox {
                    id: cruiseEnabled
                    text: "Enable Cruise Control"
                }

                Label {
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.bottomMargin: 4
                    wrapMode: Text.WordWrap
                    opacity: 0.65
                    font.pixelSize: 11
                    text: "Hold the throttle steady for the hold time and cruise engages. A brake, or a pull past the position it holds, cancels it."
                }

                Label {
                    Layout.topMargin: 6
                    Layout.bottomMargin: 2
                    font.bold: true
                    text: "Speed"
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    rowSpacing: 2
                    columnSpacing: 8

                    Label { text: "Min Speed (km/h)" }
                    TextField {
                        id: cruiseMinSpeed
                        Layout.fillWidth: true
                        validator: DoubleValidator { bottom: 0.0; top: 150.0; decimals: 1 }
                    }
                    Label {
                        Layout.columnSpan: 2
                        Layout.fillWidth: true
                        Layout.leftMargin: 12
                        Layout.bottomMargin: 4
                        wrapMode: Text.WordWrap
                        opacity: 0.65
                        font.pixelSize: 11
                        text: "Cruise does not engage below this speed"
                    }

                    Label { text: "Max Speed (km/h)" }
                    TextField {
                        id: cruiseMaxSpeed
                        Layout.fillWidth: true
                        validator: DoubleValidator { bottom: 0.0; top: 150.0; decimals: 1 }
                    }
                    Label {
                        Layout.columnSpan: 2
                        Layout.fillWidth: true
                        Layout.leftMargin: 12
                        Layout.bottomMargin: 4
                        wrapMode: Text.WordWrap
                        opacity: 0.65
                        font.pixelSize: 11
                        text: "Cruise does not engage above this speed"
                    }
                }

                Label {
                    Layout.topMargin: 6
                    Layout.bottomMargin: 2
                    font.bold: true
                    text: "Sensitivity"
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    rowSpacing: 2
                    columnSpacing: 8

                    Label { text: "Hold Time (s)" }
                    TextField {
                        id: cruiseHoldSec
                        Layout.fillWidth: true
                        validator: DoubleValidator { bottom: 0.0; top: 30.0; decimals: 1 }
                    }
                    Label {
                        Layout.columnSpan: 2
                        Layout.fillWidth: true
                        Layout.leftMargin: 12
                        Layout.bottomMargin: 4
                        wrapMode: Text.WordWrap
                        opacity: 0.65
                        font.pixelSize: 11
                        text: "How long the throttle has to stay steady before cruise engages"
                    }

                    Label { text: "Deadband (V)" }
                    TextField {
                        id: cruiseDeadband
                        Layout.fillWidth: true
                        validator: DoubleValidator { bottom: 0.01; top: 1.0; decimals: 2 }
                    }
                    Label {
                        Layout.columnSpan: 2
                        Layout.fillWidth: true
                        Layout.leftMargin: 12
                        Layout.bottomMargin: 4
                        wrapMode: Text.WordWrap
                        opacity: 0.65
                        font.pixelSize: 11
                        text: "How far the throttle may drift and still count as steady"
                    }
                    Label {
                        Layout.columnSpan: 2
                        Layout.fillWidth: true
                        Layout.leftMargin: 12
                        Layout.bottomMargin: 4
                        wrapMode: Text.WordWrap
                        font.pixelSize: 11
                        color: "#e74c3c"
                        visible: Number(cruiseDeadband.text) > 0.5
                        text: "Warning: high deadband, cruise may engage with the throttle moving."
                    }
                }

                Label {
                    Layout.topMargin: 6
                    Layout.bottomMargin: 2
                    font.bold: true
                    text: "Legal Lock"
                }

                CheckBox {
                    id: legalEnabled
                    text: "Enable Legal Lock"
                }

                Label {
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.bottomMargin: 2
                    wrapMode: Text.WordWrap
                    opacity: 0.65
                    font.pixelSize: 11
                    text: "Limits the motor to 25 km/h / 500 W. Stopped: tap the brake 5 times within 5 seconds. Same gesture to unlock."
                }

                Label {
                    Layout.leftMargin: 12
                    font.pixelSize: 11
                    color: legalLocked ? "#e67e22" : "#95a5a6"
                    text: legalLocked ? "Locked: 25 km/h / 500 W" : "Unlocked"
                }

                Label {
                    Layout.topMargin: 6
                    Layout.bottomMargin: 2
                    font.bold: true
                    text: "Debug"
                }

                CheckBox {
                    id: debugEnabled
                    text: "Debug mode (verbose logs)"
                }

                Label {
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.bottomMargin: 4
                    wrapMode: Text.WordWrap
                    opacity: 0.65
                    font.pixelSize: 11
                    text: "Prints a detailed line on the VESC Tool terminal once per second. For diagnosis."
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true

            Button {
                Layout.fillWidth: true
                text: "Load"
                enabled: !saving
                onClicked: getSettings()
            }

            Button {
                Layout.fillWidth: true
                text: "Save"
                enabled: loaded && !saving
                onClicked: saveSettings()
            }

            Button {
                Layout.fillWidth: true
                text: "Reset"
                enabled: loaded && !saving
                onClicked: sendCode("(restore-settings-ui)")
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Label { text: "State:" }
            Label {
                text: "●"
                color: root.stateColor()
            }
            Label { text: root.stateText() }
            Item { Layout.fillWidth: true }
        }

        Label {
            Layout.fillWidth: true
            opacity: 0.6
            font.pixelSize: 11
            elide: Text.ElideRight
            text: "Last cancel: " + root.lastCancel
        }
    }

    BusyIndicator {
        anchors.centerIn: parent
        running: !loaded || saving
        visible: running
    }
}

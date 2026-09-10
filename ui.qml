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
            return "A ligar..."
        }
        if (cruiseState === "on") {
            return "Cruise ligado"
        }
        if (cruiseState === "cancelling") {
            return "A desligar..."
        }
        return "Cruise desligado"
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

    Connections {
        target: mCommands

        function onCustomAppDataReceived(data) {
            var message = data.toString().trim()

            // The lisp tags every reply, so the UI never mistakes a load or a reset for a save.
            // "saved" comes after the cruise/state lines the lisp already sent, so there is
            // nothing to ask for here; asking again is what made the status repeat forever.
            if (message === "saved") {
                saving = false
                VescIf.emitStatusMessage("Definições guardadas.", true)
            } else if (message === "loaded") {
                saving = false
            } else if (message === "reset") {
                saving = false
                VescIf.emitStatusMessage("Defaults repostos.", true)
            } else if (message === "err") {
                saving = false
                VescIf.emitStatusMessage("Erro ao guardar.", false)
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
                    text: "Activar Cruise Control"
                }

                Label {
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.bottomMargin: 4
                    wrapMode: Text.WordWrap
                    opacity: 0.65
                    font.pixelSize: 11
                    text: "Mantém o acelerador parado durante o tempo definido para o cruise ligar. Travar ou mexer o acelerador desliga."
                }

                Label {
                    Layout.topMargin: 6
                    Layout.bottomMargin: 2
                    font.bold: true
                    text: "Velocidade"
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    rowSpacing: 2
                    columnSpacing: 8

                    Label { text: "Min para ligar (km/h)" }
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
                        text: "Cruise não liga abaixo desta velocidade"
                    }

                    Label { text: "Max para ligar (km/h)" }
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
                        text: "Cruise não liga acima desta velocidade"
                    }
                }

                Label {
                    Layout.topMargin: 6
                    Layout.bottomMargin: 2
                    font.bold: true
                    text: "Sensibilidade"
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    rowSpacing: 2
                    columnSpacing: 8

                    Label { text: "Tempo de espera (s)" }
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
                        text: "Quantos segundos tens de manter o acelerador parado para o cruise ligar"
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
                        text: "Quanto o acelerador pode oscilar e ainda contar como parado"
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
                        text: "Aviso: deadband alto, o cruise pode ligar com o acelerador a mexer."
                    }
                }

                Label {
                    Layout.topMargin: 6
                    Layout.bottomMargin: 2
                    font.bold: true
                    text: "Legal lock"
                }

                CheckBox {
                    id: legalEnabled
                    text: "Activar Legal Lock"
                }

                Label {
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.bottomMargin: 2
                    wrapMode: Text.WordWrap
                    opacity: 0.65
                    font.pixelSize: 11
                    text: "Limita o motor a 25 km/h. Para activar: travão + 2 blips no acelerador. Mesmo gesto para desligar."
                }

                Label {
                    Layout.leftMargin: 12
                    font.pixelSize: 11
                    color: legalLocked ? "#e67e22" : "#95a5a6"
                    text: legalLocked ? "Bloqueio activo: 25 km/h / 500 W" : "Bloqueio inactivo"
                }

                Label {
                    Layout.topMargin: 6
                    Layout.bottomMargin: 2
                    font.bold: true
                    text: "Debug"
                }

                CheckBox {
                    id: debugEnabled
                    text: "Modo debug (logs verbosos)"
                }

                Label {
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.bottomMargin: 4
                    wrapMode: Text.WordWrap
                    opacity: 0.65
                    font.pixelSize: 11
                    text: "Imprime estado detalhado no terminal do VESC Tool a cada 1s. Para diagnóstico."
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true

            Button {
                Layout.fillWidth: true
                text: "Carregar"
                enabled: !saving
                onClicked: getSettings()
            }

            Button {
                Layout.fillWidth: true
                text: "Guardar"
                enabled: loaded && !saving
                onClicked: saveSettings()
            }

            Button {
                Layout.fillWidth: true
                text: "Repor"
                enabled: loaded && !saving
                onClicked: sendCode("(restore-settings-ui)")
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Label { text: "Estado:" }
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
            text: "Último cancelamento: " + root.lastCancel
        }
    }

    BusyIndicator {
        anchors.centerIn: parent
        running: !loaded || saving
        visible: running
    }
}

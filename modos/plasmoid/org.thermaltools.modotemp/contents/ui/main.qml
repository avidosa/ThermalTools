import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root
    property string modo: "equilibrado"
    property string temp: "--"
    readonly property var colores: ({
        "chill": "#3fb950", "equilibrado": "#4d8fef", "juego": "#f04a4a", "nolimit": "#b48cf2"
    })

    preferredRepresentation: compactRepresentation
    toolTipMainText: "Modo " + modo
    toolTipSubText: "CPU a " + temp + " °C · escribe  modo  en una terminal para cambiarlo"

    P5Support.DataSource {
        engine: "executable"
        connectedSources: ["\"$HOME/.local/bin/modo\" --barra"]
        interval: 2000
        onNewData: (source, data) => {
            const p = data["stdout"].trim().split(" ")
            if (p.length === 2) { root.modo = p[0]; root.temp = p[1] }
        }
    }

    // Pastilla del color del modo con la temperatura en blanco. (El texto no
    // puede ir en color: Panel Colorizer repinta todo el texto del panel.)
    compactRepresentation: Item {
        Layout.minimumWidth: pastilla.width + 4
        Layout.preferredWidth: pastilla.width + 4
        Rectangle {
            id: pastilla
            anchors.centerIn: parent
            width: txt.implicitWidth + 12; height: 18; radius: 9
            color: root.colores[root.modo] || "gray"
            Text {
                id: txt
                anchors.centerIn: parent
                text: root.temp + "°"
                color: "white"
                font.bold: true
                font.pixelSize: 12
            }
        }
    }
    fullRepresentation: PlasmaComponents.Label { text: "Modo " + root.modo + " · CPU " + root.temp + " °C" }
}

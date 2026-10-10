import QtQuick

Singleton {
    id: clock
    enum Precision { Seconds, Minutes }
    property int precision: SystemClock.Minutes
    property date date: new Date()
    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            const now = new Date()
            if (clock.precision === SystemClock.Seconds
                || now.getMinutes() !== clock.date.getMinutes()
                || now.getDate() !== clock.date.getDate())
                clock.date = now
        }
    }
}

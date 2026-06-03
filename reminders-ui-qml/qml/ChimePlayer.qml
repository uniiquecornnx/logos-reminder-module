/* Optional chime — kept in its own QML file so that a failure to import
 * QtMultimedia (e.g. blocked by basecamp's sandbox) only fails the
 * Loader in Main.qml, not the entire UI. The Loader's Error status is
 * handled gracefully on the consumer side. */
import QtQuick
import QtMultimedia

SoundEffect {
    source: "sounds/pop.wav"
    loops: 0
    volume: 0.6   /* a notification, not a fire alarm */
}

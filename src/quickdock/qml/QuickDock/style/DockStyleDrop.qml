import QtQuick

// Drop previews while dragging: the zone indicator, the slim marker shown
// between tabs, and the drop compass.
QtObject {
    property int indicatorBorderWidth: 2
    property int indicatorRadius: 3
    property int tabMarkerWidth: 4
    property int tabMarkerMargin: 3
    property int compassSize: 104
    property int compassCellSize: 30
}

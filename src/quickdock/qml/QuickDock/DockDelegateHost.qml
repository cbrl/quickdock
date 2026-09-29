pragma ComponentBehavior: Bound

import QtQuick

// Hosts one instance of a delegate and hands it the values of `context`.
// A delegate root declares the values it uses as `required property`, as a
// ListView delegate does with model roles: they are set when it is created
// and stay bound to the context afterwards. Values it does not declare are
// not passed. The instance fills the host, and the host takes its implicit
// size from the instance.
Item {
    id: root

    property Component delegate: null
    property QtObject context: null
    readonly property Item item: _item

    property Item _item: null
    property bool _completed: false

    implicitWidth: _item ? _item.implicitWidth : 0
    implicitHeight: _item ? _item.implicitHeight : 0

    onDelegateChanged: _rebuild()
    onContextChanged: _rebuild()
    Component.onCompleted: {
        _completed = true
        _rebuild()
    }

    // A Repeater over an object model is used because it sets a delegate's
    // required properties from the object's properties by name. Its model is
    // cleared before its delegate changes: swapping the delegate of a live
    // object-model Repeater crashes Qt 6.11. Nothing is built before the host
    // is complete, as its initial delegate and context would otherwise each
    // build an instance that is thrown away.
    function _rebuild() {
        if (!_completed)
            return
        repeater.model = []
        repeater.delegate = delegate
        repeater.model = delegate && context ? [context] : []
    }

    // A property of the instance, or `fallback` when it has none.
    function value(name, fallback) {
        return _item && name in _item ? _item[name] : fallback
    }

    function _same(first, second) {
        return first === second
            || (first !== null && second !== null && first !== undefined && second !== undefined
                && typeof first === typeof second && String(first) === String(second))
    }

    // The Repeater set the delegate's required properties from the context,
    // so a property that holds the context's value now is one of them. One
    // that does not is an unrelated built-in of the same name (Text.style,
    // say) and is left alone.
    function _adopt(instance) {
        instance.anchors.fill = root
        for (const key in context) {
            const current = context[key]
            if (key !== "objectName" && typeof current !== "function" && key in instance
                    && _same(instance[key], current))
                instance[key] = Qt.binding(() => root.context[key])
        }
        _item = instance
    }

    Repeater {
        id: repeater
        onItemAdded: (index, instance) => root._adopt(instance)
        onItemRemoved: (index, instance) => {
            if (root._item === instance)
                root._item = null
        }
    }
}

//
//  Reorder.swift
//  MusicPlayer
//
//  Pointer-based vertical drag-to-reorder list. The row content sits on
//  the leading side; the list renders a trailing drag handle whose gesture
//  drives reordering — so row taps stay independent of the drag.
//

import SwiftUI

struct ReorderableList<RowContent: View>: View {
    let ids: [String]
    var rowHeight: CGFloat = 64
    var handleColor: Color = .secondary
    var draggingBackground: Color = .clear
    var onReorder: ([String]) -> Void
    @ViewBuilder var rowContent: (String) -> RowContent

    @State private var order: [String] = []
    @State private var dragId: String?
    @State private var dy: CGFloat = 0
    @State private var startOrder: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            ForEach(order, id: \.self) { id in
                let dragging = id == dragId
                HStack(spacing: 0) {
                    rowContent(id)
                    Spacer(minLength: 0)
                    AuraIcon(name: "drag", size: 22, weight: .semibold, color: handleColor)
                        .padding(8)
                        .contentShape(Rectangle())
                        .gesture(dragGesture(for: id))
                }
                .frame(height: rowHeight)
                .background(dragging ? draggingBackground : .clear,
                            in: RoundedRectangle(cornerRadius: dragging ? 14 : 0, style: .continuous))
                .shadow(color: .black.opacity(dragging ? 0.45 : 0), radius: dragging ? 15 : 0, y: dragging ? 14 : 0)
                .scaleEffect(dragging ? 1.02 : 1)
                .offset(y: dragging ? dy : 0)
                .zIndex(dragging ? 5 : 0)
                .animation(dragging ? nil : .easeInOut(duration: 0.18), value: order)
            }
        }
        .onAppear { order = ids }
        .onChange(of: ids) { _, new in if dragId == nil { order = new } }
    }

    private func dragGesture(for id: String) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if dragId != id { dragId = id; startOrder = order }
                guard let base = startOrder.firstIndex(of: id) else { return }
                let steps = Int((g.translation.height / rowHeight).rounded())
                let to = max(0, min(startOrder.count - 1, base + steps))
                var next = startOrder
                next.remove(at: base)
                next.insert(id, at: to)
                order = next
                dy = g.translation.height - CGFloat(to - base) * rowHeight
            }
            .onEnded { _ in
                dragId = nil
                dy = 0
                onReorder(order)
            }
    }
}

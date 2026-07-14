import SwiftUI

/// A layout that arranges subviews in horizontal rows, wrapping to the next row
/// when the proposed width is exceeded. Useful for tag clouds and chip rows.
public struct HFlow: Layout {
  public var alignment: VerticalAlignment
  public var horizontalSpacing: CGFloat
  public var verticalSpacing: CGFloat

  public init(
    alignment: VerticalAlignment = .center,
    horizontalSpacing: CGFloat = 8,
    verticalSpacing: CGFloat = 8
  ) {
    self.alignment = alignment
    self.horizontalSpacing = horizontalSpacing
    self.verticalSpacing = verticalSpacing
  }

  public func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout Void
  ) -> CGSize {
    let maxWidth = proposal.width ?? .infinity
    let rows = computeRows(maxWidth: maxWidth, subviews: subviews)

    let width = rows.map(\.width).max() ?? 0
    let height = rows.reduce(into: 0) { total, row in
      total += row.height
    } + verticalSpacing * CGFloat(max(0, rows.count - 1))

    return CGSize(width: min(width, maxWidth), height: height)
  }

  public func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout Void
  ) {
    let rows = computeRows(maxWidth: bounds.width, subviews: subviews)
    var y = bounds.minY

    for row in rows {
      var x = bounds.minX

      for index in row.indices {
        let size = subviews[index].sizeThatFits(.unspecified)
        let dy: CGFloat

        switch alignment {
        case .top: dy = 0
        case .bottom: dy = row.height - size.height
        default: dy = (row.height - size.height) / 2
        }

        subviews[index].place(
          at: CGPoint(x: x, y: y + dy),
          anchor: .topLeading,
          proposal: ProposedViewSize(size)
        )
        x += size.width + horizontalSpacing
      }

      y += row.height + verticalSpacing
    }
  }

  private struct Row {
    var indices: [Int] = []
    var width: CGFloat = 0
    var height: CGFloat = 0
  }

  private func computeRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
    var rows: [Row] = []
    var current = Row()

    for index in subviews.indices {
      let size = subviews[index].sizeThatFits(.unspecified)
      let needsSpacing = !current.indices.isEmpty
      let addedWidth = size.width + (needsSpacing ? horizontalSpacing : 0)

      if needsSpacing, current.width + addedWidth > maxWidth {
        rows.append(current)
        current = Row()
      }

      let leadingSpacing = current.indices.isEmpty ? 0 : horizontalSpacing
      current.indices.append(index)
      current.width += size.width + leadingSpacing
      current.height = max(current.height, size.height)
    }

    if !current.indices.isEmpty {
      rows.append(current)
    }

    return rows
  }
}

#Preview {
  HFlow {
    ForEach(["SwiftUI", "TCA", "SQLiteData", "Tuist", "Sharing", "GRDB"], id: \.self) { tag in
      Text(tag)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.blue.opacity(0.15), in: .capsule)
    }
  }
  .padding()
}

import SwiftUI

/// A segment of a `ScrollableTabRow`. Conform your enum to this protocol so the
/// row can render a title and track selection by `Identifiable` id.
public protocol TabSegment: Identifiable, Hashable {
  var title: String { get }
}

/// A horizontal, scrollable tab/segment row that auto-scrolls to keep the active
/// segment visible. Each segment is sized to a fraction of the available width
/// and shows an accent underline when selected.
public struct ScrollableTabRow<Segment: TabSegment>: View {
  @Binding private var selection: Segment
  private let segments: [Segment]

  @State private var totalHeight: CGFloat = 0

  public init(
    selection: Binding<Segment>,
    segments: [Segment]
  ) {
    self._selection = selection
    self.segments = segments
  }

  public var body: some View {
    GeometryReader { geo in
      ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 0) {
            ForEach(segments, content: view(for:))
              .frame(
                minWidth: segments.isEmpty
                  ? nil
                  : geo.size.width / CGFloat(segments.count)
              )
          }
          .background {
            Color.clear
              .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) {
                totalHeight = $0
              }
          }
        }
        .onAppear {
          scrollTo(selection, using: proxy)
        }
        .onChange(of: selection) { _, new in
          scrollTo(new, using: proxy)
        }
      }
      .background(alignment: .bottom) {
        Divider()
      }
    }
    .frame(height: totalHeight)
  }

  private func view(for segment: Segment) -> some View {
    Button {
      selection = segment
    } label: {
      Text(segment.title)
        .font(.subheadline)
        .foregroundStyle(segment.id == selection.id ? Color.primary : Color.secondary)
        .fontWeight(.medium)
        .padding(.vertical, 12)
        .padding(.horizontal, 26)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) {
          Rectangle()
            .fill(Color.accentColor)
            .frame(height: 2)
            .opacity(segment.id == selection.id ? 1 : 0)
        }
        .contentShape(Rectangle())
    }
    .id(segment)
    .accessibilityAddTraits(segment.id == selection.id ? .isSelected : [])
    .buttonStyle(.plain)
  }

  private func scrollTo(
    _ segment: Segment,
    using scrollViewProxy: ScrollViewProxy
  ) {
    withAnimation {
      scrollViewProxy.scrollTo(segment, anchor: .leading)
    }
  }
}

// MARK: - Previews
#Preview {
  enum MockSegment: String, TabSegment, CaseIterable {
    case first
    case second
    case third
    case fourth
    case fifth
    case sixth
    case seventh
    case eighth
    case ninth
    case tenth
    case eleventh
    case twelfth

    var title: String {
      rawValue.localizedCapitalized
    }

    var id: String {
      rawValue
    }
  }

  struct DemoView: View {
    @State private var selection: MockSegment = .first
    let segments: [MockSegment]

    var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        ScrollableTabRow(
          selection: $selection,
          segments: segments
        )

        HStack {
          Button("First") { selection = .first }
          Button("Sixth") { selection = .sixth }
          Button("Last") { selection = segments.last ?? .first }
        }
        .buttonStyle(.bordered)

        Text("Selected: \(selection.title)")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      .padding()
    }
  }

  return VStack(spacing: 24) {
    DemoView(segments: Array(MockSegment.allCases.prefix(4)))
      .border(.quaternary)
    DemoView(segments: MockSegment.allCases)
      .border(.quaternary)
  }
  .padding()
}

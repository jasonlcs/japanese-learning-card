import JapaneseLearningCardCore
import SwiftUI

struct RubyText: View {
    var segments: [RubySegment]
    var fallback: String
    var baseFont: Font
    var rubyFont: Font
    var baseColor: Color = .primary
    var rubyColor: Color = .secondary
    var horizontalSpacing: CGFloat = 2
    var verticalSpacing: CGFloat = 4

    var body: some View {
        if RubySupport.isUsable(segments, for: fallback) {
            RubyFlowLayout(horizontalSpacing: horizontalSpacing, verticalSpacing: verticalSpacing) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    RubySegmentView(
                        segment: segment,
                        baseFont: baseFont,
                        rubyFont: rubyFont,
                        baseColor: baseColor,
                        rubyColor: rubyColor
                    )
                }
            }
            .textSelection(.enabled)
        } else {
            Text(fallback)
                .font(baseFont)
                .foregroundStyle(baseColor)
                .textSelection(.enabled)
        }
    }
}

private struct RubySegmentView: View {
    var segment: RubySegment
    var baseFont: Font
    var rubyFont: Font
    var baseColor: Color
    var rubyColor: Color

    var body: some View {
        VStack(spacing: 1) {
            // 注意: 不要加 minimumScaleFactor —— 它和 fixedSize + 自訂 Layout
            // 反覆量測的組合會讓 SwiftUI 佈局無法收斂 (主執行緒卡死)。
            Text(segment.ruby.isEmpty ? " " : segment.ruby)
                .font(rubyFont)
                .foregroundStyle(rubyColor)
                .opacity(segment.ruby.isEmpty ? 0 : 1)
                .lineLimit(1)
            Text(segment.base)
                .font(baseFont)
                .foregroundStyle(baseColor)
                .lineLimit(1)
        }
        .fixedSize()
    }
}

private struct RubyFlowLayout: Layout {
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat

    /// 每個 subview 的固定尺寸只量一次。SwiftUI 一次佈局會用多種 proposal
    /// 反覆呼叫 sizeThatFits / placeSubviews；沒有快取時每輪都重新量測
    /// 全部 Text (CoreText)，段落一多主執行緒會被拖死。
    struct Cache {
        var sizes: [CGSize]
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(sizes: subviews.map { $0.sizeThatFits(.unspecified) })
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache.sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        rows(for: subviews, maxWidth: proposal.width ?? .infinity, sizes: cache.sizes).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let result = rows(for: subviews, maxWidth: bounds.width, sizes: cache.sizes)
        var y = bounds.minY
        for row in result.rows {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    private func rows(for subviews: Subviews, maxWidth: CGFloat, sizes: [CGSize]) -> RubyFlowRows {
        var rows: [RubyFlowRow] = []
        var currentItems: [RubyFlowItem] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0
        let constrainedWidth = maxWidth.isFinite ? maxWidth : .greatestFiniteMagnitude

        for index in subviews.indices {
            let size = index < sizes.count ? sizes[index] : subviews[index].sizeThatFits(.unspecified)
            let nextWidth = currentItems.isEmpty ? size.width : currentWidth + horizontalSpacing + size.width
            if !currentItems.isEmpty && nextWidth > constrainedWidth {
                rows.append(RubyFlowRow(items: currentItems, width: currentWidth, height: currentHeight))
                currentItems = [RubyFlowItem(index: index, size: size)]
                currentWidth = size.width
                currentHeight = size.height
            } else {
                currentItems.append(RubyFlowItem(index: index, size: size))
                currentWidth = nextWidth
                currentHeight = max(currentHeight, size.height)
            }
        }

        if !currentItems.isEmpty {
            rows.append(RubyFlowRow(items: currentItems, width: currentWidth, height: currentHeight))
        }

        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(CGFloat(0)) { total, row in
            total + row.height
        } + CGFloat(max(0, rows.count - 1)) * verticalSpacing
        return RubyFlowRows(rows: rows, size: CGSize(width: width, height: height))
    }
}

private struct RubyFlowRows {
    var rows: [RubyFlowRow]
    var size: CGSize
}

private struct RubyFlowRow {
    var items: [RubyFlowItem]
    var width: CGFloat
    var height: CGFloat
}

private struct RubyFlowItem {
    var index: Int
    var size: CGSize
}

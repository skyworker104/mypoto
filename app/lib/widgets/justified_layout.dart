/// Google Photos-style justified layout algorithm.
///
/// Groups photos into rows where each row fills the container width,
/// with row height determined by combined aspect ratios.
/// Ported from server/web/js/views/timeline.js.

/// A photo with aspect ratio info for layout computation.
class JustifiedItem<T> {
  final T data;
  final double aspect; // width / height

  const JustifiedItem({required this.data, required this.aspect});
}

/// A computed row of photos with a shared height.
class JustifiedRow<T> {
  final List<JustifiedItem<T>> items;
  final double height;

  const JustifiedRow({required this.items, required this.height});
}

/// Compute justified layout rows from a list of items.
///
/// Each row fills [containerWidth] by adjusting the shared row height
/// based on the sum of aspect ratios. When the computed row height
/// drops to or below [targetRowHeight], the row is finalized.
List<JustifiedRow<T>> computeJustifiedLayout<T>({
  required List<JustifiedItem<T>> items,
  required double containerWidth,
  required double targetRowHeight,
  double gap = 2.0,
}) {
  if (items.isEmpty || containerWidth <= 0) return [];

  final rows = <JustifiedRow<T>>[];
  var currentRow = <JustifiedItem<T>>[];
  var currentAspectSum = 0.0;

  for (final item in items) {
    currentRow.add(item);
    currentAspectSum += item.aspect;

    final usableWidth = containerWidth - gap * (currentRow.length - 1);
    final rowHeight = usableWidth / currentAspectSum;

    if (rowHeight <= targetRowHeight) {
      rows.add(JustifiedRow(items: List.of(currentRow), height: rowHeight));
      currentRow = [];
      currentAspectSum = 0.0;
    }
  }

  // Last incomplete row: cap at targetRowHeight to avoid stretching
  if (currentRow.isNotEmpty) {
    final usableWidth = containerWidth - gap * (currentRow.length - 1);
    final rowHeight =
        (usableWidth / currentAspectSum).clamp(0.0, targetRowHeight);
    rows.add(JustifiedRow(items: currentRow, height: rowHeight));
  }

  return rows;
}

/// Responsive target row height based on screen width.
double getTargetRowHeight(double screenWidth) {
  if (screenWidth >= 1200) return 240;
  if (screenWidth >= 768) return 200;
  return 160;
}

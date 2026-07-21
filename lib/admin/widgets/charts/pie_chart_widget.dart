import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class PieChartWidget extends StatelessWidget {
  final Map<String, int> data;
  final String title;
  final double height;

  const PieChartWidget({
    super.key,
    required this.data,
    required this.title,
    this.height = 200,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'No data available',
            style: TextStyle(color: Colors.white.withOpacity(0.5)),
          ),
        ),
      );
    }

    final total = data.values.fold<int>(0, (sum, value) => sum + value);
    final colors = [
      const Color(0xFFEF4444),
      const Color(0xFF3B82F6),
      const Color(0xFF10B981),
      const Color(0xFFF59E0B),
      const Color(0xFF8B5CF6),
      const Color(0xFFEC4899),
      const Color(0xFF14B8A6),
      const Color(0xFFF97316),
    ];

    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: PieChart(
                    PieChartData(
                      sections: _buildSections(colors, total),
                      centerSpaceRadius: 30,
                      sectionsSpace: 2,
                      borderData: FlBorderData(show: false),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Legend
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: data.entries.take(5).toList().asMap().entries.map((entry) {
                    final idx = entry.key;
                    final item = entry.value;
                    final percentage = total > 0 ? (item.value / total * 100).toStringAsFixed(1) : '0';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: colors[idx % colors.length],
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${item.key} ($percentage%)',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<PieChartSectionData> _buildSections(List<Color> colors, int total) {
    final sections = <PieChartSectionData>[];
    var index = 0;

    for (final entry in data.entries) {
      final percentage = total > 0 ? (entry.value / total * 100) : 0.0;
      sections.add(
        PieChartSectionData(
          color: colors[index % colors.length],
          value: percentage,
          title: '${percentage.toStringAsFixed(0)}%',
          radius: 35,
          titleStyle: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
      index++;
    }

    return sections;
  }
}

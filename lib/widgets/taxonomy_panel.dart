import 'package:aura/theme/aura_theme.dart';
import 'package:flutter/material.dart';

import '../models/detailed_aura_score.dart';

class AuraTaxonomyPanel extends StatelessWidget {
  final DetailedAuraScore details;

  const AuraTaxonomyPanel({super.key, required this.details});

  Widget _buildDimensionRow(String label, DimensionScore dim, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              Text(
                '${dim.score} / 100',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: dim.score / 100.0,
              backgroundColor: Colors.white24,
              color: color,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  dim.primaryTraits.isNotEmpty
                      ? dim.primaryTraits.join(' • ')
                      : '',
                  style: const TextStyle(
                    color: AuraColors.muted,
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                'Confidence: ${dim.confidence.toStringAsFixed(2)}',
                style: const TextStyle(color: AuraColors.muted, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'AURA PROFILE',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const Divider(color: Colors.white24, thickness: 1),

          if (details.bodyShape.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Body Shape',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        details.bodyShape,
                        style: const TextStyle(
                          color: AuraColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          if (details.face != null)
            _buildDimensionRow(
              'Face Geometry',
              details.face!,
              AuraColors.primary,
            ),
          if (details.eyes != null)
            _buildDimensionRow(
              'Eye Presentation',
              details.eyes!,
              Colors.lightBlueAccent,
            ),
          if (details.expression != null)
            _buildDimensionRow(
              'Expression',
              details.expression!,
              AuraColors.yellow,
            ),

          _buildDimensionRow(
            'Body Silhouette',
            details.body,
            AuraColors.primary,
          ),
          _buildDimensionRow('Posture', details.posture, Colors.indigoAccent),
          _buildDimensionRow('Pose Dynamics', details.pose, Colors.tealAccent),
          _buildDimensionRow('Style (Slay)', details.style, AuraColors.yellow),
          _buildDimensionRow('Image Quality', details.image, Colors.cyanAccent),
          _buildDimensionRow('Presence', details.presence, Colors.yellowAccent),
          _buildDimensionRow('Content', details.content, AuraColors.error),

          if (details.rawMetrics.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(color: Colors.white24, thickness: 1),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                'BIOMETRICS BREAKDOWN',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
            ...details.rawMetrics.entries.map(
              (e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      e.key,
                      style: const TextStyle(
                        color: AuraColors.muted,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      e.value.toStringAsFixed(3),
                      style: const TextStyle(
                        color: AuraColors.green,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

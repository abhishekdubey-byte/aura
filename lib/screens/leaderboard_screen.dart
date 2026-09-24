import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _leaderboardData = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchLeaderboard();
  }

  Future<void> _fetchLeaderboard() async {
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('leaderboard')
          .select()
          .order('score', ascending: false)
          .limit(100);

      if (mounted) {
        setState(() {
          List<Map<String, dynamic>> deduped = [];
          Set<String> seenUsernames = {};
          for (var row in response) {
            String uname = row['username'] as String;
            if (!seenUsernames.contains(uname)) {
              seenUsernames.add(uname);
              deduped.add(row);
            }
          }
          _leaderboardData = deduped;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load leaderboard: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'GLOBAL LEADERBOARD',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            fontSize: 20, // Smaller font size to fit on screen
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.deepPurpleAccent));
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 60),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _errorMessage = null;
                  });
                  _fetchLeaderboard();
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent),
                child: const Text('Retry', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    if (_leaderboardData.isEmpty) {
      return const Center(
        child: Text(
          'No scores yet. Be the first!',
          style: TextStyle(color: Colors.white54, fontSize: 18),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      itemCount: _leaderboardData.length,
      itemBuilder: (context, index) {
        final entry = _leaderboardData[index];
        final isTop3 = index < 3;
        
        Color rankColor;
        Color bgColor = Colors.grey[900]!;
        IconData? medalIcon;
        
        if (index == 0) {
          rankColor = Colors.amber; // Gold
          bgColor = Colors.amber.withValues(alpha: 0.15);
          medalIcon = Icons.military_tech;
        } else if (index == 1) {
          rankColor = Colors.grey[300]!; // Silver
          bgColor = Colors.grey.withValues(alpha: 0.15);
          medalIcon = Icons.military_tech;
        } else if (index == 2) {
          rankColor = Colors.orange[300]!; // Bronze
          bgColor = Colors.orange.withValues(alpha: 0.15);
          medalIcon = Icons.military_tech;
        } else {
          rankColor = Colors.white54;
        }

        return Card(
          color: bgColor,
          elevation: isTop3 ? 8 : 2,
          margin: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: isTop3 ? BorderSide(color: rankColor.withValues(alpha: 0.5), width: 1.5) : BorderSide.none,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Row(
              children: [
                SizedBox(
                  width: 45,
                  child: Row(
                    children: [
                      if (isTop3 && medalIcon != null)
                        Icon(medalIcon, color: rankColor, size: 20),
                      if (!isTop3)
                        const SizedBox(width: 4),
                      Text(
                        '#${index + 1}',
                        style: TextStyle(
                          color: rankColor,
                          fontSize: isTop3 ? 20 : 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    entry['username'] ?? 'Anonymous',
                    style: TextStyle(
                      color: isTop3 ? Colors.white : Colors.white70,
                      fontSize: isTop3 ? 20 : 16,
                      fontWeight: isTop3 ? FontWeight.bold : FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isTop3 ? rankColor.withValues(alpha: 0.2) : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${entry['score']}',
                    style: TextStyle(
                      color: isTop3 ? rankColor : Colors.pinkAccent,
                      fontSize: isTop3 ? 24 : 18,
                      fontWeight: FontWeight.bold,
                      shadows: isTop3 ? [Shadow(blurRadius: 10, color: rankColor.withValues(alpha: 0.5))] : [],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

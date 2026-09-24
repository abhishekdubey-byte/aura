import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _watermarkEnabled = false;
  final TextEditingController _watermarkController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _watermarkEnabled = prefs.getBool('watermark_enabled') ?? false;
      _watermarkController.text = prefs.getString('custom_watermark') ?? 'Calculate your Aura: Download AURA App';
    });
  }

  Future<void> _saveWatermarkToggle(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('watermark_enabled', value);
    setState(() {
      _watermarkEnabled = value;
    });
  }

  Future<void> _saveCustomWatermark(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_watermark', value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          SwitchListTile(
            title: const Text('Enable Watermark', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Add watermark to captured photos', style: TextStyle(color: Colors.grey)),
            value: _watermarkEnabled,
            onChanged: _saveWatermarkToggle,
            activeColor: Colors.orangeAccent,
          ),
          if (_watermarkEnabled) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _watermarkController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Custom Watermark Text',
                      labelStyle: TextStyle(color: Colors.grey),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.orangeAccent),
                      ),
                    ),
                    onChanged: _saveCustomWatermark,
                    onSubmitted: (value) {
                      FocusScope.of(context).unfocus();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    _saveCustomWatermark(_watermarkController.text);
                    FocusScope.of(context).unfocus();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Watermark text saved!'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orangeAccent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Save', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _watermarkController.dispose();
    super.dispose();
  }
}

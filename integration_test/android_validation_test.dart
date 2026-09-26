import 'layout_export_test.dart' as exports;
import 'runtime_smoke_test.dart' as runtime;

/// Full native validation in one installation, including the layout matrix.
void main() {
  runtime.main();
  exports.main();
}

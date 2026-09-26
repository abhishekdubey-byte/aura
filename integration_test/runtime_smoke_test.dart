import 'aura_workflow_test.dart' as aura;
import 'layout_camera_test.dart' as layout;
import 'video_workflow_test.dart' as video;

/// One installed build exercises mode navigation, ML, full-resolution export,
/// layout photo/video capture, camera flip, rotation and draft recovery.
void main() {
  aura.main();
  layout.main();
  video.main();
}

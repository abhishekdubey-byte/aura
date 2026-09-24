import 'package:image/image.dart' as img;

void main() {
  var image = img.Image(width: 100, height: 100);
  img.drawString(image, 'Test', font: img.arial24, x: 0, y: 0, color: img.ColorRgb8(255, 255, 255));
  print('Success');
}

import 'dart:io';
import 'dart:typed_data';

void main() {
  final f = File('assets/app_icon.png').readAsBytesSync();
  print('Size: ${f.length}');
  print('Header: ${f.sublist(0, 8)}');
  print('Is PNG: ${f[0] == 0x89 && f[1] == 0x50 && f[2] == 0x4E && f[3] == 0x47}');
}

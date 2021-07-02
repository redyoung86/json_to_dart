import 'dart:io';
import "package:path/path.dart" show dirname, join, normalize;
import '../lib/json_to_dart.dart';

String _scriptPath() {
  var script = Platform.script.toString();
  if (script.startsWith("file://")) {
    script = script.substring(7);
  } else {
    final idx = script.indexOf("file:/");
    script = script.substring(idx + 5);
  }
  return script;
}

main() {
  // 空值安全
  bool nullSafety = true;

  // 实体名称
  final classGenerator = new ModelGenerator('Sample');
  final currentDirectory = dirname(_scriptPath());
  // json文件
  final filePath = normalize(join(currentDirectory, 'sample.json'));
  final jsonRawData = new File(filePath).readAsStringSync();

  // 字段swagger注释
  final fileNotePath = normalize(join(currentDirectory, 'demo_swagger.json'));
  final jsonNoteData = new File(fileNotePath).readAsStringSync();

  // 解析 swagger properties 节点中的字段说明
  Map<String, String> properties = classGenerator.parseToProperties(jsonNoteData);

  DartCode dartCode = classGenerator.generateDartClasses(jsonRawData, properties);
  print(dartCode.code);
}

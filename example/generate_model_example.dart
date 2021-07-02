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
  //1、更新 data_json.json 为json格式的数据
  //2、更新 data_swagger_properties.json 为 swagger中properties节点（definitions->实体-> properties）的json格式数据
  //3、更新实体名称
  String modelName = "Sample";

  // 空值安全
  bool nullSafety = true;

  // 实体名称
  final classGenerator = new ModelGenerator(modelName);
  final currentDirectory = dirname(_scriptPath());
  // json文件,ref = demo_sample.json
  final filePath = normalize(join(currentDirectory, 'data_json.json'));
  final jsonRawData = new File(filePath).readAsStringSync();

  // 字段swagger注释,swagger properties 节点, ref = demo_swagger_sample.json
  final fileNotePath = normalize(join(currentDirectory, 'data_swagger_properties.json'));
  final jsonNoteData = new File(fileNotePath).readAsStringSync();

  // 解析 swagger properties 节点中的字段说明
  Map<String, String> properties = classGenerator.parseToProperties(jsonNoteData);

  DartCode dartCode = classGenerator.generateDartClasses(jsonRawData, properties, nullSafety);

  // 输出代码
  print(dartCode.code);
}

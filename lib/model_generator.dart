import 'dart:collection';

import 'package:dart_style/dart_style.dart';
import 'package:json_ast/json_ast.dart' show parse, Settings, Node;
import 'package:json_to_dart/helpers.dart';
import 'package:json_to_dart/syntax.dart';
import 'dart:convert' as Convert;

class DartCode extends WithWarning<String> {
  DartCode(String result, List<Warning> warnings) : super(result, warnings);

  String get code => this.result;
}

/// A Hint is a user type correction.
class Hint {
  final String path;
  final String type;

  Hint(this.path, this.type);
}

class ModelGenerator {
  final String _rootClassName;
  final bool _privateFields;
  List<ClassDefinition> allClasses = <ClassDefinition>[];
  final Map<String, String> sameClassMapping = new HashMap<String, String>();
  List<Hint> hints;

  ModelGenerator(this._rootClassName, [this._privateFields = false, hints]) {
    if (hints != null) {
      this.hints = hints;
    } else {
      this.hints = <Hint>[];
    }
  }

  Hint _hintForPath(String path) {
    return this.hints.firstWhere((h) => h.path == path, orElse: () => null);
  }

  List<Warning> _generateClassDefinition(String className, dynamic jsonRawDynamicData, String path, Node astNode, [Map<String, String> properties]) {
    List<Warning> warnings = <Warning>[];
    if (jsonRawDynamicData is List) {
      // if first element is an array, start in the first element.
      final node = navigateNode(astNode, '0');
      _generateClassDefinition(className, jsonRawDynamicData[0], path, node);
    } else {
      final Map<dynamic, dynamic> jsonRawData = jsonRawDynamicData;
      final keys = jsonRawData.keys;

      Map<String, String> _properties = {};
      if (properties != null) {
        _properties = properties;
      }

      ClassDefinition classDefinition = new ClassDefinition(className, _privateFields);
      keys.forEach((key) {
        TypeDefinition typeDef;
        final hint = _hintForPath('$path/$key');
        final node = navigateNode(astNode, key);
        if (hint != null) {
          typeDef = new TypeDefinition(hint.type, astNode: node);
        } else {
          typeDef = new TypeDefinition.fromDynamic(jsonRawData[key], node);
        }
        if (typeDef.name == 'Class') {
          typeDef.name = camelCase(key);
        }
        if (typeDef.name == 'List' && typeDef.subtype == 'Null') {
          warnings.add(newEmptyListWarn('$path/$key'));
        }
        if (typeDef.subtype != null && typeDef.subtype == 'Class') {
          typeDef.subtype = camelCase(key);
        }
        if (typeDef.isAmbiguous) {
          warnings.add(newAmbiguousListWarn('$path/$key'));
        }

        // 设置描述
        if (_properties.containsKey(key)) {
          typeDef.description = _properties[key];
        }

        classDefinition.addField(key, typeDef);
      });

      final similarClass = allClasses.firstWhere((cd) => cd == classDefinition, orElse: () => null);
      if (similarClass != null) {
        final similarClassName = similarClass.name;
        final currentClassName = classDefinition.name;
        sameClassMapping[currentClassName] = similarClassName;
      } else {
        allClasses.add(classDefinition);
      }
      final dependencies = classDefinition.dependencies;
      dependencies.forEach((dependency) {
        List<Warning> warns;
        if (dependency.typeDef.name == 'List') {
          // only generate dependency class if the array is not empty
          if (jsonRawData[dependency.name].length > 0) {
            // when list has ambiguous values, take the first one, otherwise merge all objects
            // into a single one
            dynamic toAnalyze;
            if (!dependency.typeDef.isAmbiguous) {
              WithWarning<Map> mergeWithWarning = mergeObjectList(jsonRawData[dependency.name], '$path/${dependency.name}');
              toAnalyze = mergeWithWarning.result;
              warnings.addAll(mergeWithWarning.warnings);
            } else {
              toAnalyze = jsonRawData[dependency.name][0];
            }
            final node = navigateNode(astNode, dependency.name);
            warns = _generateClassDefinition(dependency.className, toAnalyze, '$path/${dependency.name}', node, properties);
          }
        } else {
          final node = navigateNode(astNode, dependency.name);
          warns = _generateClassDefinition(dependency.className, jsonRawData[dependency.name], '$path/${dependency.name}', node, properties);
        }
        if (warns != null) {
          warnings.addAll(warns);
        }
      });
    }
    return warnings;
  }

  /// 解析 swagger properties 节点中的字段说明
  Map<String, String> parseToProperties(String jsonNoteData) {
    Map<String, String> _map = {};
    if (jsonNoteData == null || jsonNoteData.isEmpty) {
      return _map;
    }

    final Map<String, dynamic> jsonData = Convert.json.decode(jsonNoteData);

    jsonData.forEach((key, value) {
      Map<String, dynamic> data = value;

      // print("key=" + key);
      // print(data["description"]);

      _map[key] = data["description"];
    });

    //print(jsonData);
    // print(_map);
    return _map;
  }

  /// generateUnsafeDart will generate all classes and append one after another
  /// in a single string. The [rawJson] param is assumed to be a properly
  /// formatted JSON string. The dart code is not validated so invalid dart code
  /// might be returned
  DartCode generateUnsafeDart(String rawJson, [Map<String, String> properties]) {
    final jsonRawData = decodeJSON(rawJson);
    final astNode = parse(rawJson, Settings());
    List<Warning> warnings = _generateClassDefinition(_rootClassName, jsonRawData, "", astNode, properties);
    // after generating all classes, replace the omited similar classes.
    allClasses.forEach((c) {
      final fieldsKeys = c.fields.keys;
      fieldsKeys.forEach((f) {
        final typeForField = c.fields[f];
        if (sameClassMapping.containsKey(typeForField.name)) {
          c.fields[f].name = sameClassMapping[typeForField.name];
        }
      });
    });
    return new DartCode(allClasses.map((c) => c.toString()).join('\n'), warnings);
  }

  /// generateDartClasses will generate all classes and append one after another
  /// in a single string. The [rawJson] param is assumed to be a properly
  /// formatted JSON string. If the generated dart is invalid it will throw an error.
  DartCode generateDartClasses(String rawJson, [Map<String, String> properties]) {
    final unsafeDartCode = generateUnsafeDart(rawJson, properties);
    final formatter = new DartFormatter();
    return new DartCode(formatter.format(unsafeDartCode.code), unsafeDartCode.warnings);
  }
}

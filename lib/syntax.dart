import 'package:json_ast/json_ast.dart' show Node;
import 'package:json_to_dart/helpers.dart';

const String emptyListWarn = "list is empty";
const String ambiguousListWarn = "list is ambiguous";
const String ambiguousTypeWarn = "type is ambiguous";

class Warning {
  final String warning;
  final String path;

  Warning(this.warning, this.path);
}

Warning newEmptyListWarn(String path) {
  return new Warning(emptyListWarn, path);
}

Warning newAmbiguousListWarn(String path) {
  return new Warning(ambiguousListWarn, path);
}

Warning newAmbiguousType(String path) {
  return new Warning(ambiguousTypeWarn, path);
}

class WithWarning<T> {
  final T result;
  final List<Warning> warnings;

  WithWarning(this.result, this.warnings);
}

class TypeDefinition {
  String name;
  String subtype;
  bool isAmbiguous = false;
  bool _isPrimitive = false;

  // 属性描述
  String description;

  factory TypeDefinition.fromDynamic(dynamic obj, Node astNode) {
    bool isAmbiguous = false;
    final type = getTypeName(obj);
    if (type == 'List') {
      List<dynamic> list = obj;
      String elemType;
      if (list.length > 0) {
        elemType = getTypeName(list[0]);
        for (dynamic listVal in list) {
          if (elemType != getTypeName(listVal)) {
            isAmbiguous = true;
            break;
          }
        }
      } else {
        // when array is empty insert Null just to warn the user
        elemType = "Null";
      }
      return new TypeDefinition(type, astNode: astNode, subtype: elemType, isAmbiguous: isAmbiguous);
    }
    return new TypeDefinition(type, astNode: astNode, isAmbiguous: isAmbiguous);
  }

  TypeDefinition(this.name, {this.subtype, this.isAmbiguous, Node astNode, this.description}) {
    if (subtype == null) {
      _isPrimitive = isPrimitiveType(this.name);
      if (this.name == 'int' && isASTLiteralDouble(astNode)) {
        this.name = 'double';
      }
    } else {
      _isPrimitive = isPrimitiveType('$name<$subtype>');
    }
    if (isAmbiguous == null) {
      isAmbiguous = false;
    }
  }

  bool operator ==(other) {
    if (other is TypeDefinition) {
      TypeDefinition otherTypeDef = other;
      return this.name == otherTypeDef.name && this.subtype == otherTypeDef.subtype && this.isAmbiguous == otherTypeDef.isAmbiguous && this._isPrimitive == otherTypeDef._isPrimitive;
    }
    return false;
  }

  bool get isPrimitive => _isPrimitive;

  bool get isPrimitiveList => _isPrimitive && name == 'List';

  String _buildParseClass(String expression, [bool nullSafety = false]) {
    final properType = subtype != null ? subtype : name;
    if (nullSafety) {
      return ' $properType.fromJson($expression)';
    }
    return 'new $properType.fromJson($expression)';
  }

  String _buildToJsonClass(String expression, [bool nullSafety = false]) {
    if (nullSafety) {
      return '$expression?.toJson()';
    }
    return '$expression.toJson()';
  }

  String jsonParseExpression(String key, bool privateField, [bool nullSafety = false]) {
    final jsonKey = "json['$key']";
    final fieldKey = fixFieldName(key, typeDef: this, privateField: privateField);
    if (isPrimitive) {
      if (name == "List") {
        return "$fieldKey = json['$key'].cast<$subtype>();";
      }
      return "$fieldKey = json['$key'];";
    } else if (name == "List" && subtype == "DateTime") {
      return "$fieldKey = json['$key'].map((v) => DateTime.tryParse(v));";
    } else if (name == "DateTime") {
      return "$fieldKey = DateTime.tryParse(json['$key']);";
    } else if (name == 'List') {
      // list of class
      if (nullSafety) {
        return "if (json['$key'] != null) {\n\t\t\t$fieldKey = <$subtype>[];\n\t\t\tjson['$key'].forEach((v) { $fieldKey?.add( $subtype.fromJson(v)); });\n\t\t}";
      }
      return "if (json['$key'] != null) {\n\t\t\t$fieldKey = new List<$subtype>();\n\t\t\tjson['$key'].forEach((v) { $fieldKey.add(new $subtype.fromJson(v)); });\n\t\t}";
    } else {
      // class
      return "$fieldKey = json['$key'] != null ? ${_buildParseClass(jsonKey, nullSafety)} : null;";
    }
  }

  String toJsonExpression(String key, bool privateField, [bool nullSafety = false]) {
    final fieldKey = fixFieldName(key, typeDef: this, privateField: privateField);
    final thisKey = 'this.$fieldKey';
    if (isPrimitive) {
      return "data['$key'] = $thisKey;";
    } else if (name == 'List') {
      // class list
      if (nullSafety) {
        return """if ($thisKey != null) {
      data['$key'] = $thisKey?.map((v) => ${_buildToJsonClass('v')}).toList();
    }""";
      }
      return """if ($thisKey != null) {
      data['$key'] = $thisKey.map((v) => ${_buildToJsonClass('v')}).toList();
    }""";
    } else {
      // class
      if (nullSafety) {
        return """
          data['$key'] = ${_buildToJsonClass(thisKey, nullSafety)};
        """;
      }
      return """if ($thisKey != null) {
      data['$key'] = ${_buildToJsonClass(thisKey, nullSafety)};
    }""";
    }
  }
}

class Dependency {
  String name;
  final TypeDefinition typeDef;

  Dependency(this.name, this.typeDef);

  String get className => camelCase(name);
}

class ClassDefinition {
  final String _name;
  final bool _privateFields;
  final bool _nullSafety; //是否空值安全
  final Map<String, TypeDefinition> fields = new Map<String, TypeDefinition>();
  final String _unifiedClassCrefix;

  // 给子类添加前缀
  String get name => _name == _unifiedClassCrefix ? _name : _unifiedClassCrefix + _name;
  bool get privateFields => _privateFields;
  bool get nullSafety => _nullSafety;

  List<Dependency> get dependencies {
    final dependenciesList = <Dependency>[];
    final keys = fields.keys;
    keys.forEach((k) {
      final f = fields[k];
      if (!f.isPrimitive) {
        dependenciesList.add(new Dependency(k, f));
      }
    });
    return dependenciesList;
  }

  ClassDefinition(this._name, [this._privateFields = false, this._nullSafety = false, this._unifiedClassCrefix = ""]);

  bool operator ==(other) {
    if (other is ClassDefinition) {
      ClassDefinition otherClassDef = other;
      return this.isSubsetOf(otherClassDef) && otherClassDef.isSubsetOf(this);
    }
    return false;
  }

  bool isSubsetOf(ClassDefinition other) {
    final List<String> keys = this.fields.keys.toList();
    final int len = keys.length;
    for (int i = 0; i < len; i++) {
      TypeDefinition otherTypeDef = other.fields[keys[i]];
      if (otherTypeDef != null) {
        TypeDefinition typeDef = this.fields[keys[i]];
        if (typeDef != otherTypeDef) {
          return false;
        }
      } else {
        return false;
      }
    }
    return true;
  }

  hasField(TypeDefinition otherField) {
    return fields.keys.firstWhere((k) => fields[k] == otherField, orElse: () => null) != null;
  }

  addField(String name, TypeDefinition typeDef) {
    fields[name] = typeDef;
  }

  void _addTypeDef(TypeDefinition typeDef, StringBuffer sb) {
    sb.write('${typeDef.name}');
    if (typeDef.subtype != null) {
      sb.write('<${typeDef.subtype}>');
    }
  }

  String get _fieldList {
    return fields.keys.map((key) {
      final f = fields[key];
      final fieldName = fixFieldName(key, typeDef: f, privateField: privateFields);
      final sb = new StringBuffer();
      sb.write('\t');

      // 添加说明
      if (f?.description != null) {
        sb.write('/// ${f.description} \n');
      }
      if (nullSafety) {
        //sb.write(' late ');
      }

      _addTypeDef(f, sb);
      if (nullSafety) {
        //sb.write(' late ');
        sb.write('? $fieldName;');
      } else {
        sb.write(' $fieldName;');
      }

      return sb.toString();
    }).join('\n');
  }

  String get _gettersSetters {
    return fields.keys.map((key) {
      final f = fields[key];
      final publicFieldName = fixFieldName(key, typeDef: f, privateField: false);
      final privateFieldName = fixFieldName(key, typeDef: f, privateField: true);
      final sb = new StringBuffer();
      sb.write('\t');
      _addTypeDef(f, sb);
      sb.write(' get $publicFieldName => $privateFieldName;\n\tset $publicFieldName(');
      _addTypeDef(f, sb);
      sb.write(' $publicFieldName) => $privateFieldName = $publicFieldName;');
      return sb.toString();
    }).join('\n');
  }

  String get _defaultPrivateConstructor {
    final sb = new StringBuffer();
    sb.write('\t$name({');
    var i = 0;
    var len = fields.keys.length - 1;
    fields.keys.forEach((key) {
      final f = fields[key];
      final publicFieldName = fixFieldName(key, typeDef: f, privateField: false);
      _addTypeDef(f, sb);
      sb.write(' $publicFieldName');
      if (i != len) {
        sb.write(', ');
      }
      i++;
    });
    sb.write('}) {\n');
    fields.keys.forEach((key) {
      final f = fields[key];
      final publicFieldName = fixFieldName(key, typeDef: f, privateField: false);
      final privateFieldName = fixFieldName(key, typeDef: f, privateField: true);
      sb.write('this.$privateFieldName = $publicFieldName;\n');
    });
    sb.write('}');
    return sb.toString();
  }

  String get _defaultConstructor {
    final sb = new StringBuffer();
    sb.write('\t$name({');
    var i = 0;
    var len = fields.keys.length - 1;
    fields.keys.forEach((key) {
      final f = fields[key];
      final fieldName = fixFieldName(key, typeDef: f, privateField: privateFields);
      sb.write('this.$fieldName');
      if (i != len) {
        sb.write(', ');
      }
      i++;
    });
    sb.write('});');
    return sb.toString();
  }

  String get _jsonParseFunc {
    final sb = new StringBuffer();
    sb.write('\t$name');
    sb.write('.fromJson(Map<String, dynamic> json) {\n');
    fields.keys.forEach((k) {
      sb.write('\t\t${fields[k].jsonParseExpression(k, privateFields, nullSafety)}\n');
    });
    sb.write('\t}');
    return sb.toString();
  }

  String get _jsonGenFunc {
    final sb = new StringBuffer();

    if (nullSafety) {
      sb.write('\tMap<String, dynamic> toJson() {\n\t\tfinal Map<String, dynamic> data = <String, dynamic>{};\n');
    } else {
      sb.write('\tMap<String, dynamic> toJson() {\n\t\tfinal Map<String, dynamic> data = new Map<String, dynamic>();\n');
    }

    fields.keys.forEach((k) {
      sb.write('\t\t${fields[k].toJsonExpression(k, privateFields, nullSafety)}\n');
    });
    sb.write('\t\treturn data;\n');
    sb.write('\t}');
    return sb.toString();
  }

  String toString() {
    if (privateFields) {
      return 'class $name {\n$_fieldList\n\n$_defaultPrivateConstructor\n\n$_gettersSetters\n\n$_jsonParseFunc\n\n$_jsonGenFunc\n}\n';
    } else {
      if (nullSafety) {
        // 不实用构造方法
        return 'class $name {\n$_fieldList\n\n$_jsonParseFunc\n\n$_jsonGenFunc\n}\n';
      }
      return 'class $name {\n$_fieldList\n\n$_defaultConstructor\n\n$_jsonParseFunc\n\n$_jsonGenFunc\n}\n';
    }
  }
}

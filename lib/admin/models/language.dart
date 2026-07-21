import 'package:hive/hive.dart';

part 'language.g.dart';

@HiveType(typeId: 2)
class Language {
  @HiveField(0)
  final int id;
  
  @HiveField(1)
  final String name;
  
  @HiveField(2)
  final String? imageUrl;

  Language({
    required this.id,
    required this.name,
    this.imageUrl,
  });

  factory Language.fromJson(Map<String, dynamic> json) {
    return Language(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      imageUrl: json['image_url'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'image_url': imageUrl,
    };
  }

  @override
  String toString() => 'Language(id: $id, name: $name)';
}

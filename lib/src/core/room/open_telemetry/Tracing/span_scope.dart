import 'event_category.dart';

class SpanScope {
  final String id;
  final String name;
  final int startTime;
  final Map<String, String> attributes;
  final String? parentId;
  final EventCategory category;
  final int targetMask;

  SpanScope({
    required this.id,
    required this.name,
    required this.startTime,
    required this.attributes,
    required this.parentId,
    required this.category,
    this.targetMask = 0,
  });
}

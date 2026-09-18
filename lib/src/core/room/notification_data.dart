/// Holds the information needed to display a notification.
class NotificationInfo {
  /// @nodoc
  @override
  String toString() {
    return super.toString();
  }

  /// @nodoc
  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }

  /// @nodoc
  @override
  bool operator ==(Object other) {
    return super == other;
  }

  /// @nodoc
  @override
  int get hashCode => super.hashCode;

  /// @nodoc
  const NotificationInfo({
    required this.title,
    required this.message,
    required this.icon,
  });

  /// The title of the notification.
  /// ### Type
  ///
  /// - `String`
  final String title;

  /// The message body of the notification.
  /// ### Type
  ///
  /// - `String`
  final String message;

  /// The URL or identifier of the notification icon.
  /// ### Type
  ///
  /// - `String`
  final String icon;

  /// Converts this [NotificationInfo] instance into a JSON-compatible map.
  ///
  /// This method serializes the notification data into a key-value
  /// structure that can be used for JSON encoding, storage, or
  /// network transmission.
  ///
  /// ### Returns
  ///
  /// - A `Map<String, String>` containing the notification properties,
  ///   including `title`, `message`, and `icon`.
  ///
  /// ### **Example**
  /// ```dart
  /// final notification = NotificationInfo(
  ///   title: 'Meeting Started',
  ///   message: 'Your meeting has successfully started.',
  ///   icon: 'bell',
  /// );
  ///
  /// final json = notification.toJson();
  /// print(json);
  /// // Output:
  /// // {
  /// //   'title': 'Meeting Started',
  /// //   'message': 'Your meeting has successfully started.',
  /// //   'icon': 'bell'
  /// // }
  /// ```
  /// @nodoc
  Map<String, String> toJson() {
    return {
      'title': title,
      'message': message,
      'icon': icon,
    };
  }
}

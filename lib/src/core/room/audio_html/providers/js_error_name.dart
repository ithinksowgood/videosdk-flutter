// ignore_for_file: invalid_runtime_check_with_js_interop_types

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// The `name` of a JavaScript error object a browser call rejected with
/// ('NotAllowedError', 'AbortError', 'NotFoundError', ...): read from the
/// object itself, not from its text. Null when [error] is not a JavaScript
/// object, has no text `name`, or the name is the bare 'Error' - the caller
/// then falls back to the text (sowgoodDomErrorName).
///
/// SowGood, 2026-11-17: the text of a rejected promise's error is whatever
/// the compiler's toString makes of it; if a refused play() were ever read
/// as 'unknown', the app would report every refusal as a failure nobody
/// knows.
String? sowgoodJsErrorName(Object error) {
  try {
    final name = (error as JSObject).getProperty<JSAny?>('name'.toJS);
    if (name == null || !name.typeofEquals('string')) return null;
    final text = (name as JSString).toDart;
    return text.isEmpty || text == 'Error' ? null : text;
  } catch (_) {
    return null;
  }
}

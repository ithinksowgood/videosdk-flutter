// ignore_for_file: strict_top_level_inference

class Logger {
  // ignore: unused_field, non_constant_identifier_names
  final String _app_name;
  // ignore: empty_constructor_bodies
  Logger(this._app_name) {}

  void error(error) {
    // print('[' + _app_name + '] ERROR: ' + error);
  }

  void debug(msg) {
    // print('[' + _app_name + '] DEBUG: ' + msg);
  }

  void warn(msg) {
    // print('[' + _app_name + '] WARN: ' + msg);
  }

  void failure(error) {
    throw (error);
    // var log = '[' + _app_name + '] FAILURE: ' + error;
    // print(log);
    // throw (log);
  }
}

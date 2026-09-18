// ignore_for_file: strict_top_level_inference
import '../enhanced_event_emitter.dart';

abstract class TransportInterface extends EnhancedEventEmitter {
  TransportInterface(String url, {dynamic options}) : super();

  get closed;

  Future send(dynamic message);

  close();
}

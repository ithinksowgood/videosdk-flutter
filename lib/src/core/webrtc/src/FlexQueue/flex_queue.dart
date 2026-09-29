import 'dart:async';
import 'dart:developer';

/// SOWGOOD (2026-09-28, Founders Night): a failing task was visible only in the
/// browser console, and a task that never finishes blocks every later one (the
/// queue has no timeout) - a listener who heard no late speaker left no trace.
/// The app sets these hooks to report both. Null = no report.
void Function(String task, Object error, StackTrace stack)? sowgoodFlexTaskFailed;
void Function(String task, Duration running)? sowgoodFlexTaskStalled;
const Duration sowgoodFlexStallAfter = Duration(seconds: 15);

abstract class FlexTask {
  final String? id;
  final Function execFun;
  final Function? callbackFun;
  final Function? errorCallbackFun;
  final Object? argument;
  final String? message;

  FlexTask({
    this.id,
    required this.execFun,
    this.argument,
    this.callbackFun,
    this.errorCallbackFun,
    this.message,
  });
}

class FlexTaskAdd extends FlexTask {
  FlexTaskAdd({
    super.id,
    required super.execFun,
    super.argument,
    super.callbackFun,
    super.errorCallbackFun,
    super.message,
  });
}

class FlexTaskRemove extends FlexTask {
  FlexTaskRemove({
    super.id,
    required super.execFun,
    super.argument,
    super.callbackFun,
    super.errorCallbackFun,
    super.message,
  });
}

class FlexQueue {
  bool isBusy = false;
  final List<FlexTask> taskQueue = [];

  void addTask(FlexTask task) async {
    if (task is FlexTaskRemove) {
      final int index =
          taskQueue.indexWhere((FlexTask qTask) => qTask.id == task.id);
      if (index != -1) {
        taskQueue.removeAt(index);
        return;
      } else {
        taskQueue.add(task);
        _runTask();
      }
    } else if (task is FlexTaskAdd) {
      taskQueue.add(task);
      _runTask();
    }
  }

  Future<void> _runTask() async {
    if (!isBusy) {
      if (taskQueue.isNotEmpty) {
        isBusy = true;
        final FlexTask task = taskQueue.removeAt(0);
        final Timer stall = Timer(
          sowgoodFlexStallAfter,
          () => sowgoodFlexTaskStalled?.call(
              task.message ?? '', sowgoodFlexStallAfter),
        );
        try {
          if (task.argument == null) {
            final result = await task.execFun();
            task.callbackFun?.call(result);
          } else {
            final result = await task.execFun(task.argument);
            task.callbackFun?.call(result);
          }
        } catch (error, st) {
          log(error.toString());
          log(st.toString());
          // SOWGOOD DIAGNOSTIC (2026-09-18): dart:developer's log() prints
          // nothing on the web, so a failing consume task was invisible on
          // Safari; print() reaches the console, which the app captures.
          // ignore: avoid_print
          print('videosdk FlexQueue task failed (${task.message}): $error\n$st');
          sowgoodFlexTaskFailed?.call(task.message ?? '', error, st);
          task.errorCallbackFun?.call(error);
        } finally {
          stall.cancel();
          isBusy = false;
          // Re-enter to process the next queued task. This is not unbounded
          // recursion: the call returns immediately when isBusy is true or
          // taskQueue is empty, so the call depth is at most 1.
          _runTask();
        }
      }
    }
  }
}

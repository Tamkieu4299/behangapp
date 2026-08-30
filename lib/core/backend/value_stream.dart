import 'dart:async';

class ValueStream<T> {
  ValueStream(T initial) : _value = initial;

  T _value;
  final _controller = StreamController<T>.broadcast();

  T get value => _value;

  void add(T value) {
    _value = value;
    if (_controller.hasListener) _controller.add(value);
  }

  Stream<T> watch() async* {
    yield _value;
    yield* _controller.stream;
  }

  Future<void> close() => _controller.close();
}

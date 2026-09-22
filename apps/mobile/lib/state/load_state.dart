/// Состояние загрузки экрана: скелетон → данные (или пусто) → ошибка с повтором. Один тип вместо пары
/// `busy`/`error` в каждом экране.
sealed class LoadState<T> {
  const LoadState();
}

class Loading<T> extends LoadState<T> {
  const Loading();
}

class Loaded<T> extends LoadState<T> {
  const Loaded(this.data);

  final T data;
}

class Failed<T> extends LoadState<T> {
  const Failed(this.error);

  final Object error;
}

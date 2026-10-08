# Corrección local de audioplayers_windows

Basado en `audioplayers_windows` 4.4.1 de [Blue Fire](https://github.com/bluefireteam/audioplayers/tree/main/packages/audioplayers_windows), con su licencia MIT conservada en `LICENSE`.

Los archivos nativos se conservan como en el paquete publicado, salvo `windows/event_stream_handler.h`. Este handler copia los eventos a una cola y utiliza una ventana de mensajes creada en el hilo de plataforma para entregarlos a Flutter. Los callbacks de Media Foundation ya no llaman directamente a `EventSink` desde hilos de audio. La cancelación libera el sink y descarta los mensajes pendientes antes de destruir la ventana; una nueva suscripción crea otra ventana.

Rucio selecciona esta implementación mediante `dependency_overrides` en el `pubspec.yaml` principal. La corrección forma parte del repositorio y no modifica la caché global de Pub.

La prueba `test/native/audio_event_thread_test.cpp` comprueba los hilos de entrega, el orden de los eventos, la copia de detalles de errores y la cancelación, resuscripción y destrucción con eventos pendientes. `integration_test/desktop_audio_test.dart` comprueba el reproductor real de Windows.

Al actualizar el plugin, compara los archivos con esta versión y conserva la corrección mientras el proveedor no entregue los eventos en el hilo de plataforma.

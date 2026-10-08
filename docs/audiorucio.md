# Audiorucio para Windows y Android

Abre un libro y selecciona **Herramientas de lectura → Iniciar Audiorucio**, o utiliza el botón del mismo nombre en **Ajustes de lectura**. La vista muestra la portada, el título, el autor y el texto de la página visible del lector. Al entrar siempre queda en pausa y no genera audio hasta que pulses reproducir. **Volver al libro** detiene el audio y recupera el lector en la página que se estaba escuchando.

Incluye reproducción y pausa, retroceso de 5 segundos, avance de 15 segundos, barra de posición del fragmento, volumen y estas voces de español de España:

| Opción | Voz de Google Cloud |
| --- | --- |
| Estándar | `es-ES-Standard-H` |
| Premium | `es-ES-Chirp3-HD-Autonoe` |

La narración usa la paginación real de epub.js, con el tamaño de letra, interlineado, márgenes y una o dos columnas configurados en el lector. Al terminar una página pasa automáticamente a la siguiente y mantiene sincronizada la posición de lectura. Una segunda vista oculta, con las mismas dimensiones y estilos, obtiene las páginas siguientes sin mover el lector durante la precarga. Las páginas sin texto se omiten.

Mientras se reproduce, se prepara un único fragmento por adelantado. La precarga se cancela al pausar, cambiar de voz o salir; si el audio ya se generó, queda en la caché local. Si una página supera el límite de Google, su audio se divide internamente en partes de hasta 4500 bytes UTF-8 y se reproduce seguido, manteniendo el texto de la página completa en pantalla. La barra temporal corresponde a la parte de audio actual. Los saltos temporales atraviesan estas partes y páginas de la sesión. Al cambiar de voz se conserva la proporción reproducida de la parte: la posición es aproximada porque las voces tienen duraciones distintas. No hay seguimiento palabra por palabra.

## Android: segundo plano y controles multimedia

Puedes minimizar Rucio o apagar la pantalla mientras escuchas. Android muestra una sesión multimedia con el título y la portada del libro, pausa/reanudación, retroceso de 5 segundos, avance de 15 segundos y detener. La distribución de los controles depende de la versión de Android. Detener conserva el punto de escucha y retira la notificación; pausar permite reanudar desde ella.

El audio utiliza `just_audio`, `audio_session` y un servicio de reproducción de `audio_service`. El servicio mantiene activa la aplicación durante la escucha. Las llamadas y la desconexión de auriculares pausan la reproducción. La paginación oculta utiliza temporizadores para poder obtener la siguiente página aunque el WebView no esté dibujando. El progreso se guarda desde Flutter y el lector vuelve a la página escuchada cuando recupera el primer plano.

**Volver al libro**, el botón Atrás dentro de Audiorucio y cerrar Rucio desde aplicaciones recientes detienen la sesión. Entrar de nuevo sigue dejando el reproductor en pausa. La caché y el consumo mensual pertenecen a cada instalación: el móvil y el PC mantienen registros independientes.

## Conectar Google Cloud

Puedes utilizar tu cuenta de facturación existente para un proyecto nuevo:

1. Crea un proyecto llamado `Audiorucio` en la [consola de Google Cloud](https://console.cloud.google.com/projectcreate).
2. En **Facturación**, vincula el proyecto a tu cuenta de facturación actual.
3. Selecciona ese proyecto y habilita [Cloud Text-to-Speech API](https://console.cloud.google.com/apis/library/texttospeech.googleapis.com).
4. En [APIs y servicios → Credenciales](https://console.cloud.google.com/apis/credentials), crea una **Clave de API** y limita sus restricciones de API a **Cloud Text-to-Speech API**.
5. En Audiorucio, pulsa **Conectar Google Cloud**, introduce la clave y pulsa **Conectar**.

La clave introducida se conserva en memoria durante la sesión de la aplicación. No se guarda en preferencias, Supabase ni en los archivos de audio. Para desarrollo local también se admite `GOOGLE_CLOUD_TTS_API_KEY` dentro del `.env` ignorado por Git. Los comandos de ejecución y compilación mantienen `--dart-define-from-file=.env`.

Google factura la generación del audio según su [tarifa de Text-to-Speech](https://cloud.google.com/text-to-speech/pricing). Cambiar de voz puede generar otra versión del mismo texto. La precarga también cuenta como generación, aunque después no escuches ese fragmento; se incluye en el panel de consumo mensual. Solo se anticipa el siguiente fragmento mientras escuchas, sin generar el libro completo.

## Caché y posición

El audio MP3 se almacena en `audiorucio` dentro del directorio de soporte local de la aplicación. No se sube audio a Supabase. La caché distingue usuario, libro, voz y texto; reutiliza los fragmentos existentes y elimina los menos recientes al superar 500 MiB, conservando el archivo en uso. Durante un cambio de fragmento se protegen temporalmente los dos archivos.

**Opciones de audio → Vaciar caché de audio** detiene la reproducción y libera esos archivos. Volver a escuchar un fragmento eliminado requiere generar audio de nuevo. Los fragmentos ya almacenados se pueden reproducir sin clave ni conexión, siempre que el EPUB esté abierto en el lector.

La voz, el volumen y el punto temporal de escucha se guardan localmente. La posición del lector sigue usando el mecanismo de progreso existente. Al volver a Audiorucio se recupera el punto temporal, en pausa, cuando coincide la página y su texto; si se ha navegado a otra parte del libro o ha cambiado la paginación, se respeta la nueva página.

## Consumo mensual

El botón **Consumo mensual** de la barra superior muestra los caracteres generados por cada voz, el coste estimado en USD tras el tramo gratuito, el valor sin ese tramo y el historial de los meses registrados. El registro empieza con esta versión; no reconstruye el uso anterior. Los meses siguen el calendario y la hora local del dispositivo, por lo que los límites pueden diferir de los periodos de Google.

Tarifas de referencia verificadas el 08/10/2026 en [Google Cloud](https://cloud.google.com/text-to-speech/pricing):

| Voz | Tramo gratuito mensual | Precio posterior |
| --- | --- | --- |
| Estándar | 4.000.000 caracteres | 4 USD/millón |
| Premium (Chirp 3 HD) | 1.000.000 caracteres | 30 USD/millón |

Se cuentan los caracteres Unicode enviados, incluidos espacios, puntuación y saltos de línea. Una respuesta satisfactoria de Google suma consumo aunque falle después la reproducción o el almacenamiento del audio. La caché, la pausa y la reanudación no generan consumo. Vaciar la caché conserva el registro; regenerar un fragmento eliminado sí suma otra vez.

Las solicitudes quedan registradas antes de enviarse. Si Google rechaza explícitamente la solicitud con un error 4xx, se descarta del consumo. Si no llega respuesta por un corte, cancelación o error del servidor, sus caracteres quedan **sin confirmar** incluso tras reiniciar: Google podría haberlos facturado. Se muestran aparte y no se suman al coste estimado. Si el registro local no puede leerse o guardarse, no se envían nuevas generaciones; los audios de la caché siguen disponibles.

Los contadores se guardan en las preferencias locales del dispositivo, separados de la caché y sin guardar el texto ni la clave de API. Suman todas las claves y usuarios que utilicen esta instalación. No se sincronizan con Supabase ni con otros dispositivos.

**Es una estimación del uso registrado, no la factura de Google.** Supone que el tramo gratuito está disponible para ese consumo; el uso previo u otras aplicaciones y dispositivos pueden agotarlo. Standard y WaveNet comparten SKU. Cambiar entre proyectos con tramos distintos también puede alterar la estimación. No incluye impuestos, conversión de moneda, créditos ni descuentos. Las tarifas de referencia están incorporadas en la aplicación y deben revisarse si Google las cambia.

Para comprobar el importe registrado por Google, usa **Facturación → Informes** en la consola, filtrando por proyecto y servicio Cloud Text-to-Speech. Integrar esos datos en Rucio requeriría configurar [exportación de facturación a BigQuery](https://cloud.google.com/billing/docs/how-to/export-data-bigquery) y acceso autenticado con permisos de consulta; la clave actual de Text-to-Speech no proporciona acceso a la facturación. La exportación se actualiza durante el día y BigQuery puede generar costes de almacenamiento y consulta.

## Próxima iteración: highlights

El texto es seleccionable. Cada párrafo conserva su rango CFI y los segmentos originales de texto con sus propios rangos CFI. Esto permite asociar selecciones con el EPUB en la próxima iteración. Esta versión todavía no ofrece guardar highlights desde Audiorucio.

## Verificación

Windows utiliza la copia local de `audioplayers_windows` en `third_party/audioplayers_windows`, basada en 4.4.1. Los eventos de audio se entregan a Flutter mediante una cola despachada en el hilo de plataforma. Esto corrige el aviso `channel sent a message from native to Flutter on a non-platform thread` de la implementación original. La corrección requiere detener la aplicación y volver a ejecutar `flutter run --dart-define-from-file=.env`: hot reload y hot restart no recompilan el plugin nativo.

`./tool/test_audio_events.ps1` compila y ejecuta las pruebas de concurrencia con las herramientas C++ de Visual Studio y los headers generados por Flutter. Verifican la entrega en el hilo correcto, el orden de los eventos, los detalles de errores y la limpieza al cancelar o destruir el handler.

```powershell
flutter pub get
flutter analyze
flutter test
./tool/test_audio_events.ps1
node --test test/javascript/*.test.cjs
flutter test integration_test/desktop_audio_test.dart -d windows --dart-define-from-file=.env
flutter build windows --release --dart-define-from-file=.env
```

Las pruebas automáticas cubren extracción con CFIs reales de epub.js, límites de páginas y vistas que abarcan varios capítulos, división por bytes UTF-8, reproducción automática al completar cada página, precarga en curso sin duplicar solicitudes, cancelación al pausar, reutilización y eliminación de caché, errores de Google, cambio de voz, saltos temporales, reanudación en pausa y cierre durante generación.

Las pruebas de integración abren un EPUB en el WebView real de Windows, entran en Audiorucio y vuelven al libro. Comparan los CFIs y el texto con las páginas del lector en distintos tamaños de letra, márgenes y vistas de una o dos columnas, y comprueban que la precarga no modifica el progreso ni pierde o repite texto. El reproductor nativo completa tres páginas seguidas con audio silencioso local, sin contactar con Google.

El consumo se verifica con cambios de mes y año, peticiones concurrentes, caracteres Unicode, persistencia, tramos gratuitos, errores y cancelaciones, regeneración tras vaciar la caché y navegación por el historial. La integración de Windows también abre y cierra el panel de consumo.

La integración Android usa un EPUB y audio silencioso locales para comprobar la paginación real, el avance por varias páginas en segundo plano y los comandos enviados a la sesión multimedia de Android. No envía solicitudes a Google. Con un móvil conectado, desbloqueado y con depuración USB:

```powershell
python tool/test_android_audio.py --device <identificador-adb> --adb <ruta-a-adb.exe>
python tool/test_android_audio.py --device <identificador-adb> --adb <ruta-a-adb.exe> --screen-off
python -B -m unittest discover -s test -p test_android_audio_tool.py
flutter build apk --release --target-platform android-arm64 --dart-define-from-file=.env
```

La segunda prueba apaga la pantalla. Si hay bloqueo seguro, desbloquea el móvil al terminar para que la prueba pueda recuperar el primer plano. El script utiliza el identificador independiente `com.rucio.rucio_flutter.audio_test` mediante `--android-project-arg=audiorucioIntegrationTest=true` y evita la limpieza automática de Flutter con `--keep-app-running`. Después elimina únicamente ese paquete de prueba. No ejecutes la integración directamente con el identificador de producción en un móvil con datos.

Verificado en un Xiaomi 24122RKC7G con Android 16: reproducción continua por varias páginas con la aplicación minimizada y con la pantalla apagada, controles nativos de pausa, retroceso, avance, reanudación y detener. La compilación APK de producción en modo release también pasa.

La generación y escucha de las dos voces reales requieren una clave con la API y la facturación activadas.

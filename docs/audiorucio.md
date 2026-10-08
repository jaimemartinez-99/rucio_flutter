# Audiorucio para Windows

Abre un libro y selecciona **Herramientas de lectura → Iniciar Audiorucio**, o utiliza el botón del mismo nombre en **Ajustes de lectura**. La vista muestra la portada, el título, el autor y el texto del fragmento que se escucha. **Volver al libro** detiene el audio y recupera el lector.

Incluye reproducción y pausa, retroceso de 5 segundos, avance de 15 segundos, barra de posición del fragmento, volumen y estas voces de español de España:

| Opción | Voz de Google Cloud |
| --- | --- |
| Estándar | `es-ES-Standard-H` |
| Premium | `es-ES-Chirp3-HD-Autonoe` |

La narración continúa por fragmentos y capítulos desde la posición del lector. Los saltos temporales atraviesan los fragmentos de esta sesión. Al cambiar de voz se conserva la proporción reproducida del fragmento: la posición es aproximada porque las voces tienen duraciones distintas. El texto se actualiza por fragmento, sin seguimiento palabra por palabra.

## Conectar Google Cloud

Puedes utilizar tu cuenta de facturación existente para un proyecto nuevo:

1. Crea un proyecto llamado `Audiorucio` en la [consola de Google Cloud](https://console.cloud.google.com/projectcreate).
2. En **Facturación**, vincula el proyecto a tu cuenta de facturación actual.
3. Selecciona ese proyecto y habilita [Cloud Text-to-Speech API](https://console.cloud.google.com/apis/library/texttospeech.googleapis.com).
4. En [APIs y servicios → Credenciales](https://console.cloud.google.com/apis/credentials), crea una **Clave de API** y limita sus restricciones de API a **Cloud Text-to-Speech API**.
5. En Audiorucio, pulsa **Conectar Google Cloud**, introduce la clave y pulsa **Conectar**.

La clave introducida se conserva en memoria durante la sesión de la aplicación. No se guarda en preferencias, Supabase ni en los archivos de audio. Para desarrollo local también se admite `GOOGLE_CLOUD_TTS_API_KEY` dentro del `.env` ignorado por Git. Los comandos de ejecución y compilación mantienen `--dart-define-from-file=.env`.

Google factura la generación del audio según su [tarifa de Text-to-Speech](https://cloud.google.com/text-to-speech/pricing). Cambiar de voz puede generar otra versión del mismo texto. No se genera el libro completo ni se anticipan fragmentos que todavía no has solicitado.

## Caché y posición

El audio MP3 se almacena en `audiorucio` dentro del directorio de soporte local de la aplicación. No se sube audio a Supabase. La caché distingue usuario, libro, voz y texto; reutiliza los fragmentos existentes y elimina los menos recientes al superar 500 MiB, conservando el archivo en uso. Durante un cambio de fragmento se protegen temporalmente los dos archivos.

**Opciones de audio → Vaciar caché de audio** detiene la reproducción y libera esos archivos. Volver a escuchar un fragmento eliminado requiere generar audio de nuevo. Los fragmentos ya almacenados se pueden reproducir sin clave ni conexión, siempre que el EPUB esté abierto en el lector.

La voz, el volumen y el punto temporal de escucha se guardan localmente. La posición del lector sigue usando el mecanismo de progreso existente. El punto temporal se recupera cuando el lector continúa en la misma posición; si se ha navegado a otra parte del libro, se respeta esa nueva posición.

## Consumo mensual

El botón **Consumo mensual** de la barra superior muestra los caracteres generados por cada voz, el coste estimado en USD tras el tramo gratuito, el valor sin ese tramo y el historial de los meses registrados. El registro empieza con esta versión; no reconstruye el uso anterior. Los meses siguen el calendario y la hora local del PC, por lo que los límites pueden diferir de los periodos de Google.

Tarifas de referencia verificadas el 08/10/2026 en [Google Cloud](https://cloud.google.com/text-to-speech/pricing):

| Voz | Tramo gratuito mensual | Precio posterior |
| --- | --- | --- |
| Estándar | 4.000.000 caracteres | 4 USD/millón |
| Premium (Chirp 3 HD) | 1.000.000 caracteres | 30 USD/millón |

Se cuentan los caracteres Unicode enviados, incluidos espacios, puntuación y saltos de línea. Una respuesta satisfactoria de Google suma consumo aunque falle después la reproducción o el almacenamiento del audio. La caché, la pausa y la reanudación no generan consumo. Vaciar la caché conserva el registro; regenerar un fragmento eliminado sí suma otra vez.

Las solicitudes quedan registradas antes de enviarse. Si Google rechaza explícitamente la solicitud con un error 4xx, se descarta del consumo. Si no llega respuesta por un corte, cancelación o error del servidor, sus caracteres quedan **sin confirmar** incluso tras reiniciar: Google podría haberlos facturado. Se muestran aparte y no se suman al coste estimado. Si el registro local no puede leerse o guardarse, no se envían nuevas generaciones; los audios de la caché siguen disponibles.

Los contadores se guardan en las preferencias locales del PC, separados de la caché y sin guardar el texto ni la clave de API. Suman todas las claves y usuarios que utilicen esta instalación. No se sincronizan con Supabase ni con otros dispositivos.

**Es una estimación del uso registrado, no la factura de Google.** Supone que el tramo gratuito está disponible para ese consumo; el uso previo u otras aplicaciones y dispositivos pueden agotarlo. Standard y WaveNet comparten SKU. Cambiar entre proyectos con tramos distintos también puede alterar la estimación. No incluye impuestos, conversión de moneda, créditos ni descuentos. Las tarifas de referencia están incorporadas en la aplicación y deben revisarse si Google las cambia.

Para comprobar el importe registrado por Google, usa **Facturación → Informes** en la consola, filtrando por proyecto y servicio Cloud Text-to-Speech. Integrar esos datos en Rucio requeriría configurar [exportación de facturación a BigQuery](https://cloud.google.com/billing/docs/how-to/export-data-bigquery) y acceso autenticado con permisos de consulta; la clave actual de Text-to-Speech no proporciona acceso a la facturación. La exportación se actualiza durante el día y BigQuery puede generar costes de almacenamiento y consulta.

## Próxima iteración: highlights

El texto es seleccionable. Cada párrafo conserva su rango CFI y los segmentos originales de texto con sus propios rangos CFI. Esto permite asociar selecciones con el EPUB en la próxima iteración. Esta versión todavía no ofrece guardar highlights desde Audiorucio.

## Verificación

```powershell
flutter pub get
flutter analyze
flutter test
node --test test/javascript/*.test.cjs
flutter test integration_test/desktop_audio_test.dart -d windows --dart-define-from-file=.env
flutter build windows --release --dart-define-from-file=.env
```

Las pruebas automáticas cubren extracción con CFIs reales de epub.js, división por bytes UTF-8, transiciones de capítulos, reutilización y eliminación de caché, errores de Google, cambio de voz, saltos temporales, reanudación, cierre durante generación y disposición de la vista. Las pruebas de integración abren un EPUB en el WebView real de Windows, entran en Audiorucio, comprueban el texto y vuelven al libro; también reproducen un archivo silencioso local en el componente de audio nativo, sin contactar con Google.

El consumo se verifica con cambios de mes y año, peticiones concurrentes, caracteres Unicode, persistencia, tramos gratuitos, errores y cancelaciones, regeneración tras vaciar la caché y navegación por el historial. La integración de Windows también abre y cierra el panel de consumo.

La generación y escucha de las dos voces reales requieren una clave con la API y la facturación activadas.

# Lector compartido

## Audiorucio

Windows y Android incluyen **Iniciar Audiorucio** en las herramientas y ajustes del lector. Abre un reproductor con portada, texto seleccionable, las voces Standard-H y Autonoe, pausa, saltos de −5/+15 segundos y volumen. Android permite seguir escuchando con la aplicación minimizada o la pantalla apagada, con controles multimedia del sistema. El audio utiliza una caché local de hasta 500 MiB por dispositivo. La configuración, las pruebas y el alcance de la siguiente iteración de highlights están en [Audiorucio](audiorucio.md).

Windows, Android e iOS usan `ReaderScreen`: selección de texto, tipos de highlight, notas, Vocablingo y definiciones, Claude, búsqueda, ajustes y progreso se gestionan en la misma pantalla.

`ReaderWebView` adapta la comunicación y el componente nativo: WebView2 en Windows y `webview_flutter` en móvil. Los mensajes JavaScript se procesan en una sola implementación. `ReaderContentLoader` prepara el mismo HTML y utiliza la caché EPUB en ambas plataformas.

El EPUB se sirve desde la caché mediante HTTP en `127.0.0.1`, también en Windows. El archivo no se incrusta en base64 dentro del HTML: así los libros grandes no superan el [límite de 2 MB de NavigateToString en WebView2](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/working-with-local-content). El servidor local se cierra al salir del lector.

## Información del libro

Mantener pulsado un libro abre un menú con «Información del libro», además de las opciones de eliminación. La ficha lee título, autores, colaboradores, editorial, idiomas, fecha, identificadores, temas, colección y sinopsis del EPUB. Utiliza el archivo en caché; si no está descargado, lo descarga con la sesión del usuario. El análisis del ZIP y XML se realiza en un isolate.

Las páginas se obtienen primero de los metadatos, incluidos los campos de Calibre. Si no hay un total declarado, se cuentan los destinos únicos del índice de páginas EPUB 3 o NCX de EPUB 2 y se muestran como «Páginas referenciadas». La [especificación EPUB](https://www.w3.org/TR/epub-33/#sec-nav-pagelist) describe este índice opcional. Si faltan ambos datos se muestra «No indicado en el EPUB».

## Notas al pie del EPUB

Pulsar una referencia como `[1]` abre una ventana con el texto seleccionable de la nota. Las notas largas se pueden desplazar. Cerrar la ventana conserva la página y el progreso porque el lector carga el documento de destino desde el EPUB sin navegar a él. Funciona también sin conexión si el libro está descargado.

Se reconocen las referencias semánticas EPUB 3, referencias antiguas por identificador o superíndice y archivos de notas de EPUB 2, incluidos archivos individuales como `nota1.html`. Se extrae el bloque de la nota y se eliminan los enlaces de retorno. Los enlaces normales de capítulos, índices y páginas mantienen su navegación habitual. Si falla la lectura de una nota, se muestra el error en la misma ventana.

## Traducción local

En Android e iOS se mantiene Google ML Kit. En Windows se utiliza CTranslate2 con el modelo inglés → español de Argos y SentencePiece. El resultado puede variar entre motores; en ambos casos el texto se traduce en el dispositivo.

La primera traducción en Windows descarga un entorno privado de Python, el motor y el modelo (unos 160 MB de descarga en total). Los archivos se guardan en el directorio de soporte de Rucio. No es necesario instalar Python manualmente. Una vez preparado, no se necesita conexión para traducir. Los fragmentos seleccionados se pasan al proceso local por entrada estándar.

Versiones: uv 0.12.23, Python 3.11, CTranslate2 4.8.2, SentencePiece 0.2.1, NumPy 2.4.6, PyYAML 6.0.3 y Argos en_es 1.0. Las descargas de uv y del modelo se verifican mediante SHA-256. Las dependencias se instalan desde PyPI con versiones fijadas.

Fuentes: [CTranslate2](https://opennmt.net/CTranslate2/), [Argos Translate](https://github.com/argosopentech/argos-translate), [índice de modelos](https://github.com/argosopentech/argospm-index), [SentencePiece](https://github.com/google/sentencepiece), [uv](https://docs.astral.sh/uv/).

## Verificación

`flutter analyze` y `flutter test` comprueban el lector compartido y sus flujos. Para verificar también la instalación y traducción real en Windows:

```powershell
$env:RUN_LOCAL_TRANSLATION_TESTS = 'true'
flutter test test/desktop_translation_test.dart
```

Esta prueba descarga los componentes a `.dart_tool/translation_install_validation` y comprueba después que se puede traducir con las descargas bloqueadas.

Las pruebas de extracción y navegación de notas usan jsdom únicamente como dependencia de desarrollo:

```powershell
cd test/javascript
npm ci
npm test
```

# Actualizaciones de Android

La primera versión con el actualizador se instala abriendo el APK sobre la app existente, sin desinstalarla. Las siguientes versiones se descargan desde Rucio. Android siempre pide confirmar la instalación; la primera vez también hay que permitir que Rucio instale aplicaciones.

La biblioteca busca actualizaciones al entrar, con un intervalo de doce horas entre comprobaciones correctas. Opciones → Buscar actualizaciones permite comprobarlas en cualquier momento. Una comprobación fallida no retrasa el siguiente intento.

Los APK se guardan en el bucket privado `rucio-updates` de Supabase. Cada cuenta autorizada tiene su propio directorio; las políticas permiten leer únicamente el directorio del usuario autenticado y prohíben modificarlo desde la aplicación. Los usuarios para los que se publican versiones se configuran fuera del repositorio, en `~/.rucio/updates.json`. Al publicar por primera vez se utiliza la cuenta con sesión abierta en Rucio para Windows. Para otro usuario hay que añadir expresamente su identificador a esa configuración y publicar para él.

## Publicar una versión

1. Incrementar `version` y el número después de `+` en `pubspec.yaml`.
2. Escribir las notas en `docs/releases/<versión>.md`.
3. Ejecutar `flutter analyze` y las pruebas pertinentes.
4. Ejecutar `python tool/publish_android_release.py --notes-file docs/releases/<versión>.md --publish`.

El comando compila con `.env`, divide los APK por arquitectura, comprueba paquete, versión, tamaño y certificado, y publica el manifiesto disponible para la aplicación después de subir los archivos. Sin `--publish` solamente prepara y verifica los APK. `--skip-build` permite publicar APK ya compilados después de verificarlos de nuevo.

`python tool/verify_android_updates.py` descarga los APK publicados, valida tamaño y SHA-256 y comprueba las políticas de acceso con los roles autenticado y anónimo. Las comprobaciones de escritura se ejecutan en una transacción que se revierte.

Las credenciales administrativas se obtienen de la sesión local de Supabase CLI durante la publicación; no se incorporan al APK. Los APK contienen la configuración de servicios de la aplicación, por lo que deben mantenerse privados.

## Firma y conservación de datos

Se conserva la clave con la que se firmaron las instalaciones anteriores. `tool/prepare_android_signing.ps1` la copia a `~/.rucio/signing/rucio-release.keystore`, crea otra copia local en `~/.rucio/signing/backup/` y prepara el archivo ignorado `android/key.properties`. El certificado público esperado está en `android/release-certificate.sha256`.

En otro ordenador es necesario restaurar esa misma clave. Las copias actuales están en este PC; para protegerse de una avería hay que conservar una copia adicional fuera de él. Una clave diferente impediría actualizar las instalaciones existentes.

Los APK divididos conservan el mismo número de versión para todas las arquitecturas mediante `force-version-code-ignoring-abi=true`. El descargador usa caché local, valida tamaño y SHA-256 y elimina descargas incompletas. Android comprueba también el paquete, el certificado y que la versión sea posterior antes de abrir el instalador. La actualización mantiene los datos de la app porque conserva su identificador y firma.

Las versiones anteriores permanecen en Storage. Revisar su ocupación al publicar varias versiones y retirar los APK antiguos cuando ya no se necesiten; conservar siempre los referenciados por `latest.json`.

## Verificación

`flutter test test/android_update_test.dart` comprueba selección de arquitectura, metadatos incompatibles, descargas corruptas, exceso de tamaño, verificación nativa, reutilización de caché, cambios del APK antes de instalar y frecuencia de comprobaciones. La instalación completa y los permisos requieren una prueba en un dispositivo Android.

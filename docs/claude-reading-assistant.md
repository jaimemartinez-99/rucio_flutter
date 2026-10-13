# Asistente de lectura de Claude

El asistente usa RAG local: recorta el EPUB desde el comienzo hasta una posición CFI comprobada, busca pasajes relevantes dentro de ese prefijo y envía esos pasajes a Claude. Desde una selección, el límite es el final de esa selección. Desde el menú del lector, el límite es el comienzo de la página actual, para evitar incluir texto de esa página que todavía no se haya leído. El límite se fija al abrir el panel.

No se incluyen capítulos posteriores, índice, notas semánticas, contenido oculto ni secciones fuera del orden de lectura. Los nombres de archivos y las etiquetas del índice tampoco se envían a Claude, porque pueden adelantar acontecimientos. La ubicación se verifica contra el documento antes de extraer texto. Al retroceder y abrir otra consulta, se vuelve a extraer el contexto hasta la nueva posición. No se mantiene un registro de qué capítulos se han leído realmente: un salto hacia delante cambia el límite de la consulta.

Si falla la extracción o no se conoce la posición, la consulta se bloquea. La extracción local mantiene un límite de 2.000.000 de unidades UTF-16. La búsqueda parte exclusivamente del prefijo verificado: nunca se buscan candidatos en capítulos futuros para filtrarlos después. Al retroceder, una nueva posición genera su propio índice y no reutiliza evidencia del límite anterior.

## Recuperación local

`ClaudeRetrievalService` construye un índice BM25 en Dart, compartido por Windows y Android, sin dependencias nativas nuevas. La primera construcción y las búsquedas se ejecutan en isolates para no bloquear la interfaz. El índice se reutiliza mientras el panel conserva el mismo contexto; es una caché en memoria, no una base de datos persistente ni un servicio remoto. Reabrir el panel vuelve a preparar el texto.

El texto se divide en fragmentos de unas 1.400 unidades UTF-16, favoreciendo límites de párrafo, frase y palabra. La búsqueda normaliza mayúsculas y acentos, elimina palabras frecuentes y reconoce algunas variaciones y familias de palabras en español e inglés. Los nombres recurrentes del propio texto ayudan a priorizar candidatos; no se usan fichas de personajes ni conocimiento externo. Es recuperación léxica, sin embeddings, modelo local, resúmenes generados ni llamadas de pago para preparar el índice.

Se seleccionan los mejores candidatos y se añaden hasta dos fragmentos vecinos por lado de la misma sección. Se conserva también el final del prefijo para dar contexto a la página o selección actual. Los intervalos adyacentes se unen, se eliminan duplicados y los pasajes se ordenan cronológicamente. Para peticiones explícitas de resumen se distribuye la muestra a lo largo del texto permitido; esa muestra no garantiza cubrir todos los acontecimientos.

El presupuesto inicial es de 20.000 caracteres de pasajes. El conteo gratuito de Anthropic comprueba la petición completa, incluida la pregunta y la selección, con un máximo de 12.000 tokens de entrada. Si se supera, se reduce el presupuesto de recuperación y se vuelve a contar, hasta tres conteos. Una pregunta o selección que no permita cumplir el límite bloquea el envío y pide acortarla. Nunca se vuelve automáticamente al texto completo ni se añade una generación de pago para buscar más contexto.

El panel muestra cuánto texto se ha seleccionado y permite desplegar los pasajes antes de enviar y junto a la respuesta. Cada pasaje tiene un identificador como `[F1]`, un capítulo numérico si está presente en el texto leído y, en su defecto, una sección. No se envían nombres de archivos ni títulos futuros del índice. El historial conserva referencias y posiciones de los pasajes, sin guardar sus textos completos.

La política de `system` exige basarse exclusivamente en los pasajes adjuntos para los hechos de la obra, sin recurrir al conocimiento previo para desvelar identidades o acontecimientos. También prohíbe confirmar teorías con información futura y anticipar la importancia de un personaje. El texto y la pregunta se delimitan y escapan como datos. Se piden citas con los identificadores de pasaje y se distingue la evidencia explícita de las interpretaciones. Estas medidas reducen el riesgo; no garantizan que el modelo nunca genere un spoiler ni que sus citas o interpretaciones sean correctas.

El capítulo numérico de lectura se obtiene de los encabezados del documento en la posición comprobada, sin usar títulos de capítulos futuros del índice. El porcentaje se calcula desde el CFI cuando hay ubicaciones generadas, o desde la posición capturada del lector. El panel muestra capítulo, porcentaje y número de secciones disponibles para buscar. Los pasajes recuperados se adjuntan como `retrieved_read_passages`; son una selección discontinua y no todo el texto leído, salvo cuando el prefijo es pequeño y cabe completo.

Claude recibe la posición actual en `verified_reading_position`, separada de la procedencia de los pasajes. El CFI se conserva para recortar y guardar metadatos, pero no se pide al modelo que lo interprete. La política aclara que el inicio de la página actual es el final del prefijo permitido y que un pasaje temprano no determina dónde está leyendo el usuario. Si la recuperación no encuentra evidencia suficiente, el modelo debe decirlo sin afirmar que el lector no ha llegado a ese acontecimiento. Se exige conservar la secuencia de las escenas y no atribuir a un personaje diálogos que ocurrieron después de marcharse.

Cada consulta es independiente. El historial se consulta explícitamente y no se envía al modelo. Puede incluir respuestas de consultas realizadas en posiciones posteriores; las respuestas nuevas guardan su límite de lectura.

## Consumo por pregunta

Cada respuesta muestra los tokens reportados por Anthropic y el coste estimado en USD. La entrada incluye tokens normales, escrituras de caché y lecturas de caché, sin contarlos dos veces. Si faltan datos de consumo, se muestra «Consumo no registrado», también para consultas antiguas.

El panel ofrece dos modos y guarda la elección localmente:

- **Económico**, seleccionado por defecto: `claude-haiku-5-5`, con razonamiento adaptativo a esfuerzo `medium` y hasta 4.096 tokens de salida total, incluidos razonamiento y respuesta. Se habilita razonamiento para que el modelo encuentre hechos relevantes en contextos largos; todos esos tokens se incluyen en el consumo y la estimación.
- **Análisis profundo**: `claude-sonnet-5-5`, con hasta 2.048 tokens de salida y la configuración `between_tools`, compatible con Sonnet 5.5.

Ambos usan la misma recuperación local y el mismo límite CFI. Haiku sigue siendo la opción económica por defecto. No se requieren nuevos servicios, claves ni cambios en Supabase. La búsqueda funciona en el dispositivo; el conteo y la generación necesitan internet y envían únicamente la pregunta, la selección, los metadatos y los pasajes elegidos a Anthropic.

Al escribir una pregunta, tras una pausa de 600 ms se usa el endpoint gratuito de conteo de tokens del modelo elegido. El panel muestra el presupuesto orientativo antes de habilitar el envío. La estimación asume el límite completo de salida y caché nueva de cinco minutos para toda la entrada cacheable; el coste real puede ser menor si la respuesta es más corta o se reutiliza caché. Los textos demasiado cortos para caché se estiman como entrada normal. El conteo es una estimación de Anthropic, no un límite garantizado de facturación.

Cambiar la pregunta o el modelo invalida la estimación. Se cancelan los conteos obsoletos y se ignoran sus respuestas tardías. Si falla el conteo, se bloquea el envío y se permite reintentar. Al enviar se reutiliza la petición que se mostró en la estimación, sin repetir el conteo ni cambiar de modelo automáticamente. No hay una consulta de generación adicional para estimar el coste.

Tarifas verificadas el 13 de octubre de 2026, en USD por millón de tokens:

| Modelo y tamaño de entrada | Entrada | Salida | Escritura 5 min | Escritura 1 h | Lectura de caché |
|---|---:|---:|---:|---:|---:|
| Haiku 5.5, hasta 100.000 tokens | 0,10 | 0,50 | 0,125 | 0,20 | 0,01 |
| Haiku 5.5, más de 100.000 tokens | 0,50 | 2,50 | 0,625 | 1,00 | 0,05 |
| Sonnet 5.5 | 2,00 | 10,00 | 2,50 | 4,00 | 0,10 |

El umbral de Haiku cuenta toda la entrada: tokens normales, escrituras y lecturas de caché. Cuando se supera, se aplica la tarifa alta a toda esa petición, incluida la salida. El panel identifica esa tarifa antes de enviar. Los registros antiguos de Sonnet 5 siguen usando su tarifa correspondiente, con lectura de caché a 0,20 USD por millón.

El coste se guarda con la respuesta para que un cambio posterior de tarifas no altere los importes históricos. No incluye impuestos, descuentos ni ajustes de facturación de la cuenta. Para modelos sin una tarifa registrada, el coste se muestra como no disponible.

Se solicita caché efímera de cinco minutos para el bloque de pasajes recuperados. Repetir la misma pregunta desde el mismo límite puede reutilizarlo; cambiar la pregunta o avanzar puede cambiar los pasajes e impedir el acierto de caché. La estimación asume caché nueva y no promete reutilización. No se envía texto futuro para precalentar la caché. Las consultas pequeñas pueden no alcanzar el mínimo cacheable de Anthropic y se facturan como entrada normal.

El consumo y el límite se guardan en `rucio.claude_history.metadata`, y el modelo en `model`. `metadata.retrieval` registra la versión de recuperación, el tamaño del prefijo y de los pasajes, y sus identificadores, sección, capítulo y offsets en el texto extraído. No incluye el contenido de los pasajes ni del índice. Si esas columnas faltan en una instalación antigua, aplicar [el script aditivo](../tool/claude_history_metadata.sql) en Supabase. Los errores de persistencia se muestran en el panel; la respuesta y su consumo permanecen visibles durante la sesión.

## Verificación

```powershell
flutter analyze
flutter test --no-pub test/claude_retrieval_service_test.dart test/claude_service_test.dart test/claude_chat_sheet_test.dart test/claude_mode_test.dart test/reader_screen_test.dart test/reader_content_loader_test.dart
```

```powershell
cd test/javascript
node --test *.test.cjs
```

La prueba de API real es optativa y consume dos consultas breves por modelo con fragmentos ficticios: una debe responder sobre un hecho ya leído desde una posición avanzada y otra debe rechazar un spoiler futuro. No accede a libros privados ni guarda historial:

```powershell
flutter test --no-pub --dart-define-from-file=.env --dart-define=RUN_CLAUDE_LIVE_TEST=true test/claude_live_test.dart
```

Para comprobar una regresión con un EPUB privado se puede proporcionar un fixture local mediante `CLAUDE_BOOK_FIXTURE`, sin incorporarlo al repositorio. La prueba de recuperación es local y no consume API; la prueba generativa requiere además `RUN_CLAUDE_BOOK_TEST=true`, `.env` y consume dos respuestas de Haiku:

```powershell
flutter test --no-pub --dart-define=CLAUDE_BOOK_FIXTURE=.dart_tool/claude_case.json test/claude_retrieval_service_test.dart
flutter test --no-pub --dart-define-from-file=.env --dart-define=RUN_CLAUDE_BOOK_TEST=true --dart-define=CLAUDE_BOOK_FIXTURE=.dart_tool/claude_case.json test/claude_book_regression_test.dart
```

El fixture contiene `cutoffCfi`, `sections` con `href`, `text` e `isCurrent`, `location` y `boundaryLabel`. Puede incluir `title`, `author`, `percentage`, `chapterNumber` y `spineIndex`. Debe ser un prefijo ya recortado y verificado, no un EPUB entero. El caso actual comprueba la pregunta sobre la huida juvenil de Heathcliff desde el capítulo XVII.

Fuentes: [Haiku 5.5](https://platform.claude.com/docs/en/models/haiku-5-5/overview), [Sonnet 5.5](https://platform.claude.com/docs/en/models/sonnet-5-5/overview), [tarifas](https://platform.claude.com/docs/en/about-claude/pricing), [caché](https://platform.claude.com/docs/en/build-with-claude/prompt-caching), [conteo de tokens](https://platform.claude.com/docs/en/build-with-claude/token-counting).

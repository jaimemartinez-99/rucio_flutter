# Asistente de lectura de Claude

El lector adjunta el texto del EPUB en su orden de lectura, desde el comienzo hasta una posición CFI comprobada. Desde una selección, el límite es el final de esa selección. Desde el menú del lector, el límite es el comienzo de la página actual, para evitar incluir texto de esa página que todavía no se haya leído. El límite se fija al abrir el panel.

No se incluyen capítulos posteriores, índice, notas semánticas, contenido oculto ni secciones fuera del orden de lectura. Los nombres de archivos y las etiquetas del índice tampoco se envían a Claude, porque pueden adelantar acontecimientos. La ubicación se verifica contra el documento antes de extraer texto. Al retroceder y abrir otra consulta, se vuelve a extraer el contexto hasta la nueva posición. No se mantiene un registro de qué capítulos se han leído realmente: un salto hacia delante cambia el límite de la consulta.

Si falla la extracción o no se conoce la posición, la consulta se bloquea. El contexto no se trunca silenciosamente: se bloquean prefijos de más de 2.000.000 de unidades UTF-16 o peticiones de más de 950.000 tokens de entrada, comprobadas con el endpoint gratuito de conteo de Anthropic.

La política de `system` exige basarse exclusivamente en el texto adjunto para los hechos de la obra, sin recurrir al conocimiento previo para desvelar identidades o acontecimientos. También prohíbe confirmar teorías con información futura y anticipar la importancia de un personaje. El texto y la pregunta se delimitan y escapan como datos. Estas medidas reducen el riesgo; no garantizan que el modelo nunca genere un spoiler.

El capítulo numérico se obtiene de los encabezados del documento en la posición comprobada, sin usar títulos de capítulos futuros del índice. El porcentaje se calcula desde el CFI cuando hay ubicaciones generadas, o desde la posición capturada del lector. El panel muestra capítulo, porcentaje y número de secciones adjuntas. En la petición se separan `already_read_text`, con las secciones previas, y `current_section_read_prefix`, con la parte leída de la sección actual. Ambos forman el contexto permitido; un prefijo actual vacío no elimina el texto previo.

Claude recibe esa posición en `verified_reading_position`. El CFI se conserva para recortar y guardar metadatos, pero no se pide al modelo que lo interprete. La política aclara que el inicio de la página actual es el final del contexto adjunto, y que la introducción al comienzo del corpus no determina dónde está leyendo el usuario. Las preguntas sobre hechos ya leídos se responden utilizando todos los capítulos anteriores; las interpretaciones de motivos se distinguen de los hechos explícitos sin rechazar por ello toda la pregunta.

Cada consulta es independiente. El historial se consulta explícitamente y no se envía al modelo. Puede incluir respuestas de consultas realizadas en posiciones posteriores; las respuestas nuevas guardan su límite de lectura.

## Consumo por pregunta

Cada respuesta muestra los tokens reportados por Anthropic y el coste estimado en USD. La entrada incluye tokens normales, escrituras de caché y lecturas de caché, sin contarlos dos veces. Si faltan datos de consumo, se muestra «Consumo no registrado», también para consultas antiguas.

El panel ofrece dos modos y guarda la elección localmente:

- **Económico**, seleccionado por defecto: `claude-haiku-5-5`, con razonamiento adaptativo a esfuerzo `medium` y hasta 4.096 tokens de salida total, incluidos razonamiento y respuesta. Se habilita razonamiento para que el modelo encuentre hechos relevantes en contextos largos; todos esos tokens se incluyen en el consumo y la estimación.
- **Análisis profundo**: `claude-sonnet-5-5`, con hasta 2.048 tokens de salida y la configuración `between_tools`, compatible con Sonnet 5.5.

Ambos adjuntan todo el texto leído hasta el mismo límite CFI. Esta versión reduce el coste cambiando de modelo; no sustituye capítulos por resúmenes ni omite pasajes para reducir tokens.

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

Se solicita caché efímera de cinco minutos para el texto de los capítulos anteriores y para el prefijo del capítulo actual. Los capítulos anteriores permanecen en un bloque estable al avanzar dentro del capítulo. No se envía texto futuro para precalentar la caché. Las consultas pequeñas pueden no alcanzar el mínimo cacheable de Anthropic y se facturan como entrada normal.

El consumo y el límite se guardan en `rucio.claude_history.metadata`, y el modelo en `model`. Si esas columnas faltan en una instalación antigua, aplicar [el script aditivo](../tool/claude_history_metadata.sql) en Supabase. Los errores de persistencia se muestran en el panel; la respuesta y su consumo permanecen visibles durante la sesión.

## Verificación

```powershell
flutter analyze
flutter test --no-pub test/claude_service_test.dart test/claude_chat_sheet_test.dart test/claude_mode_test.dart test/reader_screen_test.dart test/reader_content_loader_test.dart
```

```powershell
cd test/javascript
node --test *.test.cjs
```

La prueba de API real es optativa y consume dos consultas breves por modelo con fragmentos ficticios: una debe responder sobre un hecho ya leído desde una posición avanzada y otra debe rechazar un spoiler futuro. No accede a libros privados ni guarda historial:

```powershell
flutter test --no-pub --dart-define-from-file=.env --dart-define=RUN_CLAUDE_LIVE_TEST=true test/claude_live_test.dart
```

Fuentes: [Haiku 5.5](https://platform.claude.com/docs/en/models/haiku-5-5/overview), [Sonnet 5.5](https://platform.claude.com/docs/en/models/sonnet-5-5/overview), [tarifas](https://platform.claude.com/docs/en/about-claude/pricing), [caché](https://platform.claude.com/docs/en/build-with-claude/prompt-caching), [conteo de tokens](https://platform.claude.com/docs/en/build-with-claude/token-counting).

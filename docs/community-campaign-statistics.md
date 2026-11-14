# Estadísticas propias de campañas de WhatsApp

Esta implementación Community registra sus propias entregas y presenta un reporte independiente. No carga modelos o servicios Enterprise ni cambia sus licencias, planes, rutas o bloqueos.

## Uso

1. Abre **Campañas → WhatsApp → Estadísticas** para comparar campañas, o usa el botón de estadísticas de una campaña iniciada.
2. Selecciona fechas de programación, una campaña y cualquiera de las etiquetas de su audiencia. Las fechas se interpretan en la zona horaria del navegador; el rango máximo es de 366 días.
3. Consulta los conteos, tasas, distribución por estado, evolución y comparación. Las gráficas tienen tooltips; la evolución puede agruparse por día, semana o mes. El modo automático adapta la agrupación al rango y al tamaño de pantalla.
4. Selecciona una tarjeta o un segmento para filtrar el detalle, busca por nombre o teléfono y revisa las causas de fallo. Los filtros quedan en la URL.
5. Los datos se consultan cada 30 segundos mientras la página está activa y visible. También puedes actualizarlos manualmente o desactivar la actualización automática.

## Definiciones

| KPI | Definición |
| --- | --- |
| Destinatarios | Registros de la audiencia guardada al iniciar cada campaña. Un contacto cuenta una vez por campaña. |
| Enviados | WhatsApp devolvió un identificador de mensaje, o confirmó un evento que prueba el envío. Incluye los fallos posteriores a la aceptación. |
| Entregados | Existe confirmación de entrega o lectura. Un recibo de lectura también prueba entrega. |
| Leídos | Existe un recibo de lectura de Meta; no se infiere lectura cuando no hay confirmación. |
| Fallidos | Error explícito del proveedor o fallo de preparación con causa registrada. |
| Pendientes | Por enviar, enviados sin entrega confirmada y envíos cuyo resultado no se pudo confirmar. |
| Tasa de entrega | Entregados / enviados aceptados. Sin denominador, muestra «Sin datos». |
| Tasa de lectura | Leídos / entregados. |
| Tasa de respuesta | Contactos con respuesta atribuida / entregados. Se muestran también las confirmadas. |
| Duración del envío | `completed_at - started_at`; no mide cuánto tarda el contacto en leer. |

La distribución muestra estados excluyentes, mientras que enviados, entregados y leídos son acumulativos. La tarjeta de enviados incluye todos los aceptados, y la de entregados incluye los leídos. La tabla puede filtrarse también por estado exacto.

Las gráficas temporales usan la fecha del evento de Meta, o la aceptación local del envío. Muestran actividad dentro del rango de las campañas seleccionadas, mientras los indicadores muestran su estado conocido actual. No se calculan clics, conversiones ni ingresos sin una fuente de atribución.

## Respuestas a campañas

Cada mensaje entrante de WhatsApp Cloud se atribuye una sola vez, con estas reglas en orden:

1. **Anuncio de Meta.** Si el mensaje trae `referral` (Click-to-WhatsApp), no se atribuye a ninguna campaña; la tarjeta del anuncio ya lo identifica.
2. **Confirmada.** El `context.id` del mensaje coincide con el identificador de Meta de un envío de campaña del mismo inbox, sin límite de tiempo: el contacto tocó un botón de respuesta rápida de la plantilla (`button`) o la citó (`quote`). Si el identificador llega con otro alcance (teléfono o BSUID), se compara su token.
3. **Probable.** Sin lo anterior: es el primer mensaje del contacto en las 24 horas siguientes a su último envío correcto (enviado, entregado o leído) de ese inbox, sin mensajes de la conversación de por medio y sin una respuesta registrada (`window`).
4. En cualquier otro caso no se atribuye.

La conversación muestra sobre el mensaje la campaña, si es confirmada o probable y cómo se dedujo. La atribución se guarda en `content_attributes.campaign_attribution` del mensaje, y la primera respuesta en `replied_at`, `reply_message_id`, `reply_conversation_id` y `reply_source` de la entrega. Una respuesta confirmada reemplaza a una probable anterior; nunca al revés. Agregar uno o dos botones de respuesta rápida a las plantillas convierte la mayoría de respuestas en confirmadas. Los botones de enlace o de llamada no generan mensaje y no permiten atribuir.

Solo se atribuyen mensajes recibidos después de desplegar esta función y envíos con identificador de Meta guardado.

## Persistencia y webhooks

- `community_campaign_reports` conserva la audiencia y sus etiquetas al iniciar el envío; editar etiquetas después no cambia el denominador.
- `community_campaign_deliveries` conserva un registro por campaña/contacto y un identificador de Meta único por inbox.
- El transporte propio reutiliza el adaptador MIT de Cloud API. Añade `biz_opaque_callback_data` con un identificador firmado de entrega para correlacionar recibos que lleguen antes de la respuesta HTTP. La firma evita vincular recibos a identificadores numéricos adivinados.
- Los recibos se buscan por cuenta e inbox y se procesan con bloqueo de fila. Recibos duplicados o fuera de orden no rebajan una lectura a enviado ni a fallido.
- Una solicitud interrumpida queda **Sin confirmación**, y no se reenvía automáticamente: Meta puede haberla aceptado. La actualización posterior del proveedor puede resolver su estado.
- La API `GET /api/v1/accounts/:account_id/community_campaign_statistics` requiere administrador y aplica el alcance de cuenta. Valida fechas, zona horaria, identificadores, estados y paginación.

## Audiencias de fallidos y aviso de actividad

En el wizard de una campaña nueva, la sección **Audiencia → Enviar a** permite elegir contactos por etiquetas o **Solo fallidos de otra campaña**. Selecciona una campaña finalizada del mismo canal y, opcionalmente, uno o varios códigos de error. Dejar los códigos vacíos incluye todos los fallos confirmados. Por ejemplo, `131048` selecciona únicamente esa causa; `131026` permite seleccionar sus fallos de entrega.

El servidor resuelve la selección por cuenta, canal y contacto. Excluye contactos bloqueados, recibos de entrega o lectura y reintentos en curso o sin confirmación de la misma cadena de campañas. Una campaña nueva conserva sus propios intentos y el historial anterior. La audiencia se vuelve a calcular y se congela al iniciar el envío; otras campañas de reintento de esa misma cadena no pueden reservar simultáneamente los mismos contactos. La configuración se conserva en `campaigns.trigger_rules.community_audience`, sin migraciones nuevas.

El wizard muestra las campañas de WhatsApp que iniciaron hoy, las coincidencias con contactos que ya tuvieron un intento hoy y las campañas pendientes programadas para el día elegido. Usa la zona horaria del navegador, incluyendo sus límites de medianoche. Antes de crear o reprogramar, consulta nuevamente estos datos y pide confirmación cuando hay actividad. El aviso ayuda a evitar duplicados; permite un reintento intencional y no representa un bloqueo diario global. Los intentos no prueban entrega y el historial ausente no puede reconstruirse.

La consulta `POST /api/v1/accounts/:account_id/community_campaign_audience` no crea campañas ni envía mensajes; requiere administrador y valida el alcance de cuenta y canal. Las estadísticas siguen siendo de solo consulta y no incluyen acciones de reenvío.

## Historial existente y despliegue

Crear y verificar un backup antes de migrar. La migración añade dos tablas independientes, sin borrar ni modificar los registros anteriores. Ejecutar `bundle exec rails community_campaigns:import_history` después de migrar y antes de arrancar workers. La tarea es idempotente y lee los datos históricos mediante un adaptador de solo lectura; no instancia modelos Enterprise.

El historial refleja las confirmaciones que quedaron guardadas. No se reconstruyen recibos que no se almacenaron ni se presupone que un envío sin identificador haya fallado. Las etiquetas históricas corresponden a las referencias que conserva la campaña al importar.

Rails y Sidekiq deben usar la misma imagen. Sidekiq espera al healthcheck de Rails, que ejecuta la preparación de base e importación antes de servir. Se conserva el backup y la imagen anterior para revertir código; las tablas añadidas no requieren eliminarse para volver atrás.

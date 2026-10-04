# Decisiones Arquitectónicas - Banco XYZ
## Exp3 - Semana 8

Este documento justifica la presencia de cada componente, define el contrato de los
eventos Kafka y establece los criterios de calidad para entradas, errores y repetición
de mensajes. Complementa a `PROPUESTA_TECNICA.md`.

---

## 1. Justificación por componente

| Componente | Propósito | Por qué existe como servicio separado |
|---|---|---|
| `config-server` | Entregar configuración centralizada | Cambiar parámetros (Kafka, Eureka, Circuit Breaker del Core) sin recompilar ni redesplegar el Core |
| `discovery-server` (Eureka) | Registro y descubrimiento de servicios | Los servicios se localizan por nombre lógico, no por IP/puerto fijo |
| `bank-core-api` | Dueño del dominio bancario y de la base de datos | Única pieza que escribe en MySQL y que publica eventos; concentra reglas de negocio y transacciones |
| `auth-server` | Emitir tokens OAuth 2.0 (JWT) | Centraliza la autenticación: ningún otro servicio guarda contraseñas ni firma tokens; los demás solo validan con la llave pública (JWKS) |
| `bff-web` | API adaptada al navegador | Respuestas completas (dashboard, historial completo) y scope `web.access` |
| `bff-mobile` | API adaptada a dispositivos móviles | Respuestas livianas (resumen, últimos movimientos) para reducir datos y latencia en red móvil; scope `mobile.access` |
| `bff-atm` | API adaptada al cajero | Solo consulta de saldo y retiro; scope `atm.access`; es el canal que origina los eventos `RETIRO_REALIZADO` del flujo principal |
| `audit-service` | Consumir eventos y dejar traza de auditoría | Desacopla la auditoría de la operación: el cliente no espera a que se audite, y la auditoría escala con consumidores propios |
| `bank-common` | Librería compartida | Una única estructura de error HTTP, un único manejo global de errores y un único contrato de evento (productor y consumidor validan contra el mismo schema) |
| Kafka (`banco.movimientos`) | Bus de eventos | Procesamiento asíncrono, 3 particiones para escalar consumidores y orden por cuenta |

### 1.1 Por qué hay tres BFF dentro de una actividad de microservicios

El patrón *Backend for Frontend* resuelve un problema distinto al del Core: **cada canal
tiene necesidades de seguridad, formato y volumen de datos diferentes**, y no conviene que
el Core las conozca.

- **Aislamiento de seguridad:** cada canal es un cliente OAuth2 distinto (`web-app`, `mobile-app`,
  `atm-app`) con su propio scope. Un token de ATM no sirve en Web ni en Mobile, y ninguno sirve
  directamente en el Core (que exige `core.access`).
- **Contrato por canal:** el Core expone un modelo único; cada BFF lo transforma (el ATM
  devuelve solo saldo; Mobile, un resumen; Web, un dashboard). El Core no se contamina con
  lógica de presentación.
- **Resiliencia por canal:** si un canal se satura o su Circuit Breaker se abre, los otros
  dos no se ven afectados.
- **Aporte al flujo de eventos:** los BFF son los **productores indirectos** del flujo
  orientado a eventos. Cuando un cliente opera (p. ej. un retiro en el ATM), el BFF invoca
  al Core, el Core confirma la transacción y publica el evento que consume la auditoría:

```text
Cliente -> BFF (canal, token OAuth2, validación) -> Core API (transacción) -> COMMIT
        -> evento en Kafka -> audit-service
```

Los BFF **no acceden a MySQL ni publican en Kafka**: la persistencia y la emisión de
eventos están encapsuladas en el Core, lo que garantiza que un evento solo existe si la
transacción fue confirmada.

---

## 2. Matriz de eventos

| Evento | Emisor | Tópico / Key | Consumidor | Cuándo se emite |
|---|---|---|---|---|
| `DEPOSITO_REALIZADO` | `bank-core-api` | `banco.movimientos` / `cuentaId` | `audit-service` (grupo `banco-auditoria`) | Después del COMMIT de un depósito |
| `RETIRO_REALIZADO` | `bank-core-api` | `banco.movimientos` / `cuentaId` | `audit-service` | Después del COMMIT de un retiro |
| `COMPRA_REALIZADA` | `bank-core-api` | `banco.movimientos` / `cuentaId` | `audit-service` | Después del COMMIT de una compra |

Cabeceras Kafka: `eventId`, `eventType`, `schemaVersion`.

### 2.1 Estructura esperada (contrato v1.0)

Definición formal: `bank-common/src/main/resources/contracts/movimiento-evento.v1.schema.json`
(JSON Schema draft-07).

| Campo | Tipo | Obligatorio | Regla |
|---|---|---|---|
| `eventId` | string (UUID) | Sí | Único por evento; clave de idempotencia |
| `version` | string | Sí | Patrón `1.x` |
| `tipoEvento` | enum | Sí | `DEPOSITO_REALIZADO`, `RETIRO_REALIZADO`, `COMPRA_REALIZADA` |
| `movimientoId` | entero | Sí | ≥ 1 |
| `cuentaId` | entero | Sí | ≥ 1; es la key de la partición |
| `tipoMovimiento` | enum | Sí | `deposito`, `retiro`, `compra` (coherente con `tipoEvento`) |
| `monto` | número | Sí | Positivo en depósito; negativo en retiro y compra |
| `saldoResultante` | número | Sí | ≥ 0 |
| `fechaMovimiento` | string `date` | Sí | ISO-8601 |
| `fechaEvento` | string `date-time` | Sí | ISO-8601 UTC |

Ejemplo:

```json
{
  "eventId": "3f2b8c1e-5d4a-4c3b-9a1e-0d2f6b7a8c90",
  "version": "1.0",
  "tipoEvento": "RETIRO_REALIZADO",
  "movimientoId": 13,
  "cuentaId": 101,
  "tipoMovimiento": "retiro",
  "monto": -100.00,
  "saldoResultante": 4850.00,
  "fechaMovimiento": "2026-09-30",
  "fechaEvento": "2026-09-30T15:04:05.123Z"
}
```

### 2.2 Reglas de evolución del contrato

| Cambio | ¿Compatible? | Acción |
|---|---|---|
| Agregar un campo **opcional** | Sí | Se mantiene `version` 1.x; `additionalProperties` está permitido |
| Agregar un valor a `tipoEvento` | No para consumidores v1 | Publicar schema v1.1 y actualizar consumidores primero |
| Quitar o renombrar un campo requerido | No | Nuevo schema `v2` y `version` 2.x; convivencia de ambos durante la migración |
| Cambiar el tipo de un campo | No | Ídem |

Regla de despliegue: **primero se actualizan los consumidores, después el productor**.

### 2.3 Dónde se valida el contrato

- **Productor** (`KafkaMovimientoPublisher`): valida antes de enviar; un evento inválido no se publica.
- **Consumidor** (`MovimientoAuditConsumer`): valida al recibir; un mensaje inválido se rechaza y se registra (`mensaje RECHAZADO por contrato`) sin bloquear la partición.
- Pruebas: `MovimientoEventoContratoTest` (bank-common) y `MovimientoAuditConsumerTest` (audit-service).

---

## 3. Idempotencia y deduplicación

Kafka garantiza entrega *al menos una vez*: un reintento, un rebalanceo o un reinicio antes
del commit del offset pueden entregar el mismo mensaje dos veces.

| Nivel | Mecanismo |
|---|---|
| Productor | `enable.idempotence=true` + `acks=all`: el cliente Kafka no duplica por reintentos internos |
| Evento | Cada evento lleva un `eventId` UUID único generado en el Core |
| Consumidor | `ProcessedEventStore.registrarSiEsNuevo(eventId)`: si ya fue visto, se omite y se registra `evento DUPLICADO omitido` |
| Fallo de proceso | Si el procesamiento lanza excepción, se hace `olvidar(eventId)` para que la reentrega sí se procese |

Limitación declarada: el almacén de `eventId` es en memoria (ventana 24 h, máx. 100.000
eventos). Para producción se reemplaza por una tabla con `UNIQUE(event_id)` o Redis
implementando la misma interfaz, sin tocar el consumidor.

---

## 4. Criterios de calidad

### 4.1 Entradas

- Se validan con Bean Validation **en el controlador, antes de abrir la transacción**
  (`@Valid`, `@Positive`, `@Digits`, `@Pattern`, `@Size`).
- Reglas del movimiento: cuenta positiva; tipo ∈ {deposito, retiro, compra}; monto > 0 con
  máximo 13 enteros y 2 decimales; descripción ≤ 255 caracteres.
- Las rutas con `{cuentaId}` exigen un valor positivo; un valor no numérico responde 400.
- Una solicitud inválida **no toca la base de datos ni genera eventos**.

### 4.2 Errores HTTP (formato único en Core y BFF)

```json
{
  "timestamp": "2026-09-30T12:00:00",
  "status": 400,
  "error": "VALIDATION_ERROR",
  "mensaje": "La solicitud contiene datos invalidos",
  "path": "/api/core/movimientos",
  "detalles": [ { "campo": "monto", "mensaje": "El monto debe ser mayor que cero" } ]
}
```

| HTTP | `error` | Origen |
|---|---|---|
| 400 | `VALIDATION_ERROR`, `JSON_INVALIDO`, `PARAMETRO_INVALIDO`, `BAD_REQUEST`, `SOLICITUD_RECHAZADA` | Validación / formato |
| 401 | `NO_AUTENTICADO`, `CREDENCIALES_INVALIDAS` | Seguridad |
| 403 | `ACCESO_DENEGADO` | Token con scope de otro canal |
| 404 | `NOT_FOUND` | Cuenta inexistente |
| 409 | `SALDO_INSUFICIENTE` | Regla de negocio |
| 503 | `CORE_NO_DISPONIBLE` | Circuit Breaker abierto, timeout o caída del Core |
| 500 | `INTERNAL_SERVER_ERROR` | Error no controlado (sin exponer detalles internos) |

Implementación: `CommonExceptionHandler` (bank-common, prioridad baja) + un handler de
dominio por servicio (prioridad alta). Los 401/403 de seguridad usan `ApiSecurityErrorHandlers`.

### 4.3 Separación de capas en las APIs

```text
Request DTO  --(Controller, @Valid)-->  Service  --(Mapper)-->  Entidad JPA
Entidad JPA  --(Mapper, dentro del Service)-->  Response DTO  -->  Controller
```

Las entidades JPA (`Cuenta`, `Movimiento`) nunca salen de la capa de servicio; los
controladores solo reciben y devuelven DTOs. Los eventos Kafka son un tercer modelo
(`MovimientoEvento`), independiente de la entidad.

### 4.4 Repetición de mensajes

Ver sección 3. Mensajes inválidos: se rechazan y registran sin reintento. Mensajes
duplicados: se omiten y registran.

---

## 5. Matriz de tolerancia a fallos

| Servicio | Dependencia protegida | Mecanismo | Comportamiento ante falla |
|---|---|---|---|
| `bff-atm` | Core API (consulta y **retiro**) | Circuit Breaker `coreApi` + Retry (solo lecturas) + Bulkhead (10 concurrentes) + timeouts HTTP (2 s / 3 s) | 503 `CORE_NO_DISPONIBLE`; con el circuito abierto responde sin esperar |
| `bff-web` | Core API | Circuit Breaker `coreApi` + Retry + Bulkhead + timeouts | 503 `CORE_NO_DISPONIBLE` |
| `bff-mobile` | Core API | Circuit Breaker `coreApi` + Retry + Bulkhead + timeouts | 503 `CORE_NO_DISPONIBLE` |
| `bank-core-api` | Kafka (publicación) | Circuit Breaker `kafkaPublisher` + `max.block.ms=3000` + productor idempotente | La operación bancaria ya confirmada **sigue respondiendo éxito**: la publicación se hace en un hilo propio (ver 5.2) y el fallo se registra en el Core |
| `audit-service` | Mensajes inválidos / duplicados | Validación de contrato + idempotencia | Se omiten sin detener el consumo |

Las excepciones funcionales (404, 409, 4xx) están en `ignore-exceptions`: no cuentan como
falla de infraestructura ni abren el circuito. La configuración del Core se centraliza en
`config-repo/bank-core-api.properties`.

### 5.1 Escenarios de fallo reproducibles

| # | Escenario | Cómo reproducirlo | Resultado esperado |
|---|---|---|---|
| F1 | Core caído, canal ATM | Detener `bank-core-api` y consultar `GET /api/atm/saldo/101` 3 veces | 503 `CORE_NO_DISPONIBLE`; el circuito pasa a `OPEN` (`/actuator/health`) |
| F2 | Core caído, canal Web / Mobile | Detener `bank-core-api` y llamar `GET /api/web/cuentas/101` o `GET /api/mobile/cuentas/101` 3 veces | 503 `CORE_NO_DISPONIBLE`; circuito `OPEN` en ese BFF |
| F3 | Recuperación | Esperar 10 s y levantar el Core | `OPEN` → `HALF_OPEN` → `CLOSED` |
| F4 | Cuenta inexistente | `GET /api/atm/saldo/999999` | 404 `NOT_FOUND`; el circuito **no** se abre |
| F5 | Kafka caído | `docker compose stop kafka` y hacer un retiro por el BFF ATM | El retiro responde 200 de inmediato; en el log del Core aparece `Kafka no disponible: evento ... no publicado` |
| F6 | Mensaje inválido en el tópico | Publicar `{"hola":"mundo"}` en `banco.movimientos` | `audit-service`: `mensaje RECHAZADO por contrato`; el consumo continúa |
| F7 | Mensaje duplicado | Publicar dos veces el mismo JSON válido | `audit-service`: una vez `evento procesado`, otra `evento DUPLICADO omitido` |
| F8 | Datos de entrada inválidos | `POST /api/atm/retiros` con `{"cuentaId":101,"monto":-5}` | 400 `VALIDATION_ERROR` con `detalles` |
| F9 | Sin token / token de otro canal | Llamar un endpoint sin `Authorization` o con token Web en ATM | 401 / 403 con el formato de error estándar |
| F10 | Authorization Server caído | `docker compose stop auth-server` y llamar un BFF con token aún vigente (el BFF ya no podrá renovar su token hacia el Core cuando expire) | El BFF responde 503 `CORE_NO_DISPONIBLE` al no poder obtener token; el Core sigue validando tokens vigentes con la llave pública cacheada |

### 5.2 Publicación asíncrona de eventos

La publicación en Kafka ocurre después del COMMIT y **en un hilo propio** (`kafka-publisher`, un solo hilo para conservar el orden y una cola acotada de 1000 eventos). Así el hilo de la petición HTTP nunca espera a Kafka: aunque el broker esté caído y el productor bloquee hasta `max.block.ms=3000`, el BFF recibe su respuesta de inmediato, sin competir con su timeout de lectura (3 s).

Consecuencia aceptada: si Kafka está caído, el evento no se publica (se registra `Kafka no disponible: evento ... no publicado`; si la cola se llena, el mensaje lo indica). El patrón Outbox, previsto como mejora, permitiría reenviar esos eventos (ver `PROPUESTA_TECNICA.md`, sección 22).

Pruebas automáticas: `mvn test` ejecuta `MovimientoEventoContratoTest` y
`MovimientoAuditConsumerTest` (contrato, mensaje inválido, duplicados).

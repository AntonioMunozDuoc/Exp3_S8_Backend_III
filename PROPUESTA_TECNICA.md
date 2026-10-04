# Propuesta Técnica
## Banco XYZ - Arquitectura de Microservicios, Resiliencia, Eventos, OAuth2 y Contenedores
### Exp3 - Semana 8

## 1. Introducción

La solución de Banco XYZ evoluciona desde la arquitectura Backend for Frontend (BFF) implementada en semanas anteriores hacia una arquitectura de microservicios con mecanismos de configuración centralizada, descubrimiento de servicios, tolerancia a fallos y comunicación asíncrona orientada a eventos.

La propuesta mantiene tres canales especializados:

- Web;
- Mobile;
- Cajero Automático (ATM).

Cada canal conserva su propio BFF y su esquema de seguridad, mientras que el `bank-core-api` centraliza las reglas principales del dominio bancario y la persistencia.

Durante Semana 7 se incorporan principalmente:

- Spring Cloud Config;
- Eureka Service Discovery;
- Resilience4j;
- Apache Kafka;
- un servicio consumidor de auditoría;
- escalabilidad mediante particiones y grupos de consumidores.

Durante Semana 8 se incorporan principalmente:

- un Authorization Server OAuth 2.0 propio (`auth-server`); el Core y los tres BFF pasan a ser Resource Servers;
- Retry, Bulkhead y timeouts de Resilience4j en los tres BFF, además del Circuit Breaker;
- un `Dockerfile` por microservicio y un único `docker-compose.yaml` que levanta toda la plataforma (11 contenedores).

---

## 2. Objetivo técnico

El objetivo es fortalecer la arquitectura del sistema Banco XYZ incorporando mecanismos que permitan:

- desacoplar responsabilidades entre servicios;
- centralizar configuraciones;
- registrar y descubrir servicios;
- responder de forma controlada ante fallas;
- publicar eventos bancarios de manera asíncrona;
- procesar eventos en servicios independientes;
- distribuir carga entre múltiples consumidores;
- mantener seguridad diferenciada por canal;
- delegar la autenticación en un Authorization Server y validar tokens JWT en cada servicio;
- empaquetar y desplegar toda la plataforma de forma portable con Docker y Docker Compose.

---

## 3. Arquitectura general

La arquitectura está compuesta por los siguientes módulos:

```text
bank-common        (librería compartida: errores HTTP, contrato de eventos, cliente OAuth2, ResilientCall)
config-server
discovery-server
auth-server
bank-core-api
bff-web
bff-mobile
bff-atm
audit-service
```

Flujo general:

```text
Cliente
   |  (1. token client_credentials  ->  auth-server :9000)
   |  (2. Authorization: Bearer <token>)
   +-----------------------------+
   |             |               |
 BFF Web      BFF Mobile      BFF ATM
  :8081          :8082          :8083
   |             |               |
   +-------------+---------------+
                 |
   Resilience4j (Circuit Breaker coreApi + Retry + Bulkhead + timeouts)
                 |
                 v
          Bank Core API :8080   (Resource Server, scope core.access)
              /       \
             /         \
          MySQL        Kafka
                       :9092
                         |
                         v
               banco.movimientos
                3 particiones
                         |
                         v
          Audit Service x2 (grupo banco-auditoria)
```

Servicios de soporte:

```text
Config Server   -> :8888
Eureka Server   -> :8761
Auth Server     -> :9000
MySQL           -> :3307 (host) / :3306 (red interna)
Kafka           -> :9092 (host) / :9094 (red interna)
```

---

## 4. Backend for Frontend

La solución mantiene tres BFF independientes.

### BFF Web

Orientado a interfaces de navegador y respuestas más completas.

```text
http://localhost:8081
```

Scope:

```text
web.access
```

### BFF Mobile

Orientado a respuestas más ligeras para dispositivos móviles.

```text
http://localhost:8082
```

Scope:

```text
mobile.access
```

### BFF ATM

Orientado a operaciones específicas de cajero automático.

```text
http://localhost:8083
```

Scope:

```text
atm.access
```

Los BFF no acceden directamente a MySQL. La persistencia permanece encapsulada en `bank-core-api`.

En Docker Compose los BFF atienden por HTTP dentro de la red `banco-net`; el HTTPS es configurable con `SSL_ENABLED` (ver sección 16.6).

### Justificación de los BFF dentro de la arquitectura

Cada canal tiene necesidades distintas de seguridad, formato y volumen de datos, y el Core no debe
conocerlas. Los BFF aportan:

- **aislamiento de seguridad:** cada canal se autentica con su propio cliente OAuth2 y recibe un scope distinto (`web.access`, `mobile.access`, `atm.access`);
- **contrato por canal:** Web recibe respuestas completas, Mobile respuestas livianas y ATM solo saldo y retiro;
- **resiliencia por canal:** la falla o saturación de un canal no afecta a los otros;
- **aporte al flujo de eventos:** son la puerta de entrada de las operaciones que, una vez
  confirmadas por el Core, originan los eventos de Kafka (`Cliente -> BFF -> Core -> COMMIT -> Kafka -> Auditoría`).

El detalle por componente está en `DECISIONES_ARQUITECTONICAS.md`.

---

## 5. Core API

El módulo `bank-core-api` centraliza la lógica bancaria.

Responsabilidades principales:

- consulta de cuentas;
- consulta de movimientos;
- registro de depósitos;
- registro de retiros;
- registro de compras;
- actualización de saldos;
- validación de saldo disponible;
- persistencia mediante Spring Data JPA;
- publicación de eventos de movimientos.

Base de datos:

```text
banco_xyz_core
```

Tablas principales:

```text
cuentas
movimientos
```

---

## 6. Configuración centralizada

Se incorpora `config-server` utilizando Spring Cloud Config Server.

Puerto:

```text
8888
```

El Core API consume propiedades desde:

```text
config-repo/bank-core-api.properties
```

Entre las propiedades centralizadas se encuentran:

- parámetros del productor Kafka (serializadores, `acks=all`, idempotencia, timeouts);
- tópico de movimientos;
- Circuit Breaker `kafkaPublisher` de Resilience4j;
- propiedades de observabilidad.

Esto permite separar parte de la configuración operacional del código de la aplicación. Los valores que dependen del entorno (hosts de base de datos, Kafka, Eureka y Auth Server) se inyectan por variables de entorno en Docker Compose (ver sección 16.A).

---

## 7. Service Discovery

Se incorpora `discovery-server` mediante Netflix Eureka.

Puerto:

```text
8761
```

El `bank-core-api` se registra dinámicamente como:

```text
BANK-CORE-API
```

Durante las pruebas se verificó su estado:

```text
UP
```

Este mecanismo permite registrar servicios y facilita una arquitectura preparada para descubrimiento dinámico.

---

## 8. Tolerancia a fallos con Resilience4j

La tolerancia a fallos se aplica a **todos los servicios críticos**:

| Servicio | Dependencia protegida | Circuit Breaker |
|---|---|---|
| BFF ATM | Core API (saldo y retiro) | `coreApi` |
| BFF Web | Core API | `coreApi` |
| BFF Mobile | Core API | `coreApi` |
| Bank Core API | Publicación en Kafka | `kafkaPublisher` (configurado en `config-repo/bank-core-api.properties`) |

Además de los Circuit Breakers, los BFF aplican los otros patrones de Resilience4j vistos en la asignatura
(`ResilientCall`, módulo `bank-common`), con la composición `CircuitBreaker( Retry( Bulkhead( llamada ) ) )`:

| Patrón | Configuración | Justificación |
|---|---|---|
| Retry | 3 intentos, 300 ms; solo timeout, conexión, HTTP 5xx y falla al obtener token | Absorbe fallos transitorios sin molestar al cliente |
| Retry (exclusión) | El retiro (POST) **no** se reintenta | Un POST no idempotente podría duplicar el movimiento |
| Bulkhead | 10 llamadas concurrentes al Core, espera máxima 100 ms | Aísla al BFF: si el Core se vuelve lento, el exceso se rechaza en vez de agotar los hilos |
| Timeouts HTTP | 2 s de conexión y 3 s de lectura | Una llamada colgada se contabiliza como falla |

Los escenarios de fallo reproducibles están en `DECISIONES_ARQUITECTONICAS.md` (sección 5.1).

A continuación se detalla el Circuit Breaker del BFF ATM, cuyo perfil es idéntico en Web y Mobile.

El BFF ATM incorpora un Circuit Breaker denominado:

```text
coreApi
```

El objetivo es evitar que las fallas de comunicación con el Core API provoquen respuestas descontroladas o llamadas repetitivas innecesarias.

Configuración utilizada:

```text
sliding-window-type: COUNT_BASED
sliding-window-size: 3
minimum-number-of-calls: 3
failure-rate-threshold: 50
wait-duration-in-open-state: 10s
permitted-number-of-calls-in-half-open-state: 1
automatic-transition-from-open-to-half-open-enabled: true
```

Cuando el Core API no está disponible, el BFF ATM responde de manera controlada:

```text
HTTP 503 Service Unavailable
CORE_NO_DISPONIBLE
```

El Circuit Breaker recorre el siguiente ciclo (Semana 7 documenta los cuatro estados; en Semana 8 se evidencian el estado `CLOSED`, los reintentos, el rechazo de llamadas con el circuito abierto y la recuperación automática):

```text
CLOSED
   |
   v
OPEN
   |
   v
HALF_OPEN
   |
   v
CLOSED
```

También se configuraron excepciones funcionales que no deben contabilizarse como fallas de infraestructura, por ejemplo:

```text
AtmRecursoNoEncontradoException
AtmSaldoInsuficienteException
```

De esta forma, una cuenta inexistente continúa respondiendo con su error funcional y no abre el Circuit Breaker.

### Publicación en Kafka (`kafkaPublisher`)

El Core protege la publicación de eventos con el Circuit Breaker `kafkaPublisher` y con `max.block.ms=3000`. El evento se publica después del COMMIT, por lo que un fallo de Kafka no revierte la operación bancaria: el Core registra `Kafka no disponible: evento ... no publicado`.

La publicación se ejecuta en un hilo propio (`kafka-publisher`, un solo hilo y cola acotada de 1000 eventos), de modo que el hilo de la petición HTTP nunca espera a Kafka. Con Kafka detenido, el retiro responde de inmediato `HTTP 200` y el Core registra el fallo de publicación en segundo plano. El evento no publicado se pierde; el patrón Outbox (sección 22) permitiría reenviarlo.

---

## 9. Arquitectura orientada a eventos

Para la mensajería asíncrona se seleccionó Apache Kafka.

La razón principal es que Kafka permite:

- desacoplar productores y consumidores;
- conservar eventos en un tópico;
- trabajar con particiones;
- distribuir procesamiento mediante Consumer Groups;
- escalar consumidores horizontalmente.

En Semana 8 Kafka se ejecuta como un contenedor más de `docker-compose.yaml` (imagen `apache/kafka:4.3.1`). Para el desarrollo local sin Docker se mantiene `docker-compose.kafka.yml`.

Broker:

```text
localhost:9092   (desde el host)
kafka:9094       (desde los contenedores)
```

---

## 10. Tópico y eventos

Tópico principal:

```text
banco.movimientos
```

Configuración:

```text
Particiones: 3
Factor de replicación: 1
```

Tipos de eventos implementados:

```text
DEPOSITO_REALIZADO
RETIRO_REALIZADO
COMPRA_REALIZADA
```

Contrato utilizado:

```text
MovimientoEvento  (versión 1.0)
contracts/movimiento-evento.v1.schema.json  (JSON Schema draft-07, módulo bank-common)
```

El productor valida el evento contra el schema antes de publicarlo y el consumidor lo valida al
recibirlo. Las reglas de evolución del contrato están en `DECISIONES_ARQUITECTONICAS.md`.

Campos principales:

```text
eventId
version
tipoEvento
movimientoId
cuentaId
tipoMovimiento
monto
saldoResultante
fechaMovimiento
fechaEvento
```

Ejemplo validado:

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

---

## 11. Patrón de publicación de eventos

La solución utiliza un enfoque de notificación de eventos posterior a la confirmación de la transacción.

Dentro de `MovimientoService` se publica primero un evento interno mediante:

```text
ApplicationEventPublisher
```

El componente `KafkaMovimientoPublisher` escucha ese evento con:

```text
@TransactionalEventListener(
    phase = TransactionPhase.AFTER_COMMIT
)
```

Después del COMMIT se envía el evento a Kafka, en un hilo propio para que la respuesta al cliente no dependa de la disponibilidad del broker.

Flujo:

```text
Operación bancaria
      |
      v
Validación
      |
      v
Persistencia MySQL
      |
      v
COMMIT exitoso
      |
      v
Evento interno
      |
      v
KafkaMovimientoPublisher
      |
      v
banco.movimientos
```

Esta decisión evita publicar el evento antes de que la operación bancaria haya sido confirmada en la base de datos.

---

## 12. Clave Kafka y orden de eventos

Cada evento utiliza como clave:

```text
cuentaId
```

Ejemplo:

```text
Key: 101
```

El uso de `cuentaId` permite que los eventos asociados a una misma cuenta sean dirigidos consistentemente a una partición, conservando su orden relativo dentro de ella.

Al mismo tiempo, diferentes cuentas pueden distribuirse entre las distintas particiones.

---

## 13. Consumidor de auditoría

Se incorpora un nuevo módulo:

```text
audit-service
```

Su responsabilidad es consumir de manera asíncrona los eventos del tópico:

```text
banco.movimientos
```

Grupo:

```text
banco-auditoria
```

El consumidor procesa:

- key;
- partition;
- offset;
- payload.

Ejemplo validado:

```text
AUDITORIA [auditoria-2] evento procesado: eventId=842ddc4b-8934-48dd-a662-73d1215cefbb,
tipo=RETIRO_REALIZADO, cuenta=101, monto=-100, saldo=4690.00, key=101, particion=2, offset=2
```

El servicio utiliza `StringDeserializer` para consumir el JSON producido por el Core API y,
por cada mensaje:

1. valida el contrato JSON Schema (los mensajes inválidos se rechazan y registran, sin reintento);
2. aplica **idempotencia** por `eventId` (`ProcessedEventStore`): los duplicados se omiten y se registran;
3. procesa el evento y deja la traza de auditoría.

El productor del Core usa `enable.idempotence=true` y `acks=all`. El almacén de `eventId` es en
memoria (ventana de 24 h); para producción se reemplaza por una tabla con `UNIQUE(event_id)`.

---

## 14. Escalabilidad horizontal

El tópico `banco.movimientos` posee tres particiones.

Se ejecutaron simultáneamente dos instancias de `audit-service` dentro del mismo grupo:

```text
banco-auditoria
```

Kafka realizó automáticamente un rebalanceo.

Distribución observada:

```text
Consumidor 1 -> particiones 0 y 1
Consumidor 2 -> partición 2
```

La inspección del grupo mostró dos `CONSUMER-ID` distintos y las particiones distribuidas entre ambos consumidores.

Esto demuestra que el procesamiento puede escalar horizontalmente al agregar nuevas instancias del mismo consumidor.

---

## 15. Prueba funcional completa

Se ejecutó un retiro real mediante el BFF ATM con un token OAuth2 del canal.

Datos:

```text
Cuenta: 101
Monto retirado: 100
Saldo disponible resultante: 4590.00
Estado: APROBADO
```

El flujo observado fue:

```text
BFF ATM
   |
   v
Bank Core API
   |
   +--> MySQL
   |
   +--> AFTER_COMMIT
           |
           v
          Kafka
           |
           v
   banco.movimientos
           |
           v
     audit-service
```

El Core registró la publicación:

```text
Evento Kafka publicado: eventId=76f78555-efff-404a-b73e-7e0f9981dc84,
tipo=RETIRO_REALIZADO, cuenta=101, topic=banco.movimientos, particion=2, offset=3
```

Posteriormente, `audit-service` procesó el mismo evento (`AUDITORIA [auditoria-2] evento procesado`, saldo=4590.00).

Además, el script `scripts/smoke-test` ejecuta 14 verificaciones (autenticación, protección de BFF y Core, retiro, monto negativo, saldo insuficiente y cuenta inexistente) con resultado `14 OK, 0 con fallo`.

---

## 16. Seguridad con OAuth 2.0

### 16.1 Arquitectura de seguridad

La emisión de tokens se centraliza en un **Authorization Server** (`auth-server`, Spring Authorization Server, puerto 9000).
Los BFF y el Core API dejan de emitir o gestionar credenciales propias y pasan a ser **Resource Servers** que solo validan el token
(delegación de seguridad, tal como plantea la guía de la semana).

```text
Canal ──(client_credentials)──► auth-server ──► access_token (JWT RS256)
Canal ──(Bearer token)────────► BFF  (valida firma vía JWKS, issuer, expiración y scope)
BFF   ──(client_credentials)──► auth-server
BFF   ──(Bearer token)────────► Core API (exige scope core.access)
```

### 16.2 Flujo elegido: `client_credentials`

Los consumidores del sistema (aplicación Web, aplicación Mobile, cajero ATM y los propios BFF) son **clientes de sistema** sin un usuario
interactivo en el backend, por lo que el grant adecuado es `client_credentials`. El flujo `authorization_code` queda como evolución
cuando exista un login de usuario final (ver sección 22).

### 16.3 Clientes y scopes

| Cliente | Uso | Scope |
|---|---|---|
| `web-app` | Canal Web → BFF Web | `web.access` |
| `mobile-app` | Canal Mobile → BFF Mobile | `mobile.access` |
| `atm-app` | Cajero → BFF ATM | `atm.access` |
| `bff-web`, `bff-mobile`, `bff-atm` | BFF → Core API | `core.access` |

Un token de un canal **no** sirve en otro canal ni en el Core (mínimo privilegio).

### 16.4 Configuración

- `auth-server`: clientes y `issuer` declarados en `application.properties`; los secretos se inyectan por variable de entorno.
- Resource Servers (Core y BFF): `spring.security.oauth2.resourceserver.jwt.jwk-set-uri` (llaves públicas) e `issuer-uri` (validación del claim `iss`).
- El `issuer` es **fijo** (`AUTH_ISSUER`), por eso el mismo token es válido desde el host y desde la red interna de Docker.
- Cliente OAuth2 de los BFF: `ClientCredentialsTokenProvider` (módulo `bank-common`) obtiene el token con autenticación `client_secret_basic`,
  lo mantiene en caché hasta 30 s antes de expirar y lo agrega como `Authorization: Bearer` en cada llamada al Core.
  Una falla del Authorization Server se trata como falla de infraestructura (la contabiliza el Circuit Breaker y el BFF responde 503).

### 16.5 Comportamiento validado

| Solicitud | Resultado |
|---|---|
| Sin token | 401 `NO_AUTENTICADO` |
| Token adulterado | 401 |
| Token con scope de otro canal | 403 `ACCESO_DENEGADO` |
| Token correcto | 200 |
| Core con token de canal (sin `core.access`) | 403 |
| Credenciales de cliente incorrectas en `/oauth2/token` | 401 `invalid_client` |

Se prueba con `scripts/smoke-test.sh` (o `.ps1`).

### 16.6 Otras medidas

- HTTPS configurable en los BFF (`SSL_ENABLED`); en Docker el tráfico queda dentro de la red privada `banco-net`.
- Sesiones sin estado (`STATELESS`) y CSRF deshabilitado (API pura con token).
- Imágenes Docker con usuario no root; secretos fuera del código (variables de entorno / `.env`).
- Limitación académica: los secretos de cliente usan `{noop}` y las llaves RSA se generan al iniciar el `auth-server`
  (al reiniciarlo los tokens previos dejan de ser válidos). En producción: secretos cifrados (BCrypt), llaves persistentes y HTTPS extremo a extremo.

---

## 16.A Contenedores y orquestación

### Dockerización

Cada microservicio tiene un `Dockerfile` multi-etapa (compilación con Maven + JRE 21 liviano), usuario no root y puerto expuesto.
El contexto de build es la raíz del repositorio porque los módulos dependen del POM padre y de `bank-common`.

### docker-compose.yaml

Define 11 contenedores en la red `banco-net`:

```text
mysql, kafka                                  (infraestructura)
config-server, discovery-server, auth-server  (plataforma)
bank-core-api, bff-web, bff-mobile, bff-atm   (negocio)
audit-service-1, audit-service-2              (eventos, mismo grupo banco-auditoria)
```

- Orden de arranque garantizado con `healthcheck` + `depends_on: condition: service_healthy`.
- `restart: unless-stopped` para reinicio automático ante fallos.
- Volúmenes persistentes para MySQL y Kafka.
- Kafka con dos listeners: `INTERNAL` (`kafka:9094`, para contenedores) y `EXTERNAL` (`localhost:9092`, para el host).
- Datos base cargados con `data.sql` (activado solo con `SQL_INIT_MODE=always`).
- Los valores que dependen del entorno (hosts de BD, Kafka, Eureka, Auth) se inyectan por variables de entorno;
  la configuración funcional compartida (Kafka, Resilience4j) permanece en el Config Server.

---

## 17. Manejo de errores

La solución mantiene manejo controlado de errores funcionales y de infraestructura.

Ejemplos:

```text
400 Bad Request
401 Unauthorized
404 Not Found
409 Conflict
503 Service Unavailable
```

Ejemplos de códigos propios:

```text
SALDO_INSUFICIENTE
CORE_NO_DISPONIBLE
```

Todos los servicios responden con la **misma estructura de error** (`timestamp`, `status`, `error`,
`mensaje`, `path`, `detalles`), definida en el módulo `bank-common`:

- `CommonExceptionHandler` (`@RestControllerAdvice`, prioridad baja) resuelve validaciones, JSON inválido,
  parámetros con tipo incorrecto, credenciales, Core no disponible (503), errores de protocolo HTTP y el fallback 500.
- Cada servicio mantiene un handler de dominio (prioridad alta) para sus excepciones propias.
- `ApiSecurityErrorHandlers` entrega los 401/403 de seguridad en el mismo formato JSON.

### Validaciones de entrada y separación de capas

Las solicitudes se validan con Bean Validation en el controlador, **antes de abrir la transacción**
(`@Valid`, `@Positive`, `@Digits`, `@Pattern`, `@Size`). Los controladores solo manejan DTOs de
entrada y de salida; las entidades JPA no salen de la capa de servicio.

---

## 18. Observabilidad

Spring Boot Actuator permite consultar el estado de los servicios.

Ejemplo:

```text
/actuator/health
```

En el BFF ATM también se utilizaron métricas de Resilience4j para verificar los estados del Circuit Breaker:

```text
resilience4j.circuitbreaker.state
resilience4j.circuitbreaker.calls
resilience4j.circuitbreaker.failure.rate
resilience4j.circuitbreaker.not.permitted.calls
```

El estado del circuito `coreApi` se consulta con la métrica `resilience4j.circuitbreaker.state` (valores `closed`, `open` y `half_open`); el endpoint `/actuator/health` del BFF no lista el componente `coreApi`.

---

## 19. Compilación y validación

Se ejecutó:

```powershell
.\mvnw.cmd clean verify
```

Resultado:

```text
Banco XYZ - Exp3 Semana 8 ......................... SUCCESS
Banco XYZ - Common ................................ SUCCESS
Banco XYZ - Config Server ......................... SUCCESS
Banco XYZ - Discovery Server ...................... SUCCESS
Banco XYZ - Authorization Server (OAuth 2.0) ...... SUCCESS
Banco XYZ - Core API .............................. SUCCESS
Banco XYZ - BFF Web ............................... SUCCESS
Banco XYZ - BFF Mobile ............................ SUCCESS
Banco XYZ - BFF ATM ............................... SUCCESS
Banco XYZ - Audit Service ......................... SUCCESS

BUILD SUCCESS
```

Esto valida la compilación integrada del POM padre y de los nueve módulos del proyecto. Las pruebas unitarias cubren el contrato de eventos, `ResilientCall` (Retry y Bulkhead), el cliente OAuth2 (`ClientCredentialsTokenProvider`) y el consumidor de auditoría (mensaje inválido y duplicados).

---

## 20. Decisiones técnicas

### Kafka en lugar de JMS

Se seleccionó Kafka porque el escenario requiere comunicación orientada a eventos y permite demostrar particionamiento, retención de eventos y escalabilidad mediante grupos de consumidores.

### Tres particiones

El tópico utiliza tres particiones para permitir distribución de carga entre consumidores.

### `cuentaId` como key

Permite mantener juntos los eventos de una misma cuenta y conservar su orden relativo.

### AFTER_COMMIT

Evita publicar un evento de negocio antes de que la operación haya sido confirmada en MySQL.

### Audit Service desacoplado

El consumidor no forma parte del Core API. Esto permite que el procesamiento de auditoría evolucione y escale de manera independiente.

---

## 21. Limitaciones del entorno de desarrollo

La implementación de Semana 8 se ejecuta en Docker Compose sobre una sola máquina (no en un clúster cloud).

Kafka utiliza:

```text
1 broker
replication-factor = 1
```

Esto es suficiente para demostrar funcionalidad, particionamiento y escalabilidad de consumidores, pero no representa una topología de alta disponibilidad para producción.

Con Kafka detenido los eventos no se publican (solo se registra el fallo); no hay reenvío automático hasta implementar el patrón Outbox.

El `audit-service` actualmente demuestra consumo y procesamiento mediante logs; una evolución futura podría persistir auditorías en una base de datos independiente.

---

## 22. Mejoras futuras

Como evolución de la solución se consideran:

- incorporar flujo `authorization_code` + PKCE con login de usuario final y propagar su identidad al Core para trazabilidad;
- persistir llaves RSA y clientes del `auth-server` (JPA/Redis) y cifrar secretos con BCrypt;
- persistir auditorías procesadas por `audit-service` y el registro de `eventId` (hoy en memoria);
- incorporar el patrón Outbox en el Core para reenviar eventos no publicados cuando Kafka estuvo caído;
- agregar un Schema Registry (Avro) si el número de productores y consumidores crece;
- idempotencia por `Idempotency-Key` también en la API HTTP de movimientos;
- agregar una estrategia de Dead Letter Topic para eventos que no puedan procesarse;
- desplegar Kafka con replicación real para alta disponibilidad;
- incorporar métricas y dashboards de observabilidad;
- externalizar más configuraciones de los servicios mediante Config Server.

---

## 23. Tecnologías utilizadas

- Java;
- Spring Boot 4;
- Spring Cloud Config;
- Netflix Eureka;
- Spring Security;
- Spring Authorization Server;
- OAuth2 Resource Server;
- JWT;
- Resilience4j;
- Spring Data JPA;
- Hibernate;
- MySQL;
- Apache Kafka;
- Spring Kafka;
- Docker y Docker Compose;
- Maven;
- HTTPS / TLS;
- Spring Boot Actuator;
- Git;
- GitHub.

---

## 24. Conclusión

La solución de Banco XYZ evoluciona desde una arquitectura BFF hacia una arquitectura de microservicios con configuración centralizada, descubrimiento, seguridad OAuth 2.0, resiliencia y mensajería asíncrona, desplegada de forma portable con Docker Compose.

El Authorization Server centraliza la emisión de tokens y los BFF y el Core validan scopes con el principio de mínimo privilegio. Resilience4j (Circuit Breaker, Retry y Bulkhead) controla las fallas de comunicación entre los tres BFF y el Core, entregando respuestas controladas cuando el servicio central no está disponible.

Apache Kafka desacopla la generación de movimientos bancarios de su procesamiento posterior. El tópico `banco.movimientos`, junto con tres particiones y el grupo `banco-auditoria`, permite distribuir eventos entre múltiples consumidores y demostrar escalabilidad horizontal.

La publicación posterior al COMMIT mantiene coherencia entre la operación persistida y el evento emitido. Como la publicación es asíncrona, una caída de Kafka no afecta la respuesta al cliente; queda como mejora el patrón Outbox para reenviar los eventos que no pudieron publicarse.

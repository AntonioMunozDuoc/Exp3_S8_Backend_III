# Evidencias de Ejecución
## Banco XYZ - Microservicios, Resiliencia, OAuth2 y Contenedores
### Exp3 - Semana 8

Este documento reúne las evidencias de ejecución de la actividad de Semana 8 de la asignatura **Desarrollo Backend III (PBY2203)**: OAuth 2.0, Docker y Docker Compose, integrados con la resiliencia, la mensajería y la configuración centralizada de semanas anteriores.

Las capturas se encuentran en:

```text
evidencias/Evidencias S8/
```

| N° | Qué demuestra | Captura |
|---|---|---|
| 1 | Imágenes Docker de los microservicios | `E01-images.png` |
| 2 | Contenedores en Docker Desktop | `E02-docker-desktop-containers.png` |
| 3 | Orquestación con Docker Compose | `E03-compose-ps.png` |
| 4 | Core API registrado en Eureka | `E04-eureka.png` |
| 5 | Config Server entrega la configuración del Core | `E05-config-server.png` |
| 6 | Metadata del Authorization Server | `E06-oauth-metadata.png` |
| 7 | Llave pública (JWKS) | `E07-jwks.png` |
| 8 | Emisión de token con `client_credentials` | `E08-token.png` |
| 9 | Credenciales inválidas | `E09-token-invalido.png` |
| 10 | Contenido del JWT | `E10-jwt.png` |
| 11 | Protección OAuth2 de BFF ATM y Core | `E11-proteccion-oauth2.png` |
| 12 | Prueba de humo (smoke test) | `E12-smoke-test.png` |
| 13 | Flujo completo con Kafka | `E13-flujo-kafka.png` |
| 14 | Reparto de particiones entre consumidores | `E14-particiones.png` |
| 15 | Circuit Breaker en estado CLOSED | `E15-circuit-closed.png` |
| 16.1 | Core detenido: respuesta controlada | `E16.1-core-caido.png` |
| 16.2 | Core detenido: Retry y Circuit Breaker | `E16.2-core-caido.png` |
| 17 | Recuperación automática | `E17-recuperacion.png` |
| 18 | Kafka detenido | `E18-kafka-caido.png` |
| 19 | Errores de validación y de negocio | `E19-errores.png` |

---

# Evidencias Semana 8

## Evidencia 01 - Imágenes Docker de los microservicios

Docker Desktop lista las 8 imágenes `bancoxyz/*` (`auth-server`, `audit-service`, `config-server`, `bff-web`, `bff-mobile`, `bff-atm`, `discovery-server`, `bank-core-api`), junto con las imágenes base `maven:3.9-eclipse-temurin-21`, `apache/kafka:4.3.1` y `mysql:8.4`.

**Resultado:** Cada microservicio tiene su propia imagen construida desde su `Dockerfile`.

![Imágenes Docker de los microservicios](evidencias/Evidencias%20S8/E01-images.png)

---

## Evidencia 02 - Contenedores en Docker Desktop

El stack `banco-xyz` muestra los 11 contenedores en ejecución (Kafka, MySQL, Config Server, Discovery, Auth Server, Core, dos instancias de auditoría y los tres BFF) con sus puertos publicados.

**Resultado:** Toda la plataforma corre en una única red de Docker Compose.

![Contenedores en Docker Desktop](evidencias/Evidencias%20S8/E02-docker-desktop-containers.png)

---

## Evidencia 03 - Orquestación con Docker Compose

`docker compose ps` lista los 11 contenedores en estado `Up`. Los que tienen healthcheck (`auth-server`, los tres BFF, `config-server`, `bank-core-api`, `discovery-server`, `kafka` y `mysql`) aparecen `healthy`; las dos instancias de `audit-service` no definen healthcheck.

**Resultado:** El orden de arranque con `depends_on` y `service_healthy` funciona.

![Orquestación con Docker Compose](evidencias/Evidencias%20S8/E03-compose-ps.png)

---

## Evidencia 04 - Core API registrado en Eureka

El dashboard de Eureka (`http://localhost:8761`) muestra `BANK-CORE-API` con estado `UP (1)`.

**Resultado:** El Core se registra en el servidor de descubrimiento.

![Core API registrado en Eureka](evidencias/Evidencias%20S8/E04-eureka.png)

---

## Evidencia 05 - Config Server entrega la configuración del Core

`http://localhost:8888/bank-core-api/default` responde con `banco.xyz.config.origen = Config Server Semana 8`, la configuración del productor Kafka (`acks=all`, `enable.idempotence=true`, `max.block.ms=3000`) y las propiedades del Circuit Breaker `kafkaPublisher`.

**Resultado:** La configuración del Core se centraliza en `config-repo/bank-core-api.properties`.

![Config Server entrega la configuración del Core](evidencias/Evidencias%20S8/E05-config-server.png)

---

## Evidencia 06 - Metadata del Authorization Server

`http://localhost:9000/.well-known/oauth-authorization-server` muestra `issuer = http://auth-server:9000`, `token_endpoint`, `jwks_uri` y `client_credentials` entre los `grant_types_supported`.

**Resultado:** El servidor de autorización publica su metadata estándar.

![Metadata del Authorization Server](evidencias/Evidencias%20S8/E06-oauth-metadata.png)

---

## Evidencia 07 - Llave pública (JWKS)

`http://localhost:9000/oauth2/jwks` publica la llave RSA pública (`kty = RSA`, `e = AQAB`, `kid`, `n`).

**Resultado:** Los Resource Servers validan la firma de los tokens con esta llave.

![Llave pública (JWKS)](evidencias/Evidencias%20S8/E07-jwks.png)

---

## Evidencia 08 - Emisión de token con `client_credentials`

La solicitud de token para `atm-app` con scope `atm.access` responde con `access_token`, `token_type = Bearer` y `expires_in = 299`.

**Resultado:** El Authorization Server emite tokens JWT para el canal ATM.

![Emisión de token con `client_credentials`](evidencias/Evidencias%20S8/E08-token.png)

---

## Evidencia 09 - Credenciales inválidas

Con un secreto incorrecto para `atm-app`, el servidor responde `HTTP/1.1 401` con `{"error":"invalid_client"}`.

**Resultado:** No se emiten tokens a clientes con credenciales incorrectas.

![Credenciales inválidas](evidencias/Evidencias%20S8/E09-token-invalido.png)

---

## Evidencia 10 - Contenido del JWT

El payload decodificado muestra `sub = atm-app`, `aud = atm-app`, `scope = ["atm.access"]`, `iss = http://auth-server:9000` y una vigencia de 300 s (`exp − iat`).

**Resultado:** El token incluye el scope del canal y el emisor fijo configurado.

![Contenido del JWT](evidencias/Evidencias%20S8/E10-jwt.png)

---

## Evidencia 11 - Protección OAuth2 de BFF ATM y Core

Cuatro pruebas: sin token → **401** `NO_AUTENTICADO`; token ATM en el BFF ATM → **200** (`saldoDisponible` de la cuenta 101); token WEB en el BFF ATM → **403** `ACCESO_DENEGADO`; token de canal directo al Core → **403** `ACCESO_DENEGADO`.

**Resultado:** Cada canal solo accede a su recurso y ningún token de canal sirve en el Core, que exige `core.access`.

![Protección OAuth2 de BFF ATM y Core](evidencias/Evidencias%20S8/E11-proteccion-oauth2.png)

---

## Evidencia 12 - Prueba de humo (smoke test)

`.\scripts\smoke-test.ps1` verifica el Authorization Server, la protección de los tres BFF y del Core, y el flujo completo con eventos (retiro 200, monto negativo 400, sin saldo 409, cuenta inexistente 404). Termina con `RESULTADO: 14 OK, 0 con fallo`.

**Resultado:** OAuth2, validaciones y reglas de negocio funcionan de extremo a extremo.

![Prueba de humo (smoke test)](evidencias/Evidencias%20S8/E12-smoke-test.png)

---

## Evidencia 13 - Flujo completo con Kafka

Un retiro de 100 sobre la cuenta 101 responde `HTTP 200` con `estado = APROBADO`. El Core registra `Evento Kafka publicado` (`RETIRO_REALIZADO`, tópico `banco.movimientos`, partición 2) y `audit-service` registra `AUDITORIA [auditoria-2] evento procesado` con el mismo `eventId`.

**Resultado:** El evento se publica después de confirmar la operación y se consume de forma asíncrona.

![Flujo completo con Kafka](evidencias/Evidencias%20S8/E13-flujo-kafka.png)

---

## Evidencia 14 - Reparto de particiones entre consumidores

`kafka-consumer-groups.sh --describe --group banco-auditoria` muestra dos `CONSUMER-ID` distintos: uno con las particiones 0 y 1, y otro con la partición 2 (`LAG = 0`).

**Resultado:** Las dos instancias de `audit-service` comparten el grupo y Kafka reparte las 3 particiones.

![Reparto de particiones entre consumidores](evidencias/Evidencias%20S8/E14-particiones.png)

---

## Evidencia 15 - Circuit Breaker en estado CLOSED

Con el Core disponible, las métricas del circuito `coreApi` en el BFF ATM muestran `closed = 1.0`, `open = 0.0` y `half_open = 0.0`.

**Resultado:** Estado normal del circuito.

![Circuit Breaker en estado CLOSED](evidencias/Evidencias%20S8/E15-circuit-closed.png)

---

## Evidencia 16.1 - Core detenido: respuesta controlada

Tras `docker compose stop bank-core-api`, las cuatro consultas a `GET /api/atm/saldo/101` responden `HTTP 503` con `CORE_NO_DISPONIBLE` y el mensaje estándar de error.

**Resultado:** La caída del Core se maneja con una respuesta controlada.

![Core detenido: respuesta controlada](evidencias/Evidencias%20S8/E16.1-core-caido.png)

---

## Evidencia 16.2 - Core detenido: Retry y Circuit Breaker

Los logs del BFF ATM muestran `Retry [coreApi]: intento 1 fallido` e `intento 2 fallido`, seguidos de `CallNotPermittedException`: con el circuito abierto, el BFF rechaza las llamadas sin intentar contactar al Core.

**Resultado:** Resilience4j aplica Retry y luego abre el circuito.

![Core detenido: Retry y Circuit Breaker](evidencias/Evidencias%20S8/E16.2-core-caido.png)

---

## Evidencia 17 - Recuperación automática

Con el Core nuevamente disponible, las tres consultas responden `HTTP 200` y las métricas vuelven a `closed = 1.0`.

**Resultado:** El circuito se recupera sin intervención manual.

![Recuperación automática](evidencias/Evidencias%20S8/E17-recuperacion.png)

---

## Evidencia 18 - Kafka detenido

Con `docker compose stop kafka`, el retiro por el BFF ATM responde de inmediato `HTTP 200` (`estado = APROBADO`). El log del Core registra `Kafka no disponible: evento ... (RETIRO_REALIZADO) de cuenta 101 no publicado`.

**Resultado:** La caída de Kafka no afecta la operación bancaria: el retiro responde con éxito y el fallo de publicación queda registrado en el Core (publicación asíncrona, ver `DECISIONES_ARQUITECTONICAS.md`, sección 5.2).

![Kafka detenido](evidencias/Evidencias%20S8/E18-kafka-caido.png)

---

## Evidencia 19 - Errores de validación y de negocio

Retiro con monto negativo → `HTTP 400` `VALIDATION_ERROR` con el detalle del campo `monto`; consulta de una cuenta inexistente → `HTTP 404` `NOT_FOUND`.

**Resultado:** Los errores usan el formato estándar de respuesta.

![Errores de validación y de negocio](evidencias/Evidencias%20S8/E19-errores.png)

---

# Resumen de evidencias de Semana 8

Las capturas permiten comprobar:

- construcción de una imagen Docker por microservicio y orquestación de los 11 contenedores con Docker Compose;
- registro del Core en Eureka y configuración centralizada con Config Server;
- Authorization Server con metadata, JWKS y emisión de tokens `client_credentials`, y rechazo de credenciales inválidas;
- contenido del JWT (emisor, sujeto y scope del canal);
- protección de los BFF y del Core por scope (401 sin token, 403 con scope de otro canal);
- prueba de humo con 14 verificaciones exitosas;
- publicación del evento `RETIRO_REALIZADO` y consumo por `audit-service`;
- reparto de las tres particiones entre dos instancias del mismo consumer group;
- Retry y Circuit Breaker con el Core detenido, y recuperación automática al volver;
- registro del fallo de publicación cuando Kafka no está disponible;
- errores de validación (400) y de recurso inexistente (404) con formato estándar.

---

# Evidencias de Semanas Anteriores

## Banco XYZ - Arquitectura de Microservicios, Resiliencia y Eventos
### Exp3 - Semana 7

Este documento reúne las evidencias principales de ejecución de la solución Banco XYZ para la actividad de Semana 7 de la asignatura **Desarrollo Backend III (PBY2203)**.

La solución mantiene la base funcional de la arquitectura Backend for Frontend desarrollada anteriormente e incorpora:

- configuración centralizada con Spring Cloud Config;
- descubrimiento de servicios con Eureka;
- tolerancia a fallos con Resilience4j;
- mensajería asíncrona con Apache Kafka;
- publicación de eventos bancarios;
- procesamiento mediante `audit-service`;
- escalabilidad horizontal mediante Consumer Groups;
- compilación integrada de los módulos del proyecto.

Las evidencias de Semana 5 se mantienen en la carpeta:

```text
evidencias/Evidencias S5/
```

Las evidencias específicas de Semana 7 se encuentran en:

```text
evidencias/Evidencias S7/
```

---

# Evidencias Semana 7

## Evidencia 01 - Config Server entrega la configuración del Core API

Se consulta:

```text
http://localhost:8888/bank-core-api/default
```

La respuesta confirma que `config-server` entrega la configuración centralizada de `bank-core-api`, incluyendo propiedades de Eureka y Kafka.

Entre las propiedades visibles se encuentran:

```text
banco.xyz.config.origen = Config Server Semana 7
eureka.client.serviceUrl.defaultZone = http://localhost:8761/eureka/
spring.kafka.bootstrap-servers = localhost:9092
banco.kafka.topic.movimientos = banco.movimientos
```

![Config Server](evidencias/Evidencias%20S7/01_Config_Server_Bank_Core_API.png)

---

## Evidencia 02 - Core API registrado en Eureka

Se observa el dashboard de Eureka en:

```text
http://localhost:8761
```

El servicio:

```text
BANK-CORE-API
```

aparece registrado con estado:

```text
UP
```

Esto demuestra el funcionamiento del mecanismo de Service Discovery.

![Eureka](evidencias/Evidencias%20S7/02_Eureka_BANK_CORE_API_UP.png)

---

## Evidencia 03 - Resilience4j con Core API disponible

Con el Core API operativo, se consulta:

```text
GET https://localhost:8083/api/atm/saldo/101
```

La respuesta es:

```text
HTTP/1.1 200
```

y entrega:

```json
{
  "cuentaId": 101,
  "saldoDisponible": 4850.00
}
```

Esto demuestra el funcionamiento normal del BFF ATM cuando su dependencia se encuentra disponible.

![Core disponible](evidencias/Evidencias%20S7/03_Resilience_Core_Disponible_200.png)

---

## Evidencia 04 - Core API no disponible y respuesta controlada

Se detiene temporalmente `bank-core-api`, manteniendo el BFF ATM operativo.

Al consultar nuevamente:

```text
GET https://localhost:8083/api/atm/saldo/101
```

se obtiene:

```text
HTTP/1.1 503
```

con el error:

```text
CORE_NO_DISPONIBLE
```

y el mensaje:

```text
El servicio central del banco no se encuentra disponible temporalmente
```

Esto demuestra que la indisponibilidad del Core es manejada de forma controlada.

![Core no disponible](evidencias/Evidencias%20S7/04_BFF_ATM_Resiliencia_CORE_NO_DISPONIBLE.png)

---

## Evidencia 05 - Circuit Breaker en estado CLOSED

Después de recuperar el Core API se consulta la métrica:

```text
resilience4j.circuitbreaker.state
```

para:

```text
name=coreApi
state=closed
```

La medición devuelve:

```json
"value": 1.0
```

confirmando que el Circuit Breaker se encuentra en estado `CLOSED`.

![Circuit Breaker CLOSED](evidencias/Evidencias%20S7/05_Circuit_Breaker_CLOSED.png)

---

## Evidencia 06 - Circuit Breaker en estado OPEN

Con el Core API detenido se realizan múltiples consultas al BFF ATM.

Las solicitudes responden con:

```text
503 CORE_NO_DISPONIBLE
```

Luego se consulta la métrica:

```text
name=coreApi
state=open
```

obteniendo:

```json
"value": 1.0
```

Esto confirma que Resilience4j abrió el circuito después de alcanzar el umbral de fallas configurado.

![Circuit Breaker OPEN](evidencias/Evidencias%20S7/06_Circuit_Breaker_OPEN.png)

---

## Evidencia 07 - Circuit Breaker en estado HALF_OPEN

Después del tiempo de espera configurado, se consulta:

```text
name=coreApi
state=half_open
```

La respuesta devuelve:

```json
"value": 1.0
```

confirmando la transición automática del Circuit Breaker al estado `HALF_OPEN`.

![Circuit Breaker HALF OPEN](evidencias/Evidencias%20S7/07_Circuit_Breaker_HALF_OPEN.png)

---

## Evidencia 08 - Tópico Kafka con tres particiones

Se describe el tópico:

```text
banco.movimientos
```

La configuración observada es:

```text
PartitionCount: 3
ReplicationFactor: 1
```

y se muestran las particiones:

```text
0
1
2
```

Esto permite distribuir eventos entre múltiples consumidores.

![Kafka tópico](evidencias/Evidencias%20S7/08_Kafka_Topic_3_Particiones.png)

---

## Evidencia 09 - Retiro aprobado mediante BFF ATM

Se ejecuta un retiro de:

```text
100.00
```

sobre la cuenta:

```text
101
```

La respuesta es:

```text
HTTP/1.1 200
```

con:

```json
{
  "cuentaId": 101,
  "montoRetirado": 100.00,
  "saldoDisponible": 4750.00,
  "estado": "APROBADO"
}
```

Esto confirma que la operación bancaria continúa funcionando correctamente con la arquitectura de Semana 7.

![Retiro ATM](evidencias/Evidencias%20S7/09_ATM_Retiro_APROBADO.png)

---

## Evidencia 10 - Evento RETIRO_REALIZADO publicado en Kafka

Se consume el tópico `banco.movimientos` y se observa el evento correspondiente al retiro anterior.

Datos principales:

```text
Partition: 2
Offset: 1
Key: 101
```

Payload:

```json
{
  "tipoEvento": "RETIRO_REALIZADO",
  "movimientoId": 14,
  "cuentaId": 101,
  "tipoMovimiento": "retiro",
  "monto": -100.00,
  "saldoResultante": 4750.00
}
```

Esto demuestra el flujo:

```text
BFF ATM
   ->
Bank Core API
   ->
MySQL
   ->
AFTER_COMMIT
   ->
Kafka
```

![Evento Kafka](evidencias/Evidencias%20S7/10_Kafka_Evento_RETIRO_REALIZADO.png)

---

## Evidencia 11 - Audit Service procesa el evento

Se inicia una instancia de:

```text
audit-service
```

con:

```text
AUDIT_INSTANCE=auditoria-1
```

El consumidor se suscribe al tópico:

```text
banco.movimientos
```

dentro del grupo:

```text
banco-auditoria
```

y procesa correctamente el evento:

```text
AUDITORIA [auditoria-1] evento procesado:
key=101
particion=2
offset=1
```

El payload corresponde a:

```text
RETIRO_REALIZADO
saldoResultante=4750.00
```

Esto demuestra comunicación asíncrona funcional entre el productor y el consumidor.

![Audit Service](evidencias/Evidencias%20S7/11_Audit_Service_Consume_Evento.png)

---

## Evidencia 12 - Escalabilidad horizontal con dos consumidores

Se ejecutan dos instancias de `audit-service` dentro del mismo grupo:

```text
banco-auditoria
```

La descripción del grupo muestra dos `CONSUMER-ID` distintos.

La distribución observada es:

```text
Consumidor 1 -> particiones 0 y 1
Consumidor 2 -> partición 2
```

Además, las particiones con eventos procesados presentan:

```text
LAG = 0
```

Esto demuestra que Kafka realiza el rebalanceo y distribuye las particiones entre múltiples consumidores del mismo grupo.

![Escalabilidad Kafka](evidencias/Evidencias%20S7/12_Kafka_Escalabilidad_2_Consumidores.png)

---

## Evidencia 13 - Compilación final de los ocho módulos

Se ejecuta desde la raíz:

```powershell
.\mvnw.cmd verify
```

El Reactor Summary muestra:

```text
Banco XYZ - Exp3 Semana 7 ........ SUCCESS
Banco XYZ - Config Server ........ SUCCESS
Banco XYZ - Discovery Server ..... SUCCESS
Banco XYZ - Core API ............. SUCCESS
Banco XYZ - BFF Web .............. SUCCESS
Banco XYZ - BFF Mobile ........... SUCCESS
Banco XYZ - BFF ATM .............. SUCCESS
Banco XYZ - Audit Service ........ SUCCESS
```

y finaliza con:

```text
BUILD SUCCESS
```

Esta evidencia demuestra compilación y empaquetado integrado exitoso de los módulos Maven del proyecto.

![Build Success](evidencias/Evidencias%20S7/13_BUILD_SUCCESS_8_Modulos.png)

---

# Resumen de evidencias

Las pruebas de Semana 7 permiten comprobar:

- funcionamiento de Spring Cloud Config;
- configuración centralizada de `bank-core-api`;
- registro del Core API en Eureka;
- operación normal del BFF ATM con el Core disponible;
- respuesta controlada cuando el Core no está disponible;
- transición del Circuit Breaker por los estados `CLOSED`, `OPEN` y `HALF_OPEN`;
- funcionamiento del tópico Kafka `banco.movimientos`;
- configuración de tres particiones;
- publicación de un evento real `RETIRO_REALIZADO`;
- procesamiento asíncrono mediante `audit-service`;
- distribución de particiones entre dos consumidores;
- escalabilidad horizontal mediante Consumer Groups;
- compilación integrada de los ocho módulos del proyecto.

---

# Relación con los criterios de evaluación

## 1. Arquitectura orientada a eventos

`bank-core-api` actúa como productor de eventos y `audit-service` como consumidor desacoplado.

El flujo implementado es:

```text
Operación bancaria
   ->
Persistencia MySQL
   ->
COMMIT
   ->
Evento
   ->
Kafka
   ->
Audit Service
```

## 2. Tópicos, mensajes y eventos

Tópico:

```text
banco.movimientos
```

Eventos implementados:

```text
DEPOSITO_REALIZADO
RETIRO_REALIZADO
COMPRA_REALIZADA
```

Clave Kafka:

```text
cuentaId
```

Particiones:

```text
3
```

## 3. Tolerancia a fallos con Resilience4j

El BFF ATM protege las llamadas al Core API mediante el Circuit Breaker:

```text
coreApi
```

Se demuestran los estados:

```text
CLOSED
OPEN
HALF_OPEN
```

además de la respuesta controlada:

```text
HTTP 503
CORE_NO_DISPONIBLE
```

## 4. Mensajería asíncrona y escalabilidad

Kafka procesa eventos de forma asíncrona mediante el grupo:

```text
banco-auditoria
```

La ejecución simultánea de dos consumidores permite comprobar el reparto de las tres particiones y el rebalanceo automático.

---

## Conclusión

Las evidencias demuestran que Banco XYZ evoluciona hacia una arquitectura de microservicios con configuración centralizada, descubrimiento de servicios, tolerancia a fallos y comunicación asíncrona.

Resilience4j permite gestionar de forma controlada la indisponibilidad del Core API, mientras que Kafka desacopla la publicación y el procesamiento posterior de los movimientos bancarios.

La integración entre `bank-core-api`, `banco.movimientos` y `audit-service`, junto con la ejecución de múltiples consumidores, demuestra una solución funcional y preparada para escalar horizontalmente.

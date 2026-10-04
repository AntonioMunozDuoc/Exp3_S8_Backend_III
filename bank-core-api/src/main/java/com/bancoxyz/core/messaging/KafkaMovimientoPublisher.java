package com.bancoxyz.core.messaging;

import com.bancoxyz.common.event.ContratoEventoException;
import com.bancoxyz.common.event.MovimientoEvento;
import com.bancoxyz.common.event.MovimientoEventoContrato;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.common.header.Header;
import org.apache.kafka.common.header.internals.RecordHeader;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.cloud.client.circuitbreaker.CircuitBreakerFactory;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

import java.nio.charset.StandardCharsets;
import java.util.List;

/**
 * Publica el evento en Kafka SOLO despues del COMMIT de la transaccion.
 *
 * Continuidad operativa: el movimiento ya esta confirmado en la base de datos,
 * por lo que una caida de Kafka nunca debe convertir la operacion bancaria en
 * un error para el cliente. El envio esta protegido con un Circuit Breaker
 * (instancia "kafkaPublisher") y con max.block.ms acotado; si falla, se
 * registra el error y la operacion sigue respondiendo con exito.
 * (Mejora futura documentada: patron Outbox para reenviar eventos perdidos.)
 */
@Component
public class KafkaMovimientoPublisher {

    private static final Logger log =
            LoggerFactory.getLogger(KafkaMovimientoPublisher.class);

    private final KafkaTemplate<String, String> kafkaTemplate;
    private final CircuitBreakerFactory<?, ?> circuitBreakerFactory;
    private final String topicMovimientos;

    public KafkaMovimientoPublisher(
            KafkaTemplate<String, String> kafkaTemplate,
            CircuitBreakerFactory<?, ?> circuitBreakerFactory,
            @Value("${banco.kafka.topic.movimientos}") String topicMovimientos) {

        this.kafkaTemplate = kafkaTemplate;
        this.circuitBreakerFactory = circuitBreakerFactory;
        this.topicMovimientos = topicMovimientos;
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void publicarMovimiento(MovimientoEvento evento) {

        String payload;

        try {
            // Valida el contrato JSON Schema antes de enviar
            payload = MovimientoEventoContrato.serializar(evento);

        } catch (ContratoEventoException ex) {
            log.error(
                    "Evento {} descartado: incumple el contrato v1 -> {}",
                    evento.eventId(),
                    ex.getErrores()
            );
            return;
        }

        String key = evento.cuentaId().toString();

        List<Header> headers = List.of(
                cabecera("eventId", evento.eventId()),
                cabecera("eventType", evento.tipoEvento()),
                cabecera("schemaVersion", evento.version())
        );

        ProducerRecord<String, String> registro =
                new ProducerRecord<>(topicMovimientos, null, key, payload, headers);

        circuitBreakerFactory
                .create("kafkaPublisher")
                .run(
                        () -> enviar(registro, evento),
                        error -> {
                            log.error(
                                    "Kafka no disponible: evento {} ({}) de cuenta {} no publicado",
                                    evento.eventId(),
                                    evento.tipoEvento(),
                                    evento.cuentaId(),
                                    error
                            );
                            return Boolean.FALSE;
                        }
                );
    }

    private Boolean enviar(
            ProducerRecord<String, String> registro,
            MovimientoEvento evento) {

        kafkaTemplate
                .send(registro)
                .whenComplete((resultado, error) -> {

                    if (error != null) {
                        log.error(
                                "Error publicando evento {} de cuenta {} en Kafka",
                                evento.eventId(),
                                evento.cuentaId(),
                                error
                        );
                        return;
                    }

                    log.info(
                            "Evento Kafka publicado: eventId={}, tipo={}, cuenta={}, topic={}, particion={}, offset={}",
                            evento.eventId(),
                            evento.tipoEvento(),
                            evento.cuentaId(),
                            topicMovimientos,
                            resultado.getRecordMetadata().partition(),
                            resultado.getRecordMetadata().offset()
                    );
                });

        return Boolean.TRUE;
    }

    private Header cabecera(String nombre, String valor) {
        return new RecordHeader(nombre, valor.getBytes(StandardCharsets.UTF_8));
    }
}

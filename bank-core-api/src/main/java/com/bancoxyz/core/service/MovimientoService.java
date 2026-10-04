package com.bancoxyz.core.service;

import com.bancoxyz.common.event.MovimientoEvento;
import com.bancoxyz.core.dto.MovimientoRequest;
import com.bancoxyz.core.dto.MovimientoResponse;
import com.bancoxyz.core.entity.Cuenta;
import com.bancoxyz.core.entity.Movimiento;
import com.bancoxyz.core.exception.RecursoNoEncontradoException;
import com.bancoxyz.core.exception.SaldoInsuficienteException;
import com.bancoxyz.core.mapper.MovimientoMapper;
import com.bancoxyz.core.repository.CuentaRepository;
import com.bancoxyz.core.repository.MovimientoRepository;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.List;

@Service
public class MovimientoService {

    private final MovimientoRepository movimientoRepository;
    private final CuentaRepository cuentaRepository;
    private final MovimientoMapper movimientoMapper;
    private final ApplicationEventPublisher eventPublisher;

    public MovimientoService(
            MovimientoRepository movimientoRepository,
            CuentaRepository cuentaRepository,
            MovimientoMapper movimientoMapper,
            ApplicationEventPublisher eventPublisher) {

        this.movimientoRepository = movimientoRepository;
        this.cuentaRepository = cuentaRepository;
        this.movimientoMapper = movimientoMapper;
        this.eventPublisher = eventPublisher;
    }

    @Transactional(readOnly = true)
    public List<MovimientoResponse> obtenerPorCuenta(Long cuentaId) {
        return movimientoRepository
                .findByCuentaIdOrderByFechaDescIdDesc(cuentaId)
                .stream()
                .map(movimientoMapper::toResponse)
                .toList();
    }

    /**
     * Recibe el DTO de entrada ya validado y devuelve un DTO de salida.
     * La entidad JPA y el evento de dominio se manejan solo dentro de la capa de servicio.
     */
    @Transactional
    public MovimientoResponse registrarOperacion(MovimientoRequest request) {

        Movimiento movimiento = movimientoMapper.toEntity(request);

        Cuenta cuenta = cuentaRepository.findById(movimiento.getCuentaId())
                .orElseThrow(() ->
                        new RecursoNoEncontradoException(
                                "Cuenta no encontrada: " + movimiento.getCuentaId()
                        )
                );

        String tipo = movimiento.getTipoMovimiento();

        BigDecimal monto = movimiento.getMonto();

        String tipoEvento;

        switch (tipo) {

            case "deposito" -> {
                cuenta.setSaldoActual(
                        cuenta.getSaldoActual().add(monto)
                );

                tipoEvento = "DEPOSITO_REALIZADO";
            }

            case "retiro" -> {

                validarSaldo(cuenta, monto);

                cuenta.setSaldoActual(
                        cuenta.getSaldoActual().subtract(monto)
                );

                movimiento.setMonto(monto.negate());

                tipoEvento = "RETIRO_REALIZADO";
            }

            case "compra" -> {

                validarSaldo(cuenta, monto);

                cuenta.setSaldoActual(
                        cuenta.getSaldoActual().subtract(monto)
                );

                movimiento.setMonto(monto.negate());

                tipoEvento = "COMPRA_REALIZADA";
            }

            default -> throw new IllegalArgumentException(
                    "Tipo de movimiento no soportado: " + tipo
            );
        }

        cuentaRepository.save(cuenta);

        Movimiento guardado =
                movimientoRepository.save(movimiento);

        // El evento lleva eventId unico (clave de idempotencia del consumidor)
        // y se publica en Kafka solo despues del COMMIT (AFTER_COMMIT).
        MovimientoEvento evento =
                MovimientoEvento.nuevo(
                        tipoEvento,
                        guardado.getId(),
                        guardado.getCuentaId(),
                        guardado.getTipoMovimiento(),
                        guardado.getMonto(),
                        cuenta.getSaldoActual(),
                        guardado.getFecha()
                );

        eventPublisher.publishEvent(evento);

        return movimientoMapper.toResponse(guardado);
    }

    private void validarSaldo(Cuenta cuenta, BigDecimal monto) {

        if (cuenta.getSaldoActual().compareTo(monto) < 0) {
            throw new SaldoInsuficienteException(
                    "Saldo insuficiente para realizar la operacion"
            );
        }
    }
}

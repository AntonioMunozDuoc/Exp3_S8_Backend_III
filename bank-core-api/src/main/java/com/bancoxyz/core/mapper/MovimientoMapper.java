package com.bancoxyz.core.mapper;

import com.bancoxyz.core.dto.MovimientoRequest;
import com.bancoxyz.core.dto.MovimientoResponse;
import com.bancoxyz.core.entity.Movimiento;
import org.springframework.stereotype.Component;

import java.time.LocalDate;

/**
 * Unico punto de conversion entre DTO y entidad JPA.
 * Las entidades no salen de la capa de servicio.
 */
@Component
public class MovimientoMapper {

    public MovimientoResponse toResponse(Movimiento movimiento) {
        return new MovimientoResponse(
                movimiento.getId(),
                movimiento.getCuentaId(),
                movimiento.getFecha(),
                movimiento.getTipoMovimiento(),
                movimiento.getMonto(),
                movimiento.getDescripcion()
        );
    }

    public Movimiento toEntity(MovimientoRequest request) {
        return new Movimiento(
                request.cuentaId(),
                LocalDate.now(),
                request.tipoMovimiento().trim().toLowerCase(),
                request.monto(),
                request.descripcion()
        );
    }
}

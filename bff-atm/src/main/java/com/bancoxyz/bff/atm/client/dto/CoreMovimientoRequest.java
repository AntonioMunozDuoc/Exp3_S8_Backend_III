package com.bancoxyz.bff.atm.client.dto;

import java.math.BigDecimal;

public record CoreMovimientoRequest(
        Long cuentaId,
        String tipoMovimiento,
        BigDecimal monto,
        String descripcion
) {
}
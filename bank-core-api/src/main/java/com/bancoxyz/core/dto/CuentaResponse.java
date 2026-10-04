package com.bancoxyz.core.dto;

import java.math.BigDecimal;

public record CuentaResponse(
        Long cuentaId,
        String nombre,
        Integer edad,
        String tipo,
        BigDecimal saldoActual,
        BigDecimal tasaInteres,
        BigDecimal interesCalculado
) {
}
package com.bancoxyz.core.dto;

import jakarta.validation.constraints.Digits;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.Size;

import java.math.BigDecimal;

/**
 * DTO de entrada. Se valida en el controlador, ANTES de abrir la transaccion
 * del servicio, de modo que una solicitud invalida nunca toca la base de datos
 * ni genera eventos.
 */
public record MovimientoRequest(

        @NotNull(message = "La cuenta es obligatoria")
        @Positive(message = "La cuenta debe ser un identificador valido")
        Long cuentaId,

        @NotBlank(message = "El tipo de movimiento es obligatorio")
        @Pattern(
                regexp = "(?i)^\\s*(deposito|retiro|compra)\\s*$",
                message = "El tipo de movimiento debe ser deposito, retiro o compra"
        )
        String tipoMovimiento,

        @NotNull(message = "El monto es obligatorio")
        @Positive(message = "El monto debe ser mayor que cero")
        @Digits(
                integer = 13,
                fraction = 2,
                message = "El monto admite hasta 13 enteros y 2 decimales"
        )
        BigDecimal monto,

        @Size(max = 255, message = "La descripcion no puede superar 255 caracteres")
        String descripcion
) {
}

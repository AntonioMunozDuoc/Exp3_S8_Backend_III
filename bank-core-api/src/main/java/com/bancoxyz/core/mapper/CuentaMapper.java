package com.bancoxyz.core.mapper;

import com.bancoxyz.core.dto.CuentaResponse;
import com.bancoxyz.core.entity.Cuenta;
import org.springframework.stereotype.Component;

@Component
public class CuentaMapper {

    public CuentaResponse toResponse(Cuenta cuenta) {
        return new CuentaResponse(
                cuenta.getCuentaId(),
                cuenta.getNombre(),
                cuenta.getEdad(),
                cuenta.getTipo(),
                cuenta.getSaldoActual(),
                cuenta.getTasaInteres(),
                cuenta.getInteresCalculado()
        );
    }
}
package com.bancoxyz.core.controller;

import com.bancoxyz.core.dto.CuentaResponse;
import com.bancoxyz.core.dto.MovimientoResponse;
import com.bancoxyz.core.service.CuentaService;
import com.bancoxyz.core.service.MovimientoService;
import jakarta.validation.constraints.Positive;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/core/cuentas")
public class CuentaController {

    private final CuentaService cuentaService;
    private final MovimientoService movimientoService;

    public CuentaController(
            CuentaService cuentaService,
            MovimientoService movimientoService) {

        this.cuentaService = cuentaService;
        this.movimientoService = movimientoService;
    }

    @GetMapping
    public List<CuentaResponse> listarCuentas() {
        return cuentaService.listarTodas();
    }

    @GetMapping("/{cuentaId}")
    public CuentaResponse obtenerCuenta(
            @PathVariable
            @Positive(message = "La cuenta debe ser un identificador valido")
            Long cuentaId) {

        return cuentaService.obtenerPorId(cuentaId);
    }

    @GetMapping("/{cuentaId}/movimientos")
    public List<MovimientoResponse> obtenerMovimientos(
            @PathVariable
            @Positive(message = "La cuenta debe ser un identificador valido")
            Long cuentaId) {

        // Verifica que la cuenta exista (404 si no) antes de listar
        cuentaService.obtenerPorId(cuentaId);

        return movimientoService.obtenerPorCuenta(cuentaId);
    }
}

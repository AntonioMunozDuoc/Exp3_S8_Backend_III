package com.bancoxyz.core.controller;

import com.bancoxyz.core.dto.MovimientoRequest;
import com.bancoxyz.core.dto.MovimientoResponse;
import com.bancoxyz.core.service.MovimientoService;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/core/movimientos")
public class MovimientoController {

    private final MovimientoService movimientoService;

    public MovimientoController(MovimientoService movimientoService) {
        this.movimientoService = movimientoService;
    }

    /**
     * @Valid se evalua antes de entrar al servicio transaccional:
     * una solicitud invalida responde 400 sin abrir transaccion.
     */
    @PostMapping
    public ResponseEntity<MovimientoResponse> crearMovimiento(
            @Valid @RequestBody MovimientoRequest request) {

        return ResponseEntity
                .status(HttpStatus.CREATED)
                .body(movimientoService.registrarOperacion(request));
    }
}

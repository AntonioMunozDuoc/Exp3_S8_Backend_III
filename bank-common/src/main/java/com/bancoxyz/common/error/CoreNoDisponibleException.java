package com.bancoxyz.common.error;

/** El servicio central no responde (Circuit Breaker abierto, timeout o caida). */
public class CoreNoDisponibleException extends RuntimeException {

    public CoreNoDisponibleException(String mensaje) {
        super(mensaje);
    }
}

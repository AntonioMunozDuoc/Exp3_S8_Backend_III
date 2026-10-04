package com.bancoxyz.core.service;

import com.bancoxyz.core.dto.CuentaResponse;
import com.bancoxyz.core.exception.RecursoNoEncontradoException;
import com.bancoxyz.core.mapper.CuentaMapper;
import com.bancoxyz.core.repository.CuentaRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

/** Expone DTOs: la entidad Cuenta no sale de esta capa. */
@Service
public class CuentaService {

    private final CuentaRepository cuentaRepository;
    private final CuentaMapper cuentaMapper;

    public CuentaService(
            CuentaRepository cuentaRepository,
            CuentaMapper cuentaMapper) {

        this.cuentaRepository = cuentaRepository;
        this.cuentaMapper = cuentaMapper;
    }

    @Transactional(readOnly = true)
    public List<CuentaResponse> listarTodas() {
        return cuentaRepository.findAll()
                .stream()
                .map(cuentaMapper::toResponse)
                .toList();
    }

    @Transactional(readOnly = true)
    public CuentaResponse obtenerPorId(Long cuentaId) {
        return cuentaRepository.findById(cuentaId)
                .map(cuentaMapper::toResponse)
                .orElseThrow(() ->
                        new RecursoNoEncontradoException(
                                "Cuenta no encontrada: " + cuentaId
                        )
                );
    }
}

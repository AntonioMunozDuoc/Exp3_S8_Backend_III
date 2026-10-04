package com.bancoxyz.core.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.math.BigDecimal;

@Entity
@Table(name = "cuentas")
public class Cuenta {

    @Id
    @Column(name = "cuenta_id")
    private Long cuentaId;

    @Column(nullable = false, length = 100)
    private String nombre;

    private Integer edad;

    @Column(nullable = false, length = 30)
    private String tipo;

    @Column(name = "saldo_actual", nullable = false, precision = 15, scale = 2)
    private BigDecimal saldoActual;

    @Column(name = "tasa_interes", precision = 10, scale = 4)
    private BigDecimal tasaInteres;

    @Column(name = "interes_calculado", precision = 15, scale = 2)
    private BigDecimal interesCalculado;

    public Cuenta() {
    }

    public Cuenta(Long cuentaId,
                  String nombre,
                  Integer edad,
                  String tipo,
                  BigDecimal saldoActual,
                  BigDecimal tasaInteres,
                  BigDecimal interesCalculado) {
        this.cuentaId = cuentaId;
        this.nombre = nombre;
        this.edad = edad;
        this.tipo = tipo;
        this.saldoActual = saldoActual;
        this.tasaInteres = tasaInteres;
        this.interesCalculado = interesCalculado;
    }

    public Long getCuentaId() {
        return cuentaId;
    }

    public void setCuentaId(Long cuentaId) {
        this.cuentaId = cuentaId;
    }

    public String getNombre() {
        return nombre;
    }

    public void setNombre(String nombre) {
        this.nombre = nombre;
    }

    public Integer getEdad() {
        return edad;
    }

    public void setEdad(Integer edad) {
        this.edad = edad;
    }

    public String getTipo() {
        return tipo;
    }

    public void setTipo(String tipo) {
        this.tipo = tipo;
    }

    public BigDecimal getSaldoActual() {
        return saldoActual;
    }

    public void setSaldoActual(BigDecimal saldoActual) {
        this.saldoActual = saldoActual;
    }

    public BigDecimal getTasaInteres() {
        return tasaInteres;
    }

    public void setTasaInteres(BigDecimal tasaInteres) {
        this.tasaInteres = tasaInteres;
    }

    public BigDecimal getInteresCalculado() {
        return interesCalculado;
    }

    public void setInteresCalculado(BigDecimal interesCalculado) {
        this.interesCalculado = interesCalculado;
    }
}
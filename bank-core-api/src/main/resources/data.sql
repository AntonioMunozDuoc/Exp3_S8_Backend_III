-- Datos base del Banco XYZ (repo bank_legacy_data, semana_1/intereses.csv y cuentas_anuales.csv).
-- Se ejecuta solo con SQL_INIT_MODE=always (docker-compose). INSERT IGNORE lo hace repetible:
-- reiniciar el Core no duplica ni pisa los saldos existentes.

INSERT IGNORE INTO cuentas (cuenta_id, nombre, edad, tipo, saldo_actual, tasa_interes, interes_calculado) VALUES
(101, 'John Doe',      30, 'ahorro',    5000.00,  0.0150, 0.00),
(102, 'Jane Smith',    25, 'prestamo',  8000.00,  0.0500, 0.00),
(103, 'Bob Johnson',   30, 'prestamo', 12000.00,  0.0500, 0.00),
(104, 'Alice Brown',   45, 'ahorro',       0.00,  0.0150, 0.00),
(105, 'Charlie Green', 35, 'hipoteca',  7000.00,  0.0400, 0.00),
(106, 'John Doe',      30, 'ahorro',    5000.00,  0.0150, 0.00),
(107, 'Diana Prince',  40, 'prestamo', 15000.00,  0.0500, 0.00),
(108, 'Steve Rogers',  80, 'ahorro',   10000.00,  0.0150, 0.00);

INSERT IGNORE INTO movimientos (id, cuenta_id, fecha, tipo_movimiento, monto, descripcion) VALUES
(1, 101, '2024-01-01', 'deposito', 1000.00, 'Ingreso mensual'),
(2, 101, '2024-03-15', 'retiro',   -500.00, 'Retiro parcial'),
(3, 102, '2024-05-22', 'deposito', 1500.00, 'Ingreso mensual'),
(4, 103, '2024-07-10', 'deposito', 2000.00, 'Ingreso mensual'),
(5, 104, '2024-09-05', 'compra',   -100.00, 'Compra en tienda'),
(6, 105, '2024-10-01', 'deposito', 2500.00, 'Ingreso extra'),
(7, 106, '2024-11-20', 'deposito', 3000.00, 'Ingreso mensual'),
(8, 107, '2024-12-25', 'deposito',    0.00, 'Ingreso navideño'),
(9, 108, '2024-12-31', 'deposito', 2000.00, 'Ingreso de fin de año');

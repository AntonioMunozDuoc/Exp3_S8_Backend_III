package com.bancoxyz.core;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication(scanBasePackages = {
        "com.bancoxyz.core",
        "com.bancoxyz.common"   // manejo global de errores compartido
})
public class BankCoreApiApplication {

    public static void main(String[] args) {
        SpringApplication.run(BankCoreApiApplication.class, args);
    }
}

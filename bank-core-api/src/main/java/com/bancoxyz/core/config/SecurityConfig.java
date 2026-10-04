package com.bancoxyz.core.config;

import com.bancoxyz.common.error.ApiSecurityErrorHandlers;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;

/**
 * El Core API es un Resource Server OAuth 2.0.
 *
 * Solo atiende solicitudes con un access token JWT valido (firma, expiracion
 * e issuer verificados contra el auth-server) que incluya el scope core.access.
 * Los BFF obtienen ese token con el grant client_credentials.
 */
@Configuration
public class SecurityConfig {

    @Bean
    public SecurityFilterChain securityFilterChain(
            HttpSecurity http) throws Exception {

        ApiSecurityErrorHandlers erroresSeguridad =
                new ApiSecurityErrorHandlers();

        http
                .csrf(csrf -> csrf.disable())

                .sessionManagement(session -> session
                        .sessionCreationPolicy(SessionCreationPolicy.STATELESS))

                .authorizeHttpRequests(auth -> auth
                        .requestMatchers("/actuator/health/**", "/actuator/info")
                        .permitAll()

                        .requestMatchers("/api/core/**")
                        .hasAuthority("SCOPE_core.access")

                        .anyRequest()
                        .authenticated()
                )

                .oauth2ResourceServer(oauth2 -> oauth2
                        .jwt(Customizer.withDefaults())
                        .authenticationEntryPoint(erroresSeguridad)
                        .accessDeniedHandler(erroresSeguridad)
                );

        return http.build();
    }
}

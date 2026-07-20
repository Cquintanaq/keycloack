package main.java.com.example.listener;
// src/main/java/com/example/listener/CustomEventListenerProviderFactory.java

import org.keycloak.Config;
import org.keycloak.events.EventListenerProvider;
import org.keycloak.events.EventListenerProviderFactory;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.KeycloakSessionFactory;

public class CustomEventListenerProviderFactory implements EventListenerProviderFactory {

    public static final String PROVIDER_ID = "custom-rabbit-listener";

    @Override
    public EventListenerProvider create(KeycloakSession session) {
        try {
            return new CustomEventListenerProvider(session);
        } catch (Exception e) {
            throw new RuntimeException("Error creando el listener", e);
        }
    }

    @Override
    public void init(Config.Scope config) {}

    @Override
    public void postInit(KeycloakSessionFactory factory) {}

    @Override
    public void close() {}

    @Override
    public String getId() {
        return PROVIDER_ID;
    }
}
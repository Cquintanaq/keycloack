package main.java.com.example.listener;
// src/main/java/com/example/listener/CustomEventListenerProvider.java
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.keycloak.events.Event;
import org.keycloak.events.EventListenerProvider;
import org.keycloak.events.EventType;
import org.keycloak.models.KeycloakSession;

import java.util.HashMap;
import java.util.Map;

public class CustomEventListenerProvider implements EventListenerProvider {

    private final RabbitMQProducer rabbitMQ;
    private final ObjectMapper json = new ObjectMapper();
    private final KeycloakSession session;

    public CustomEventListenerProvider(KeycloakSession session) throws Exception {
        this.session = session;
        this.rabbitMQ = new RabbitMQProducer();
    }

    @Override
    public void onEvent(Event event) {
        if (isRelevantEvent(event)) {
            try {
                String message = buildEventMessage(event);
                rabbitMQ.send(message);
            } catch (Exception e) {
                e.printStackTrace();
            }
        }
    }

    @Override
    public void onEvent(org.keycloak.events.admin.AdminEvent adminEvent, boolean includeRepresentation) {}

    private boolean isRelevantEvent(Event event) {
        EventType type = event.getType();
        return type == EventType.USER_UPDATE ||        // Cambio de perfil/email
               type == EventType.ROLE_GRANT ||         // Asignación de rol
               type == EventType.ROLE_REMOVED ||       // Eliminación de rol
               type == EventType.MEMBER_ADDED ||       // Añadido a grupo
               type == EventType.MEMBER_REMOVED;       // Removido de grupo
    }

    private String buildEventMessage(Event event) throws JsonProcessingException {
        Map<String, Object> data = new HashMap<>();
        data.put("type", event.getType());
        data.put("timestamp", event.getTime());
        data.put("realmId", event.getRealmId());
        data.put("userId", event.getUserId());
        data.put("ipAddress", event.getIpAddress());

        try {
            var user = session.users().getUserById(event.getRealmId(), event.getUserId());
            if (user != null) {
                data.put("username", user.getUsername());
                data.put("email", user.getEmail());
                data.put("firstName", user.getFirstName());
                data.put("lastName", user.getLastName());

                var groups = user.getGroups();
                data.put("groups", groups.stream().map(g -> g.getName()).toList());

                var roles = user.getRealmRoleMappings();
                data.put("roles", roles.stream().map(r -> r.getName()).toList());
            }
        } catch (Exception e) {
            data.put("userError", "No se pudo cargar el usuario: " + e.getMessage());
        }

        return json.writeValueAsString(data);
    }

    @Override
    public void close() {
        try {
            rabbitMQ.channel.close();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
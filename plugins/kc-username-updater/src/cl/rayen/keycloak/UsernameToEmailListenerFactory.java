package cl.rayen.keycloak;

import org.keycloak.Config;
import org.keycloak.events.EventListenerProvider;
import org.keycloak.events.EventListenerProviderFactory;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.KeycloakSessionFactory;

/**
 * Factory para UsernameToEmailListener.
 * El ID "username-to-email-updater" es el nombre que aparece en
 * Keycloak → Realm Settings → Events → Event Listeners.
 */
public class UsernameToEmailListenerFactory implements EventListenerProviderFactory {

    public static final String PROVIDER_ID = "username-to-email-updater";

    @Override
    public EventListenerProvider create(KeycloakSession session) {
        return new UsernameToEmailListener(session);
    }

    @Override
    public void init(Config.Scope config) {
        // Sin configuración adicional
    }

    @Override
    public void postInit(KeycloakSessionFactory factory) {
        // Sin inicialización post
    }

    @Override
    public void close() {
        // Nada que limpiar
    }

    @Override
    public String getId() {
        return PROVIDER_ID;
    }
}

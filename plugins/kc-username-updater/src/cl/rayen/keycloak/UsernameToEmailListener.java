package cl.rayen.keycloak;

import org.keycloak.events.Event;
import org.keycloak.events.EventListenerProvider;
import org.keycloak.events.EventType;
import org.keycloak.events.admin.AdminEvent;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.RealmModel;
import org.keycloak.models.UserModel;

/**
 * SPI Event Listener que cambia el username del RUT al email
 * cuando el usuario completa el formulario UPDATE_PROFILE.
 *
 * Flujo:
 * 1. Usuario migrado tiene username = RUT (ej: 12345678-9)
 * 2. Primer login → Keycloak fuerza UPDATE_PROFILE
 * 3. Usuario ingresa su email real
 * 4. Este listener detecta el evento y cambia username = email
 * 5. Próximo login: solo funciona con email
 */
public class UsernameToEmailListener implements EventListenerProvider {

    private static final String PLACEHOLDER_DOMAIN = "@pendiente.rni.cl";
    private final KeycloakSession session;

    public UsernameToEmailListener(KeycloakSession session) {
        this.session = session;
    }

    @Override
    public void onEvent(Event event) {
        if (event.getType() != EventType.UPDATE_PROFILE) {
            return;
        }

        String userId = event.getUserId();
        String realmId = event.getRealmId();

        if (userId == null || realmId == null) {
            return;
        }

        RealmModel realm = session.realms().getRealm(realmId);
        if (realm == null) {
            return;
        }

        UserModel user = session.users().getUserById(realm, userId);
        if (user == null) {
            return;
        }

        String email = user.getEmail();
        String currentUsername = user.getUsername();

        // Solo cambiar si:
        // 1. El email existe y no es placeholder
        // 2. El username actual NO es ya un email (evitar cambios duplicados)
        if (email != null
                && !email.isEmpty()
                && !email.endsWith(PLACEHOLDER_DOMAIN)
                && !currentUsername.equals(email)) {

            user.setUsername(email);
            System.out.println("[UsernameToEmailListener] Username cambiado: "
                    + currentUsername + " → " + email);
        }
    }

    @Override
    public void onEvent(AdminEvent event, boolean includeRepresentation) {
        // No necesitamos escuchar eventos de admin
    }

    @Override
    public void close() {
        // Nada que limpiar
    }
}

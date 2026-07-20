package cl.rayen.keycloak;

import org.keycloak.Config;
import org.keycloak.authentication.RequiredActionFactory;
import org.keycloak.authentication.RequiredActionProvider;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.KeycloakSessionFactory;

/**
 * Factory para UsernameToEmailAction.
 * El ID "username-to-email-updater" aparece en:
 *   Keycloak → Authentication → Required Actions
 */
public class UsernameToEmailActionFactory implements RequiredActionFactory {

    public static final String PROVIDER_ID = "username-to-email-updater";

    @Override
    public RequiredActionProvider create(KeycloakSession session) {
        return new UsernameToEmailAction();
    }

    @Override
    public void init(Config.Scope config) {
    }

    @Override
    public void postInit(KeycloakSessionFactory factory) {
    }

    @Override
    public void close() {
    }

    @Override
    public String getId() {
        return PROVIDER_ID;
    }

    @Override
    public String getDisplayText() {
        return "Actualizar Username a Email";
    }
}

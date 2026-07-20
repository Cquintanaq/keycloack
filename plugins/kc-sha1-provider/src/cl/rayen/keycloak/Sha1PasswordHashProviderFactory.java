package cl.rayen.keycloak;

import org.keycloak.credential.hash.PasswordHashProvider;
import org.keycloak.credential.hash.PasswordHashProviderFactory;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.KeycloakSessionFactory;

public class Sha1PasswordHashProviderFactory implements PasswordHashProviderFactory {

    @Override
    public PasswordHashProvider create(KeycloakSession session) {
        return new Sha1PasswordHashProvider();
    }

    @Override public void init(org.keycloak.Config.Scope config) {}
    @Override public void postInit(KeycloakSessionFactory factory) {}
    @Override public void close() {}

    @Override
    public String getId() { return Sha1PasswordHashProvider.ID; }
}

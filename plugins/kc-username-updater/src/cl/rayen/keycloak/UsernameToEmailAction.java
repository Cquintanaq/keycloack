package cl.rayen.keycloak;

import org.keycloak.authentication.RequiredActionContext;
import org.keycloak.authentication.RequiredActionProvider;
import org.keycloak.models.UserModel;

/**
 * RequiredAction silenciosa que cambia el username del RUT al email.
 *
 * Flujo:
 * 1. Usuario migrado tiene username = RUT y requiredActions = [UPDATE_PROFILE, username-to-email-updater]
 * 2. Primer login → Keycloak ejecuta UPDATE_PROFILE (el usuario ingresa su email real)
 * 3. Luego ejecuta ESTA acción → detecta que el email ya no es placeholder → cambia username = email
 * 4. La acción se completa silenciosamente (sin formulario) → redirect normal
 * 5. Próximo login: solo funciona con email
 */
public class UsernameToEmailAction implements RequiredActionProvider {

    private static final String PLACEHOLDER_DOMAIN = "@pendiente.rni.cl";

    @Override
    public void evaluateTriggers(RequiredActionContext context) {
        // No es necesario agregar triggers dinámicos.
        // La acción se agrega a los usuarios migrados desde el script Python.
    }

    @Override
    public void requiredActionChallenge(RequiredActionContext context) {
        // Acción silenciosa — no muestra formulario.
        // Evalúa si debe cambiar el username y completa inmediatamente.
        UserModel user = context.getUser();
        String email = user.getEmail();
        String currentUsername = user.getUsername();

        if (email != null
                && !email.isEmpty()
                && !email.endsWith(PLACEHOLDER_DOMAIN)
                && !currentUsername.equals(email)) {

            user.setUsername(email);
            System.out.println("[UsernameToEmailAction] Username cambiado: "
                    + currentUsername + " → " + email);
        } else {
            System.out.println("[UsernameToEmailAction] Sin cambio para usuario: "
                    + currentUsername + " (email=" + email + ")");
        }

        context.success(); // Completa sin mostrar formulario
    }

    @Override
    public void processAction(RequiredActionContext context) {
        // No hay formulario que procesar
        context.success();
    }

    @Override
    public void close() {
        // Nada que limpiar
    }
}

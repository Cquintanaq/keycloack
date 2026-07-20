package cl.rayen.keycloak;

import org.keycloak.credential.hash.PasswordHashProvider;
import org.keycloak.models.PasswordPolicy;
import org.keycloak.models.credential.PasswordCredentialModel;
import java.security.MessageDigest;
import java.nio.charset.StandardCharsets;

public class Sha1PasswordHashProvider implements PasswordHashProvider {

    public static final String ID = "custom-sha1";

    @Override
    public boolean policyCheck(PasswordPolicy policy, PasswordCredentialModel credential) {
        return true;
    }

    @Override
    public PasswordCredentialModel encodedCredential(String rawPassword, int iterations) {
        return PasswordCredentialModel.createFromValues(ID, new byte[0], 0, rawPassword);
    }

    @Override
    public boolean verify(String rawPassword, PasswordCredentialModel credential) {
        // secretData.value  = hash SHA1 en HEX
        // secretData.salt   = salt original de la BD (guardado como bytes UTF-8)
        String storedHash = credential.getPasswordSecretData().getValue();

        // Recuperar salt — guardado como string en los bytes del salt field
        byte[] saltBytes  = credential.getPasswordSecretData().getSalt();
        String salt       = (saltBytes != null && saltBytes.length > 0)
                            ? new String(saltBytes, StandardCharsets.UTF_8)
                            : "";

        // SHA1(password + salt) — replica exactamente FormsAuthentication.HashPasswordForStoringInConfigFile
        String computed   = sha1Hex(rawPassword + salt);
        return computed.equalsIgnoreCase(storedHash);
    }

    @Override
    public void close() {}

    private String sha1Hex(String input) {
        try {
            MessageDigest md    = MessageDigest.getInstance("SHA-1");
            byte[]        bytes = md.digest(input.getBytes(StandardCharsets.UTF_8));
            StringBuilder sb    = new StringBuilder();
            for (byte b : bytes) sb.append(String.format("%02X", b));
            return sb.toString();
        } catch (Exception e) {
            throw new RuntimeException("SHA-1 hash error", e);
        }
    }
}
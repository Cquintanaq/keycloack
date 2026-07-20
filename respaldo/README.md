# Keycloak

Keycloak es la solución central de **Identity and Access Management (IAM)** del sistema RNI. Actúa como **proveedor de identidad (IdP)** confiable, emisor de tokens y gestor de roles, grupos y atributos contextuales. Su configuración está optimizada para cumplir con estándares internacionales de seguridad médica como **HIPAA** y normativas chilenas como la **Ley 20.584** y los lineamientos del **MINSAL**.

<div id='tabla-de-contenidos'></div>

## Tabla de Contenidos

- [Requisitos](#requisitos)
- [Arquitectura](#arquitectura)
  - [Diagrama de secuencias](#diagrama-de-secuencias)
  - [Configuración del Realm y Cliente](#configuración-del-realm-y-cliente)
  - [Seguridad y Cumplimiento](#seguridad-y-cumplimiento)
  - [Modelo de Roles, Grupos y Atributos](#modelo-de-roles-grupos-y-atributos)
  - [Integración con HL7 FHIR / HL7 v5](#integración-con-hl7-fhir--hl7-v5)
  - [Flujos de Autenticación Soportados](#flujos-de-autenticación-soportados)
  - [Endpoint de Atributos de Grupo](#endpoint-de-atributos-de-grupo)
- [Ejecución](#ejecución)
- [Flujo de Autenticación](#flujo-de-autenticación)
- [Licencia](#licencia)

---

<div id='requisitos'></div>

## Requisitos

- **Keycloak 24+**: versión con soporte completo para **PKCE**, **OIDC**, **TOTP**, **WebAuthn** y gestión avanzada de sesiones.
- **PostgreSQL 17**: base de datos relacional recomendada por Keycloak para entornos productivos. Soporta cifrado en reposo y alta disponibilidad.
- **HTTPS obligatorio en producción**: Keycloak **requiere TLS** para todos los endpoints OIDC en producción, como exige HIPAA §164.312(e)(1).
- **Proveedor SMS (opcional)**: para implementar MFA por OTP en roles sensibles, cumpliendo con recomendaciones de NIST SP 800-63B y buenas prácticas HIPAA.

> **HIPAA alignment**: La autenticación fuerte, cifrado en tránsito y persistencia segura de credenciales son controles técnicos obligatorios para el manejo de PHI.

[Volver al menú](#tabla-de-contenidos)

---

<div id='arquitectura'></div>

## Arquitectura

Keycloak se despliega como **IdP centralizado**, emitiendo tokens JWT firmados con **RS256** que contienen **atributos ricos de contexto**: rol clínico, institución, nivel de seguridad, ubicación geográfica y módulos permitidos. Estos tokens son consumidos por el API Gateway y OPA para autorización ABAC.

- **Estándares**: OAuth 2.0, OpenID Connect (OIDC)
- **MFA obligatorio** para roles con acceso a datos sensibles
- **PKCE obligatorio** para aplicaciones públicas (SPA/móvil)
- **Atributos jerárquicos** basados en subgrupos institucionales
- **Validación offline** mediante **JWKS** (`/.well-known/jwks.json`)
- **Cumplimiento**: HIPAA, Ley 20.584, HL7 v5, MINSAL

> **HIPAA alignment**: El uso de estándares abiertos, autenticación multifactor y autorización basada en atributos satisface los requisitos de acceso controlado (§164.312).

[Volver al menú](#tabla-de-contenidos)

---

<div id='diagrama-de-secuencias'></div>

### Diagrama de secuencias

![title](Images/Diagrama.png)

1. **El usuario inicia sesión** desde la app móvil o web.
2. **La app solicita autenticación a Keycloak** usando el flujo **Authorization Code + PKCE**.
3. **Keycloak responde con un QR** para configurar TOTP en Google/Authy.
4. **El usuario escanea el QR** y registra su dispositivo.
5. **La app envía el `code_verifier`** y obtiene un token.
6. **Keycloak valida PKCE y MFA**, y emite un **Access Token con claims ricos**.
7. **El API Gateway recibe la petición** con el token.
8. **El token se valida offline** usando JWKS (no hay llamada en tiempo real a Keycloak).
9. **Los atributos del token** (rol, hospital, ubicación) se envían a **OPA**.
10. **OPA evalúa políticas ABAC** y devuelve `allow/deny`.

> **HIPAA alignment**: Este flujo implementa **defensa en profundidad**: autenticación fuerte + autorización contextual + validación offline segura.

[Volver al menú](#tabla-de-contenidos)

---

<div id='configuración-del-realm-y-cliente'></div>

### Configuración del Realm y Cliente

- **Realm**: `RNI`  
  Aislamiento lógico de usuarios, roles y políticas del sistema RNI.

- **Cliente OIDC**:  
  - **Tipo `public`**: para SPA/móvil → **PKCE obligatorio**  
  - **Tipo `confidential`**: para microservicios → cliente secreto

- **PKCE**:  
  - `S256` como método de desafío  
  - `Enforce PKCE = true` → evita robo de código de autorización

- **Redirect URIs restringidas**:  
  Solo dominios autorizados (`https://app.rni.cl/*`) → previene ataques de redirección

- **Request Object Required = true**:  
  Asegura que los parámetros del flujo OIDC no sean manipulados

- **Temas personalizados**:  
  Logo institucional en **PNG**, mensajes en español, diseño alineado con marca

> **HIPAA alignment**: Estas medidas protegen contra interceptación de tokens, phishing y manipulación de flujos de autenticación, cumpliendo con §164.312(a)(2)(ii).

[Volver al menú](#tabla-de-contenidos)

---

<div id='seguridad-y-cumplimiento'></div>

### Seguridad y Cumplimiento

#### Políticas de Contraseña
- Mínimo **12 caracteres**  
- Requiere mayúsculas, minúsculas, números y símbolos  
- Expiración cada **90 días**  
- Historial de **5 contraseñas**  
- Bloqueo tras **5 intentos fallidos**

> **HIPAA**: Aunque no especifica reglas de contraseña, exige “controles técnicos razonables” (§164.306). Estas políticas superan los mínimos de NIST.

#### MFA (Autenticación Multifactor)
- **Obligatorio** para roles: `médico`, `químico farmacéutico`, `administrador`
- **Métodos soportados**: TOTP, WebAuthn (FIDO2), SMS OTP
- **ACR = 2** requerido para acceso a PHI

> **HIPAA**: MFA es una “medida razonable y apropiada” para proteger datos sensibles (OCR Guidance, 2023).

#### Firma y Cifrado
- **Firma**: `RS256` (algoritmo criptográfico moderno y no reversible)
- **Cifrado opcional**: `RSA-OAEP + AES-256-GCM` para ID Tokens
- **JWKS**: validación offline en el gateway → reduce dependencias y riesgo

> **HIPAA**: Cumple con §164.312(c)(1) (integridad) y §164.312(e)(2)(ii) (confidencialidad).

[Volver al menú](#tabla-de-contenidos)

---

<div id='modelo-de-roles-grupos-y-atributos'></div>

### Modelo de Roles, Grupos y Atributos

Keycloak **no usa roles planos**. En su lugar, emplea una **estructura jerárquica de subgrupos** que refleja la organización real del sistema de salud:

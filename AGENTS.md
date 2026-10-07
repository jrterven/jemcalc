# Jem Calc: Android, iOS y web

- Todo cambio de funcionalidad, interfaz o corrección debe aplicarse y mantenerse compatible con **Android, iOS y la webapp**. No dar por terminado un cambio comprobando únicamente una plataforma.
- Compartir la interfaz, el motor matemático y el estado entre las tres plataformas. Aislar adaptadores específicos (WebView/HTML, almacenamiento, HTTP/WebSocket, archivos) con importaciones condicionales; no importar `dart:io` en código compartido con web.
- El cálculo debe seguir siendo determinista: motor local o CAS. Los modelos de IA reconocen entradas; no producen el resultado matemático.
- Validar según el alcance: analizador y pruebas pertinentes, compilaciones Android/iOS/web cuando se modifiquen adaptadores o dependencias, y revisión de la interfaz afectada en navegador y dispositivos disponibles. Informar cualquier plataforma que no se haya podido comprobar.
- No incluir claves de proveedores ni tokens privados en assets o compilaciones web. Credenciales en `server/.env`; configuración privada en `.local/`, ambos ignorados por Git.

## Puertos locales

- **Webapp y proxy local: `127.0.0.1:5187`**, URL habitual **http://localhost:5187**. Mantener este origen estable para conservar el historial del navegador.
- El 6 de octubre de 2026 se revisaron los listeners con `lsof`, las configuraciones de proyectos bajo `/Users/juanterven/dev` y se verificó mediante bind que **5187** estaba libre en IPv4 e IPv6. No apareció asignado a otro proyecto. Es una asignación de este proyecto, no una reserva permanente del sistema operativo.
- Antes de arrancar, comprobar que 5187 sigue libre o corresponde a Jem Calc. Si pertenece a otro proceso, no detenerlo ni elegir otro puerto silenciosamente; identificar el conflicto.
- El backend privado existente utiliza **8443** en la dirección LAN configurada en `.local/pilot.json`. No cambiarlo ni usar puertos de otros proyectos.
- Para ejecutar la web local usar `server/.venv/bin/python scripts/run_web.py`; consultar el README para compilarla. El proxy local escucha solo en loopback y verifica el certificado TLS del backend. No publicarlo en la LAN o Internet como si fuera un servicio autenticado de producción.

## Piloto en el servidor dedicado

- URL pública: **https://calc.jemailabs.com**, API de Android/iOS: **https://calc.jemailabs.com/api**. Acceso SSH: `juan@prod`.
- Despliegue independiente en `/home/juan/jemcalc`, contenedor Compose `jemcalc-app-1`, puerto **127.0.0.1:5188 → 8080**. Se comprobó libre antes de asignarlo. No abrirlo a la red ni reutilizar puertos de otros proyectos.
- Nginx usa `/etc/nginx/sites-available/calc.jemailabs.com.conf`. Cloudflare tiene un registro A `calc` con proxy activo y SSL **Full (strict)**; el origen usa el certificado wildcard existente de jemailabs.com. No modificar los otros virtual hosts ni registros DNS.
- Mantener la web como **piloto privado con clave**, según la elección del usuario. `jemcalc.production` protege la web con una cookie firmada, HttpOnly y Secure; las apps conservan su token. No quitar la autenticación ni inyectar el token con el proxy local en Internet.
- Credenciales remotas: `/home/juan/jemcalc/shared/.env`, permisos 600. La copia privada local y la clave de acceso están en `.local/production.env` y `.local/production-access.txt`; no incluirlas en Git, imágenes Docker, logs o builds Flutter.
- Procedimientos de actualización, validación y reversión: `deploy/README.md`.

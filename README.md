# MartinezCh. Cristhian — análisis deportivo

App web responsive de una página. El frontend se publica en GitHub Pages y consume el calendario del Edge Function de Supabase. La autenticación y el historial usan Supabase Auth y Postgres con Row Level Security (RLS).

## Estado del proyecto conectado

- Proyecto Supabase: `martinez-deportes` (`sa-east-1`, São Paulo).
- Calendario: football-data.org; la clave se guarda como secreto de Edge Functions (`FOOTBALL_DATA_API_KEY`) y nunca se publica en este repositorio.
- Hoy se muestran los partidos que devuelve la fuente para la fecha local de Ecuador; si no hay, se muestra cero, sin inventar eventos.
- football-data.org no se asume como fuente de cuotas. Los picks publicados requieren que el administrador introduzca y verifique una cuota real.
- OpenRouter no interviene en la creación de datos deportivos ni de picks.

## Archivos

- `index.html`: sitio interactivo para GitHub Pages.
- `martinez-app.ts`: código fuente de la función de Supabase que sirve el calendario.
- `schema.sql`: esquema y políticas RLS iniciales. No contiene claves API ni correos personales.

## Seguridad

- La clave de football-data.org debe existir solo en los secretos del proyecto Supabase como `FOOTBALL_DATA_API_KEY`.
- La clave `sb_publishable_...` que usa el navegador es una clave pública de Supabase; RLS debe permanecer habilitado.
- No subir nunca claves `service_role`, tokens, contraseñas ni archivos `.env`.
- RLS permite leer partidos y picks publicados; solo la cuenta administradora puede publicar picks o liquidar resultados.
- El correo del administrador autorizado para el proyecto actual está guardado en una tabla del esquema `private` de Supabase, no en GitHub. En una instalación nueva, agrega de manera privada el correo del propietario a `private.admin_bootstrap_emails` antes de registrarse.

## Prueba

1. Abre el sitio en la fecha actual de Ecuador. La lista consulta football-data.org mediante la Edge Function de Supabase.
2. Regístrate con el correo permitido para administración y confirma el email si Supabase lo solicita.
3. El administrador puede registrar picks manuales con cuota y probabilidad, y después anotar el resultado.
4. Las tarjetas de rendimiento y el gráfico permanecen vacíos hasta que existan picks liquidados; no se precargan cifras ficticias.

## Límites

- El número de competiciones y datos disponibles depende del plan de football-data.org.
- Los resultados y la liquidación de picks son manuales en esta primera versión.
- No es una plataforma de apuestas ni promete ganancias. Apuesta solo si eres mayor de edad y puedes asumir pérdidas.

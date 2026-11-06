# Marca por workspace

La instalación Community usa Ni.CO por defecto. Cada workspace puede definir su nombre, logo, color y sitio web desde **Ajustes → Marca del workspace**. Solo los administradores pueden guardar cambios o restablecer la marca inicial.

1. Escribe el nombre y el sitio web de la marca.
2. Sube un logo PNG, JPG o WebP de hasta 2 MB. El contenido del archivo se valida en el servidor; no se aceptan SVG subidos por usuarios.
3. Elige el color y revisa la vista previa. Los controles adaptan el contraste y tienen versiones clara y oscura.
4. Guarda los cambios. El panel y los chats web de esa cuenta usarán la marca. Los correos asociados a la cuenta también la incluyen, sin cambiar el remitente SMTP.
5. Copia el enlace de acceso para mostrar esa marca antes de iniciar sesión. El enlace identifica la marca pública del workspace; no inicia sesión ni concede permisos.

El acceso general `/app/login` muestra Ni.CO. Una vez autenticado, el panel resuelve la marca de la cuenta activa y la actualiza al cambiar de workspace. Las pantallas y correos sin una cuenta asociada conservan Ni.CO.

## Implementación

La configuración vive en `accounts.settings.workspace_branding`; el logo usa Active Storage y el volumen de archivos existente. No requiere migraciones. `GET`, `PATCH` y `DELETE /api/v1/accounts/:account_id/workspace_branding` reutilizan la autenticación y las políticas de cuenta. La eliminación restablece exclusivamente esta configuración y su logo.

Los tokens y el icono Ni.CO provienen del proyecto GENESIS (`Custom SHADCN`, commit `db4c13ea76ee865fd9f59782acfe472d707bf4e3`). Se adaptaron al sistema nativo Vue y Tailwind de Chatwoot; no se añadieron componentes React ni dependencias de interfaz. Los valores dinámicos se aplican como variables de diseño en una hoja de estilos, mientras los componentes usan utilidades Tailwind.

Esta es una implementación propia para Community, independiente del branding Enterprise. No modifica licencias, planes, bloqueos Enterprise ni el desarrollo propio de WhatsApp Calling. El nuevo copy del fork se mantiene en el catálogo fuente y usa español, como requiere esta instalación.

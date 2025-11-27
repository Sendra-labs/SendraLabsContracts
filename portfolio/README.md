# Nexus Protocol - Portfolio Web

Sitio web profesional que explica la arquitectura de proxies del protocolo Nexus, diseñado para desarrolladores y técnicos.

## 🚀 Características

- **Diseño Moderno**: Interfaz elegante con tema oscuro optimizado para desarrolladores
- **Diagramas Visuales**: Explicaciones visuales del flujo de proxies
- **Código Destacado**: Ejemplos de código con sintaxis destacada
- **Responsive**: Adaptado para móviles, tablets y desktop
- **Animaciones Suaves**: Transiciones y efectos visuales profesionales

## 📁 Estructura

```
portfolio/
├── index.html      # Página principal
├── styles.css      # Estilos CSS
├── script.js       # JavaScript para interactividad
└── README.md       # Este archivo
```

## 🎨 Secciones

1. **Hero**: Introducción al sistema de proxies
2. **Problema**: Explicación del problema que resuelven los proxies
3. **Solución**: Cómo los proxies solucionan el problema
4. **Arquitectura**: Componentes del sistema (ProxyFactory, ProxyManager, etc.)
5. **Flujo**: Timeline detallado del flujo de ejecución
6. **Código**: Ejemplos de implementación
7. **Beneficios**: Ventajas de la arquitectura

## 🛠️ Uso

### Desarrollo Local

1. Clona o descarga los archivos
2. Abre `index.html` en tu navegador
3. O usa un servidor local:

```bash
# Con Python
python -m http.server 8000

# Con Node.js (http-server)
npx http-server

# Con PHP
php -S localhost:8000
```

### Personalización

- **Colores**: Modifica las variables CSS en `styles.css` (`:root`)
- **Contenido**: Edita `index.html` para cambiar textos y secciones
- **Animaciones**: Ajusta `script.js` para modificar comportamientos

## 🎯 Características Técnicas

- **Sin Dependencias**: HTML, CSS y JavaScript puro
- **Performance**: Optimizado para carga rápida
- **Accesibilidad**: Estructura semántica HTML5
- **SEO Friendly**: Meta tags y estructura optimizada

## 📝 Personalización

### Cambiar Colores

Edita las variables en `styles.css`:

```css
:root {
    --accent-primary: #6366f1;  /* Color principal */
    --accent-secondary: #8b5cf6; /* Color secundario */
    /* ... más variables */
}
```

### Agregar Secciones

Copia la estructura de una sección existente y modifica el contenido en `index.html`.

### Modificar Diagramas

Los diagramas están en las secciones `.diagram-content`. Puedes agregar más elementos `.flow-box` y estilizarlos.

## 🚀 Deploy

### GitHub Pages

1. Sube los archivos a un repositorio de GitHub
2. Ve a Settings > Pages
3. Selecciona la rama `main` y carpeta `/` (root)
4. Accede a `https://tu-usuario.github.io/portfolio/`

### Netlify

1. Arrastra la carpeta `portfolio` a [Netlify Drop](https://app.netlify.com/drop)
2. O conecta tu repositorio de GitHub

### Vercel

```bash
npm i -g vercel
vercel
```

## 📄 Licencia

Este portfolio es de código abierto y está disponible bajo la licencia MIT.

## 🤝 Contribuciones

Las contribuciones son bienvenidas. Por favor:

1. Fork el proyecto
2. Crea una rama para tu feature
3. Commit tus cambios
4. Push a la rama
5. Abre un Pull Request

## 📧 Contacto

Para preguntas o sugerencias sobre este portfolio, por favor abre un issue en el repositorio.

---

**Nexus Protocol** - Arquitectura avanzada para estrategias DeFi complejas


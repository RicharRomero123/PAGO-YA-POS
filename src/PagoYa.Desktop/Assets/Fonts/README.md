# Fuentes de PagoYa

El sistema de diseño usa dos familias de **Google Fonts** (gratis, licencia SIL OFL):

| Uso en la UI | Familia | Archivo `.ttf` a colocar aquí |
|--------------|---------|-------------------------------|
| Títulos / marca (H1, TOTAL, wordmark) | **Baloo 2 ExtraBold** | `Baloo2-ExtraBold.ttf` |
| UI / datos / precios (números tabulares) | **Nunito** | `Nunito-Regular.ttf`, `Nunito-SemiBold.ttf`, `Nunito-Bold.ttf` |

## Descarga

- Baloo 2: https://fonts.google.com/specimen/Baloo+2 (peso ExtraBold / 800)
- Nunito:  https://fonts.google.com/specimen/Nunito (pesos Regular 400, SemiBold 600, Bold 700)

Descarga los archivos, extrae los `.ttf` indicados y cópialos **en esta carpeta**.

## Importante: el build NO depende de los .ttf

`Themes/PagoYaTheme.xaml` declara las FontFamily con **fallback embebido**, por ejemplo:

```xml
<FontFamily x:Key="FuenteMarca">./Assets/Fonts/#Baloo 2, Segoe UI</FontFamily>
<FontFamily x:Key="FuenteUI">./Assets/Fonts/#Nunito, Segoe UI</FontFamily>
```

Si los `.ttf` aún no están presentes, WPF cae automáticamente a **Segoe UI** y la
aplicación compila y corre igual. Al colocar los `.ttf`, la marca toma su
tipografía real sin tocar código. El `.csproj` incluye `Assets\Fonts\*.ttf`
como `Resource` con glob, así que basta con dejar los archivos aquí.

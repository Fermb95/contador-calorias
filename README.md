# Balance · contador de calorías personal

App Android (Flutter) de uso personal: objetivo calórico según perfil, registro de alimentos
(genéricos + supermercados vía Open Food Facts + escáner de código de barras), raciones caseras,
favoritos, recetas, comidas guardadas, ejercicio (tabla MET + Health Connect), agua, peso con
tendencia y gasto real estimado, histórico diario/semanal/mensual y notificaciones.

## Compilar
Cada push a `main` compila el APK con GitHub Actions (pestaña *Actions* o *Releases*).
En local: `flutter create --platforms=android --org com.fernando --project-name balance . && python3 tool/patch_android.py && flutter build apk`.

La firma (`android/app/release.jks`) es fija para que las actualizaciones se instalen encima sin perder datos.
No borres ese archivo.

## Datos
- `tool/foods_source.txt` → base de alimentos genéricos. Regenerar con `python3 tool/build_foods.py`.
- Todo se guarda solo en el móvil (SQLite). Ajustes → Copia de seguridad para exportar/restaurar.

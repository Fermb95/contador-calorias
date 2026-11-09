import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../db.dart';
import '../label_ocr.dart';
import '../models.dart';
import '../util.dart';
import 'scanner_screen.dart';

/// Crear o editar un alimento (valores por 100 g / 100 ml). Devuelve el alimento guardado.
class FoodEditorScreen extends StatefulWidget {
  final Food food;
  final bool autoOcr;
  const FoodEditorScreen({super.key, required this.food, this.autoOcr = false});

  @override
  State<FoodEditorScreen> createState() => _FoodEditorScreenState();
}

class _PortionRow {
  final TextEditingController name;
  final TextEditingController grams;
  _PortionRow(String n, String g)
      : name = TextEditingController(text: n),
        grams = TextEditingController(text: g);
}

class _FoodEditorScreenState extends State<FoodEditorScreen> {
  late final Food f = widget.food;
  late final name = TextEditingController(text: f.name);
  late final brand = TextEditingController(text: f.brand ?? '');
  late final barcode = TextEditingController(text: f.barcode ?? '');
  late final kcal = TextEditingController(text: _n(f.kcal, zeroEmpty: true));
  late final protein = TextEditingController(text: _n(f.protein, zeroEmpty: f.kcal == 0));
  late final carbs = TextEditingController(text: _n(f.carbs, zeroEmpty: f.kcal == 0));
  late final fat = TextEditingController(text: _n(f.fat, zeroEmpty: f.kcal == 0));
  late final sugar = TextEditingController(text: _n(f.sugar));
  late final satFat = TextEditingController(text: _n(f.satFat));
  late final fiber = TextEditingController(text: _n(f.fiber));
  late final salt = TextEditingController(text: _n(f.salt));
  late bool liquid = f.liquid;
  late final List<_PortionRow> portions = f.portions.map((p) => _PortionRow(p.name, _n(p.grams))).toList();
  bool perServing = false;
  final servingGrams = TextEditingController();

  static String _n(double? v, {bool zeroEmpty = false}) {
    if (v == null || (zeroEmpty && v == 0)) return '';
    return fmtNum(v, 2).replaceAll('.', '');
  }

  bool _reading = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoOcr) WidgetsBinding.instance.addPostFrameCallback((_) => _readLabel(ImageSource.camera));
  }

  String _v(double v) => fmtNum(v, 2).replaceAll('.', '');

  Future<void> _readLabel(ImageSource source) async {
    final XFile? img;
    try {
      img = await ImagePicker().pickImage(source: source, maxWidth: 2400, maxHeight: 2400, imageQuality: 92);
    } catch (e) {
      if (mounted) toast(context, 'No se pudo abrir la cámara: $e');
      return;
    }
    if (img == null) return;
    setState(() => _reading = true);
    try {
      final r = await LabelOcr.readFile(img.path);
      if (!mounted) return;
      if (r.found == 0) {
        toast(context, 'No he encontrado la tabla nutricional. Prueba más cerca, recta y con buena luz.');
        return;
      }
      setState(() {
        void put(TextEditingController c, double? v) {
          if (v != null) c.text = _v(v);
        }

        put(kcal, r.kcal?.roundToDouble());
        put(protein, r.protein);
        put(carbs, r.carbs);
        put(sugar, r.sugar);
        put(fat, r.fat);
        put(satFat, r.satFat);
        put(fiber, r.fiber);
        put(salt, r.salt);
        if (r.liquid) liquid = true;
        perServing = !r.perHundred;
      });
      toast(context, 'Leídos ${r.found} valores${r.perHundred ? ' (por 100 ${r.liquid ? 'ml' : 'g'})' : ' (parece por ración: indica sus gramos)'}. '
          'Revísalos con la etiqueta.');
    } catch (e) {
      if (mounted) toast(context, 'Error al leer la etiqueta: $e');
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _scan() async {
    final code = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const ScannerScreen()));
    if (code != null) setState(() => barcode.text = code);
  }

  void _autoKcal() {
    final p = parseNum(protein.text) ?? 0, c = parseNum(carbs.text) ?? 0, g = parseNum(fat.text) ?? 0;
    final fi = parseNum(fiber.text) ?? 0;
    setState(() => kcal.text = fmtNum(p * 4 + c * 4 + g * 9 + fi * 2).replaceAll('.', ''));
  }

  Future<void> _save() async {
    final n = name.text.trim();
    var k = parseNum(kcal.text);
    if (n.isEmpty || k == null) {
      toast(context, 'Pon al menos el nombre y las kcal');
      return;
    }
    var factor = 1.0;
    if (perServing) {
      final sg = parseNum(servingGrams.text);
      if (sg == null || sg <= 0) {
        toast(context, 'Indica cuántos gramos tiene la ración');
        return;
      }
      factor = 100 / sg;
    }
    double? v(TextEditingController c) {
      final x = parseNum(c.text);
      return x == null ? null : x * factor;
    }

    f
      ..name = n
      ..brand = brand.text.trim().isEmpty ? null : brand.text.trim()
      ..barcode = barcode.text.trim().isEmpty ? null : barcode.text.trim()
      ..kcal = k * factor
      ..protein = v(protein) ?? 0
      ..carbs = v(carbs) ?? 0
      ..fat = v(fat) ?? 0
      ..sugar = v(sugar)
      ..satFat = v(satFat)
      ..fiber = v(fiber)
      ..salt = v(salt)
      ..liquid = liquid
      ..portions = [
        for (final r in portions)
          if (r.name.text.trim().isNotEmpty && (parseNum(r.grams.text) ?? 0) > 0)
            Portion(r.name.text.trim(), parseNum(r.grams.text)!),
        if (perServing && !portions.any((r) => r.name.text.trim() == 'ración'))
          Portion('ración', parseNum(servingGrams.text)!),
      ];
    if (f.source == 'base' && f.id == null) f.source = 'custom';
    if (f.id == null && f.source != 'off' && f.source != 'recipe') f.source = 'custom';
    await Db.saveFood(f);
    if (mounted) Navigator.pop(context, f);
  }

  Widget _num(TextEditingController c, String label, {String suffix = 'g'}) => Expanded(
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, suffixText: suffix, isDense: true),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final ts = Theme.of(context).textTheme;
    final u = liquid ? 'ml' : 'g';
    return Scaffold(
      appBar: AppBar(title: Text(f.id == null ? 'Nuevo alimento' : 'Editar alimento')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre *'), textCapitalization: TextCapitalization.sentences),
          const SizedBox(height: 10),
          TextField(controller: brand, decoration: const InputDecoration(labelText: 'Marca / supermercado')),
          const SizedBox(height: 10),
          TextField(
            controller: barcode,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Código de barras',
              suffixIcon: IconButton(icon: const Icon(Icons.qr_code_scanner), onPressed: _scan),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Es una bebida (se mide en ml)'),
            value: liquid,
            onChanged: (v) => setState(() => liquid = v),
          ),
          const Divider(),
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _reading
                  ? const Row(children: [
                      SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 14),
                      Text('Leyendo la etiqueta…'),
                    ])
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('¿Tienes el envase delante?', style: ts.titleSmall),
                      const SizedBox(height: 4),
                      Text('Haz una foto a la tabla nutricional y relleno los valores por ti.', style: ts.bodySmall),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, children: [
                        FilledButton.tonalIcon(
                          onPressed: () => _readLabel(ImageSource.camera),
                          icon: const Icon(Icons.document_scanner),
                          label: const Text('Leer etiqueta'),
                        ),
                        TextButton.icon(
                          onPressed: () => _readLabel(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Desde galería'),
                        ),
                      ]),
                    ]),
            ),
          ),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text('Valores por 100 $u')),
              const ButtonSegment(value: true, label: Text('Por ración')),
            ],
            selected: {perServing},
            onSelectionChanged: (s) => setState(() => perServing = s.first),
          ),
          if (perServing) ...[
            const SizedBox(height: 10),
            TextField(
              controller: servingGrams,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Tamaño de la ración', suffixText: u),
            ),
          ],
          const SizedBox(height: 14),
          Row(children: [
            _num(kcal, 'Energía *', suffix: 'kcal'),
            IconButton(tooltip: 'Calcular kcal a partir de los macros', icon: const Icon(Icons.calculate_outlined), onPressed: _autoKcal),
          ]),
          const SizedBox(height: 10),
          Row(children: [_num(protein, 'Proteínas'), const SizedBox(width: 8), _num(carbs, 'Hidratos'), const SizedBox(width: 8), _num(fat, 'Grasas')]),
          const SizedBox(height: 10),
          Row(children: [_num(sugar, 'Azúcares'), const SizedBox(width: 8), _num(satFat, 'Saturadas'), const SizedBox(width: 8), _num(fiber, 'Fibra')]),
          const SizedBox(height: 10),
          Row(children: [_num(salt, 'Sal'), const Spacer(flex: 2)]),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: Text('Medidas caseras', style: ts.titleSmall)),
            TextButton.icon(
                onPressed: () => setState(() => portions.add(_PortionRow('', ''))), icon: const Icon(Icons.add), label: const Text('Añadir')),
          ]),
          Text('Ej.: «unidad» 60 g, «rebanada» 30 g, «vaso» 250 ml. Así luego registras por unidades.', style: ts.bodySmall),
          const SizedBox(height: 8),
          for (final r in portions)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(
                    flex: 3,
                    child: TextField(controller: r.name, decoration: const InputDecoration(labelText: 'Nombre', isDense: true))),
                const SizedBox(width: 8),
                _num(r.grams, 'Peso', suffix: u),
                IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => portions.remove(r))),
              ]),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('Guardar alimento'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
        ),
      ),
    );
  }
}

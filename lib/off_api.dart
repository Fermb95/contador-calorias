import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Filtros de supermercado: (etiqueta, tipo de filtro OFF, valor).
class StoreFilter {
  final String label;
  final String tagType;
  final String value;
  const StoreFilter(this.label, this.tagType, this.value);
}

const storeFilters = <StoreFilter>[
  StoreFilter('Todos', '', ''),
  StoreFilter('Mercadona (Hacendado)', 'brands', 'hacendado'),
  StoreFilter('Carrefour', 'brands', 'carrefour'),
  StoreFilter('Alcampo (Auchan)', 'brands', 'auchan'),
  StoreFilter('Lidl', 'stores', 'lidl'),
  StoreFilter('Dia', 'brands', 'dia'),
  StoreFilter('Eroski', 'brands', 'eroski'),
  StoreFilter('Consum', 'brands', 'consum'),
];

/// Cliente de Open Food Facts (base abierta y gratuita, licencia ODbL).
class OffApi {
  static const _ua = 'BalanceContadorCalorias/1.0 (uso personal)';
  static const _fields =
      'code,product_name,product_name_es,generic_name_es,brands,nutriments,serving_quantity,serving_size,quantity';

  static Future<List<Food>> search(String query, StoreFilter filter) async {
    final params = <String, String>{
      'search_terms': query,
      'search_simple': '1',
      'action': 'process',
      'json': '1',
      'page_size': '40',
      'sort_by': 'unique_scans_n',
      'fields': _fields,
    };
    if (filter.tagType.isNotEmpty) {
      params['tagtype_0'] = filter.tagType;
      params['tag_contains_0'] = 'contains';
      params['tag_0'] = filter.value;
    }
    final uri = Uri.https('es.openfoodfacts.org', '/cgi/search.pl', params);
    final res = await http.get(uri, headers: {'User-Agent': _ua}).timeout(const Duration(seconds: 25));
    if (res.statusCode == 429) throw Exception('Demasiadas búsquedas seguidas. Espera un minuto.');
    if (res.statusCode != 200) throw Exception('Error ${res.statusCode} al buscar.');
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final products = (j['products'] as List? ?? []);
    final out = <Food>[];
    for (final p in products) {
      final f = parseProduct(p as Map<String, dynamic>);
      if (f != null) out.add(f);
    }
    return out;
  }

  static Future<Food?> byBarcode(String code) async {
    final uri = Uri.https('world.openfoodfacts.org', '/api/v2/product/$code.json', {'fields': _fields});
    final res = await http.get(uri, headers: {'User-Agent': _ua}).timeout(const Duration(seconds: 20));
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) throw Exception('Error ${res.statusCode} al consultar el código.');
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (j['status'] != 1 || j['product'] == null) return null;
    final p = Map<String, dynamic>.from(j['product'] as Map);
    p['code'] ??= code;
    return parseProduct(p);
  }

  static double? _num(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '.'));
  }

  static Food? parseProduct(Map<String, dynamic> p) {
    final n = (p['nutriments'] as Map?)?.cast<String, dynamic>() ?? {};
    var kcal = _num(n['energy-kcal_100g']);
    if (kcal == null) {
      final kj = _num(n['energy_100g']) ?? _num(n['energy-kj_100g']);
      if (kj != null) kcal = kj / 4.184;
    }
    if (kcal == null) return null;
    String name = (p['product_name_es'] as String?)?.trim() ?? '';
    if (name.isEmpty) name = (p['product_name'] as String?)?.trim() ?? '';
    if (name.isEmpty) name = (p['generic_name_es'] as String?)?.trim() ?? '';
    if (name.isEmpty) return null;
    var brand = (p['brands'] as String?)?.split(',').first.trim();
    if (brand != null && brand.isEmpty) brand = null;
    final quantity = (p['quantity'] as String?) ?? '';
    final liquid = RegExp(r'\d\s*(ml|cl|l)\b', caseSensitive: false).hasMatch(quantity);

    final portions = <Portion>[];
    final sq = _num(p['serving_quantity']);
    if (sq != null && sq > 0) {
      final ss = (p['serving_size'] as String?)?.trim();
      portions.add(Portion(ss != null && ss.isNotEmpty ? 'ración ($ss)' : 'ración', sq));
    }
    final multi = RegExp(r'(\d+)\s*[x×]\s*(\d+[.,]?\d*)\s*(g|ml|cl)', caseSensitive: false).firstMatch(quantity);
    if (multi != null) {
      var g = double.parse(multi.group(2)!.replaceAll(',', '.'));
      if (multi.group(3)!.toLowerCase() == 'cl') g *= 10;
      portions.add(Portion('unidad del pack', g));
    } else {
      final single = RegExp(r'(\d+[.,]?\d*)\s*(kg|g|ml|cl|l)\b', caseSensitive: false).firstMatch(quantity);
      if (single != null) {
        var g = double.parse(single.group(1)!.replaceAll(',', '.'));
        switch (single.group(2)!.toLowerCase()) {
          case 'kg':
          case 'l':
            g *= 1000;
          case 'cl':
            g *= 10;
        }
        if (g > 0 && g <= 3000) portions.add(Portion('envase completo', g));
      }
    }

    return Food(
      name: name,
      brand: brand,
      barcode: p['code']?.toString(),
      kcal: kcal,
      protein: _num(n['proteins_100g']) ?? 0,
      carbs: _num(n['carbohydrates_100g']) ?? 0,
      fat: _num(n['fat_100g']) ?? 0,
      fiber: _num(n['fiber_100g']),
      sugar: _num(n['sugars_100g']),
      satFat: _num(n['saturated-fat_100g']),
      salt: _num(n['salt_100g']),
      liquid: liquid,
      portions: portions,
      source: 'off',
    );
  }
}

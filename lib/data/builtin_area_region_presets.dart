import 'area_presets/ancient_area_presets.dart';
import 'area_presets/anubis_area_presets.dart';
import 'area_presets/builtin_area_preset.dart';
import 'area_presets/cache_area_presets.dart';
import 'area_presets/dust2_area_presets.dart';
import 'area_presets/inferno_area_presets.dart';
import 'area_presets/mirage_area_presets.dart';
import 'area_presets/nuke_area_presets.dart';
import 'area_presets/overpass_area_presets.dart';
import 'area_presets/train_area_presets.dart';
import 'area_presets/vertigo_area_presets.dart';

export 'area_presets/builtin_area_preset.dart';

/// 内置地图默认区域几何预设总表，按地图标识聚合各楼层预设。
const Map<String, Map<String, List<BuiltinAreaPreset>>>
    builtinAreaRegionPresets = {
  'mirage': mirageAreaRegionPresets,
  'inferno': infernoAreaRegionPresets,
  'dust2': dust2AreaRegionPresets,
  'overpass': overpassAreaRegionPresets,
  'ancient': ancientAreaRegionPresets,
  'anubis': anubisAreaRegionPresets,
  'train': trainAreaRegionPresets,
  'nuke': nukeAreaRegionPresets,
  'cache': cacheAreaRegionPresets,
  'vertigo': vertigoAreaRegionPresets,
};

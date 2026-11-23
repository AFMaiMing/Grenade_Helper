import 'package:flutter/material.dart';

/// HSL 颜色分量调节滑块组。
class HslColorSliders extends StatelessWidget {
  final double hue;
  final double saturation;
  final double lightness;
  final ValueChanged<double> onHueChanged;
  final ValueChanged<double> onSaturationChanged;
  final ValueChanged<double> onLightnessChanged;

  const HslColorSliders({
    super.key,
    required this.hue,
    required this.saturation,
    required this.lightness,
    required this.onHueChanged,
    required this.onSaturationChanged,
    required this.onLightnessChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _HslGradientSlider(
          label: '色相',
          value: hue,
          min: 0,
          max: 360,
          gradient: LinearGradient(
            colors: List.generate(
              7,
              (i) => HSLColor.fromAHSL(1, i * 60.0, saturation, lightness)
                  .toColor(),
            ),
          ),
          onChanged: onHueChanged,
        ),
        const SizedBox(height: 8),
        _HslGradientSlider(
          label: '饱和度',
          value: saturation,
          min: 0,
          max: 1,
          gradient: LinearGradient(
            colors: [
              HSLColor.fromAHSL(1, hue, 0, lightness).toColor(),
              HSLColor.fromAHSL(1, hue, 1, lightness).toColor(),
            ],
          ),
          onChanged: onSaturationChanged,
        ),
        const SizedBox(height: 8),
        _HslGradientSlider(
          label: '亮度',
          value: lightness,
          min: 0,
          max: 1,
          gradient: LinearGradient(
            colors: [
              HSLColor.fromAHSL(1, hue, saturation, 0).toColor(),
              HSLColor.fromAHSL(1, hue, saturation, 0.5).toColor(),
              HSLColor.fromAHSL(1, hue, saturation, 1).toColor(),
            ],
          ),
          onChanged: onLightnessChanged,
        ),
      ],
    );
  }
}

class _HslGradientSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final Gradient gradient;
  final ValueChanged<double> onChanged;

  const _HslGradientSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.gradient,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 50,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 24,
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 24,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                trackShape: const RoundedRectSliderTrackShape(),
                activeTrackColor: Colors.transparent,
                inactiveTrackColor: Colors.transparent,
                thumbColor: Colors.white,
              ),
              child: Slider(
                value: value,
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

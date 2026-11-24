import 'package:flutter/material.dart';

import '../../models/tag.dart';
import '../../widgets/color_picker_widget.dart';

/// 可复用的地图区域模板选项。
class AreaTemplateOption {
  final int areaId;
  final String label;

  const AreaTemplateOption({
    required this.areaId,
    required this.label,
  });
}

/// 新建或编辑标签弹窗。
class TagEditDialog extends StatefulWidget {
  final String? initialName;
  final int? initialColor;
  final int? initialDimension;
  final List<AreaTemplateOption> areaTemplateOptions;

  const TagEditDialog({
    super.key,
    this.initialName,
    this.initialColor,
    this.initialDimension,
    this.areaTemplateOptions = const [],
  });

  @override
  State<TagEditDialog> createState() => _TagEditDialogState();
}

class _TagEditDialogState extends State<TagEditDialog> {
  late TextEditingController _nameController;
  late int _selectedColor;
  late int _selectedDimension;
  String _areaSetupMode = 'none';
  int? _sourceAreaId;
  bool _continueEditAfterReuse = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName ?? '');
    _selectedColor = widget.initialColor ?? presetColors.first;
    _selectedDimension = widget.initialDimension ?? TagDimension.custom;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Widget _buildAreaSetupSection() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _areaSetupMode,
          decoration: const InputDecoration(
            labelText: '区域数据快捷操作',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'none', child: Text('仅创建标签（稍后配置）')),
            DropdownMenuItem(value: 'edit', child: Text('立即绘制区域')),
            DropdownMenuItem(value: 'reuse', child: Text('复用已有区域数据')),
          ],
          onChanged: (val) {
            if (val == null) return;
            setState(() {
              _areaSetupMode = val;
              if (val != 'reuse') {
                _sourceAreaId = null;
                _continueEditAfterReuse = false;
              }
            });
          },
        ),
        if (_areaSetupMode == 'reuse') ...[
          const SizedBox(height: 12),
          if (widget.areaTemplateOptions.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.4),
                ),
                color: Colors.orange.withValues(alpha: 0.12),
              ),
              child: const Text(
                '当前地图还没有可复用的区域数据，请先创建区域或改为“创建后立即绘制区域”。',
                style: TextStyle(fontSize: 12),
              ),
            )
          else
            DropdownButtonFormField<int>(
              initialValue: _sourceAreaId,
              decoration: const InputDecoration(
                labelText: '选择已有区域数据',
                border: OutlineInputBorder(),
              ),
              items: widget.areaTemplateOptions
                  .map(
                    (e) => DropdownMenuItem<int>(
                      value: e.areaId,
                      child: Text(e.label, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (val) => setState(() => _sourceAreaId = val),
            ),
          const SizedBox(height: 8),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('复用后立即继续编辑', style: TextStyle(fontSize: 13)),
            value: _continueEditAfterReuse,
            onChanged: (value) =>
                setState(() => _continueEditAfterReuse = value),
          ),
        ],
      ],
    );
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入标签名称')));
      return;
    }
    if (_selectedDimension == TagDimension.area &&
        _areaSetupMode == 'reuse' &&
        _sourceAreaId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请选择要复用的区域数据')));
      return;
    }
    Navigator.pop(context, {
      'action': 'save',
      'name': name,
      'color': _selectedColor,
      'dimension': _selectedDimension,
      'areaSetupMode': _areaSetupMode,
      'sourceAreaId': _sourceAreaId,
      'continueEditAfterReuse': _continueEditAfterReuse,
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initialName != null;
    return AlertDialog(
      title: Text(isEdit ? '编辑标签' : '新建标签'),
      content: SizedBox(
        width: 300,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '标签名称',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: _selectedDimension,
                decoration: const InputDecoration(
                  labelText: '标签分组',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  TagDimension.phase,
                  TagDimension.spawn,
                  TagDimension.purpose,
                  TagDimension.area,
                  TagDimension.custom,
                ]
                    .map(
                      (dim) => DropdownMenuItem(
                        value: dim,
                        child: Text(TagDimension.getName(dim)),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val == null) return;
                  setState(() {
                    _selectedDimension = val;
                    if (_selectedDimension != TagDimension.area) {
                      _areaSetupMode = 'none';
                      _sourceAreaId = null;
                    }
                  });
                },
              ),
              if (_selectedDimension == TagDimension.area)
                _buildAreaSetupSection(),
              const SizedBox(height: 16),
              const Text(
                '标签颜色',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              TagColorPicker(
                initialColor: _selectedColor,
                onColorSelected: (c) => _selectedColor = c,
                showPreview: false,
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (isEdit)
          TextButton(
            onPressed: () => Navigator.pop(context, {'action': 'delete'}),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: Text(isEdit ? '保存' : '创建'),
        ),
      ],
    );
  }
}

/// 弹出删除标签确认对话框（可选同步删除关联区域数据）。
Future<Map<String, dynamic>?> showDeleteTagConfirmDialog(
  BuildContext context,
  Tag tag,
  int relatedAreaCount,
) {
  bool deleteRelatedAreas = false;
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: const Text('删除标签'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '确定要删除标签 "${tag.name}" 吗？${tag.isSystem ? "\n(警告：这是一个系统预设标签)" : ""}\n关联的道具标签也将被移除。',
            ),
            if (relatedAreaCount > 0) ...[
              const SizedBox(height: 12),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: deleteRelatedAreas,
                onChanged: (value) =>
                    setDialogState(() => deleteRelatedAreas = value ?? false),
                title: Text('同时删除区域数据（$relatedAreaCount 条）'),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, {
              'confirm': true,
              'deleteRelatedAreas': deleteRelatedAreas,
            }),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color.fromARGB(255, 248, 121, 121),
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    ),
  );
}

/// 弹出分组重命名对话框。
Future<String?> showRenameTagGroupDialog(
  BuildContext context,
  int dimension,
) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _RenameTagGroupDialog(
      initialName: TagDimension.getName(dimension),
    ),
  );
}

class _RenameTagGroupDialog extends StatefulWidget {
  final String initialName;

  const _RenameTagGroupDialog({required this.initialName});

  @override
  State<_RenameTagGroupDialog> createState() => _RenameTagGroupDialogState();
}

class _RenameTagGroupDialogState extends State<_RenameTagGroupDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('重命名分组'),
      content: TextField(
        controller: _controller,
        decoration: const InputDecoration(
          labelText: '分组名称',
          border: OutlineInputBorder(),
        ),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

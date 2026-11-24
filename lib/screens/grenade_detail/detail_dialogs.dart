import 'package:flutter/material.dart';

import '../../services/favorite_folder_service.dart';

/// 添加步骤弹窗触发的保存动作类型。
enum AddStepAction { textOnly, withImage, withVideo }

/// 添加步骤弹窗的表单提交结果。
typedef AddStepResult = ({
  AddStepAction action,
  String title,
  String description,
});

/// 编辑步骤弹窗的表单提交结果。
typedef EditStepResult = ({String title, String description});

/// 编辑原始出处弹窗的表单提交结果。
typedef EditSourceResult = ({String url, String note});

/// 弹出新建收藏夹名称输入弹窗，取消返回 null。
Future<String?> showCreateFavoriteFolderDialog(BuildContext context) async {
  final controller = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('新建收藏夹'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: '输入收藏夹名称'),
        onSubmitted: (_) => Navigator.pop(ctx, true),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('创建'),
        ),
      ],
    ),
  );
  if (ok != true) return null;
  return controller.text.trim();
}

/// 弹出收藏夹单选与新建弹窗，取消返回 null。
Future<int?> showFavoriteFolderPickerDialog(
  BuildContext context, {
  required FavoriteFolderService folderService,
  required int mapId,
}) async {
  var folders = await folderService.getFoldersByMap(mapId);
  if (folders.isEmpty) {
    await folderService.getOrCreateDefaultFolder(mapId);
    folders = await folderService.getFoldersByMap(mapId);
  }
  if (folders.isEmpty || !context.mounted) return null;

  int? selectedFolderId = folders.first.id;
  return showDialog<int>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: const Text('选择收藏夹'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...folders.map(
                (f) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    selectedFolderId == f.id
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: selectedFolderId == f.id
                        ? Theme.of(ctx).colorScheme.primary
                        : Theme.of(ctx).disabledColor,
                  ),
                  title: Text(f.name, overflow: TextOverflow.ellipsis),
                  onTap: () => setDialogState(() => selectedFolderId = f.id),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    final name = await showCreateFavoriteFolderDialog(ctx);
                    if (name == null || name.isEmpty) return;
                    try {
                      final created =
                          await folderService.createFolder(mapId, name);
                      folders = await folderService.getFoldersByMap(mapId);
                      if (!ctx.mounted) return;
                      setDialogState(() {
                        selectedFolderId = created.id;
                      });
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('创建失败：$e')),
                      );
                    }
                  },
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: const Text('新建收藏夹'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: selectedFolderId == null
                ? null
                : () => Navigator.pop(ctx, selectedFolderId),
            child: const Text('确定'),
          ),
        ],
      ),
    ),
  );
}

/// 弹出清除爆点或穿线确认弹窗，取消返回 false。
Future<bool?> showClearImpactPointDialog(
  BuildContext context, {
  required bool isWallbang,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(isWallbang ? '清除穿线' : '清除爆点'),
      content: Text(isWallbang ? '确定要清除已设置的穿线吗？' : '确定要清除已设置的爆点吗？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('清除', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
}

/// 弹出通用删除确认弹窗，取消返回 null，确认返回 true。
Future<bool?> showDetailDeleteConfirmDialog(
  BuildContext context, {
  required String title,
  required String content,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('删除', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
}

/// 弹出标题未保存退出确认弹窗，返回 cancel/discard/save 或 null。
Future<String?> showUnsavedTitleDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('标题未保存'),
      content: const Text('您修改了道具标题但尚未保存，要如何处理？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'cancel'),
          child: const Text('继续编辑'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'discard'),
          child: const Text('放弃修改', style: TextStyle(color: Colors.red)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'save'),
          child: const Text('保存并退出', style: TextStyle(color: Colors.green)),
        ),
      ],
    ),
  );
}

/// 弹出新增步骤底部表单，取消返回 null。
Future<AddStepResult?> showAddStepBottomSheet(BuildContext context) {
  final titleController = TextEditingController();
  final descController = TextEditingController();

  return showModalBottomSheet<AddStepResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        top: 20,
        left: 20,
        right: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '添加步骤',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Theme.of(ctx).textTheme.bodyLarge?.color,
            ),
          ),
          const SizedBox(height: 15),
          TextField(
            controller: titleController,
            decoration: InputDecoration(
              labelText: '步骤标题 (可选)',
              hintText: '例如：站位、瞄点',
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: Theme.of(ctx).colorScheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: descController,
            autofocus: true,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: '说明文字',
              hintText: '在此输入详细操作说明...',
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: Theme.of(ctx).colorScheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              if (descController.text.trim().isEmpty &&
                  titleController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请至少输入标题或说明')),
                );
                return;
              }
              Navigator.pop(
                ctx,
                (
                  action: AddStepAction.textOnly,
                  title: titleController.text,
                  description: descController.text,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey[800],
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: const Text(
              '保存 (仅文字)',
              style: TextStyle(color: Colors.white),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(
                    ctx,
                    (
                      action: AddStepAction.withImage,
                      title: titleController.text,
                      description: descController.text,
                    ),
                  ),
                  icon: const Icon(Icons.image, color: Colors.black),
                  label: const Text(
                    '加图并保存',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(
                    ctx,
                    (
                      action: AddStepAction.withVideo,
                      title: titleController.text,
                      description: descController.text,
                    ),
                  ),
                  icon: const Icon(Icons.videocam, color: Colors.white),
                  label: const Text(
                    '加视频并保存',
                    style: TextStyle(color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// 弹出编辑步骤文字底部表单，取消返回 null。
Future<EditStepResult?> showEditStepBottomSheet(
  BuildContext context, {
  required String initialTitle,
  required String initialDescription,
}) {
  final titleController = TextEditingController(text: initialTitle);
  final descController = TextEditingController(text: initialDescription);

  return showModalBottomSheet<EditStepResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        top: 20,
        left: 20,
        right: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '编辑步骤',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Theme.of(ctx).textTheme.bodyLarge?.color,
            ),
          ),
          const SizedBox(height: 15),
          TextField(
            controller: titleController,
            decoration: InputDecoration(
              labelText: '步骤标题',
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: Theme.of(ctx).colorScheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: descController,
            autofocus: true,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: '说明文字',
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: Theme.of(ctx).colorScheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => Navigator.pop(
              ctx,
              (
                title: titleController.text,
                description: descController.text,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text(
              '保存修改',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// 弹出编辑作者底部表单，取消返回 null。
Future<String?> showEditAuthorBottomSheet(
  BuildContext context, {
  required String initialAuthor,
  required List<String> authorHistory,
  required String defaultAuthor,
}) {
  final authorController = TextEditingController(text: initialAuthor);

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setModalState) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          top: 20,
          left: 20,
          right: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '编辑作者',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(ctx).textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 15),
            if (authorHistory.isNotEmpty) ...[
              const Text(
                '历史作者',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: authorHistory
                    .map(
                      (author) => ActionChip(
                        label: Text(author),
                        onPressed: () {
                          setModalState(() {
                            authorController.text = author;
                          });
                        },
                        backgroundColor: authorController.text == author
                            ? Colors.orange.withValues(alpha: 0.3)
                            : null,
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 15),
            ],
            TextField(
              controller: authorController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: '作者名',
                hintText: '留空则使用默认: $defaultAuthor',
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Theme.of(ctx).colorScheme.surfaceContainerHighest,
              ),
              onChanged: (_) => setModalState(() {}),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, authorController.text.trim()),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text(
                '保存',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 弹出编辑原始出处底部表单，取消返回 null。
Future<EditSourceResult?> showEditSourceBottomSheet(
  BuildContext context, {
  required String initialUrl,
  required String initialNote,
}) {
  final urlController = TextEditingController(text: initialUrl);
  final noteController = TextEditingController(text: initialNote);

  return showModalBottomSheet<EditSourceResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        top: 20,
        left: 20,
        right: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '编辑原始出处',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Theme.of(ctx).textTheme.bodyLarge?.color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '记录道具的来源，方便溯源和致谢原作者',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 15),
          TextField(
            controller: urlController,
            decoration: InputDecoration(
              labelText: '出处链接',
              hintText: '输入视频/帖子链接（可选）',
              prefixIcon: const Icon(Icons.link),
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: Theme.of(ctx).colorScheme.surfaceContainerHighest,
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 15),
          TextField(
            controller: noteController,
            decoration: InputDecoration(
              labelText: '备注',
              hintText: '例如：来源于xxx的教程（可选）',
              prefixIcon: const Icon(Icons.notes),
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: Theme.of(ctx).colorScheme.surfaceContainerHighest,
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => Navigator.pop(
              ctx,
              (
                url: urlController.text.trim(),
                note: noteController.text.trim(),
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text(
              '保存',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

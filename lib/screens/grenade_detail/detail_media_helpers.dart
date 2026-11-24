import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:isar_community/isar.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:pro_image_editor/designs/frosted_glass/frosted_glass.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

import '../../models.dart';
import '../../services/data_service.dart';

/// 媒体导入来源选项。
enum DetailMediaSource { gallery, clipboard }

/// 弹出媒体来源底部选择面板。
Future<DetailMediaSource?> showDetailMediaSourcePicker(
  BuildContext context,
  bool isImage,
) {
  return showModalBottomSheet<DetailMediaSource>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isImage ? '选择图片来源' : '选择视频来源',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Theme.of(ctx).textTheme.bodyLarge?.color,
            ),
          ),
          const SizedBox(height: 20),
          ListTile(
            leading: const Icon(Icons.photo_library, color: Colors.blueAccent),
            title: const Text('从图库选择'),
            onTap: () => Navigator.pop(ctx, DetailMediaSource.gallery),
          ),
          ListTile(
            leading:
                const Icon(Icons.content_paste, color: Colors.orangeAccent),
            title: const Text('从剪切板粘贴'),
            subtitle: const Text('读取已复制的媒体文件'),
            onTap: () => Navigator.pop(ctx, DetailMediaSource.clipboard),
          ),
          const SizedBox(height: 10),
        ],
      ),
    ),
  );
}

/// 构建详情页统一的图片涂鸦编辑器中文配置。
ProImageEditorConfigs buildDetailImageEditorConfigs() {
  return ProImageEditorConfigs(
    designMode: ImageEditorDesignMode.cupertino,
    theme: ThemeData.dark().copyWith(
      scaffoldBackgroundColor: Colors.black,
      iconTheme: const IconThemeData(color: Colors.white),
    ),
    mainEditor: MainEditorConfigs(
      tools: const [
        SubEditorMode.paint,
        SubEditorMode.text,
        SubEditorMode.cropRotate,
        SubEditorMode.tune,
        SubEditorMode.filter,
        SubEditorMode.blur,
        SubEditorMode.emoji,
      ],
      widgets: MainEditorWidgets(
        appBar: (editor, rebuildStream) => null,
        bottomBar: (editor, rebuildStream, key) => null,
        bodyItems: (editor, rebuildStream) => [
          ReactiveWidget(
            stream: rebuildStream,
            builder: (_) => FrostedGlassActionBar(
              editor: editor,
              openStickerEditor: () {},
            ),
          ),
        ],
      ),
    ),
    paintEditor: PaintEditorConfigs(
      widgets: PaintEditorWidgets(
        appBar: (paintEditor, rebuildStream) => null,
        bottomBar: (paintEditor, rebuildStream) => null,
        bodyItems: (paintEditor, rebuildStream) => [
          ReactiveWidget(
            stream: rebuildStream,
            builder: (_) => paintEditor.isActive
                ? const SizedBox.shrink()
                : FrostedGlassPaintAppbar(paintEditor: paintEditor),
          ),
          ReactiveWidget(
            stream: rebuildStream,
            builder: (_) =>
                FrostedGlassPaintBottomBar(paintEditor: paintEditor),
          ),
        ],
      ),
    ),
    textEditor: TextEditorConfigs(
      widgets: TextEditorWidgets(
        appBar: (textEditor, rebuildStream) => null,
        bottomBar: (textEditor, rebuildStream) => null,
        bodyItems: (textEditor, rebuildStream) => [
          ReactiveWidget(
            stream: rebuildStream,
            builder: (_) => const FrostedGlassEffect(
              radius: BorderRadius.zero,
              child: SizedBox.expand(),
            ),
          ),
          ReactiveWidget(
            stream: rebuildStream,
            builder: (_) => FrostedGlassTextAppbar(textEditor: textEditor),
          ),
          ReactiveWidget(
            stream: rebuildStream,
            builder: (_) => FrostedGlassTextBottomBar(
              configs: textEditor.configs,
              initColor: textEditor.primaryColor,
              onColorChanged: (color) => textEditor.primaryColor = color,
              selectedStyle: textEditor.selectedTextStyle,
              onFontChange: textEditor.setTextStyle,
            ),
          ),
        ],
      ),
    ),
    cropRotateEditor: CropRotateEditorConfigs(
      widgets: CropRotateEditorWidgets(
        appBar: (cropRotateEditor, rebuildStream) => null,
        bottomBar: (cropRotateEditor, rebuildStream) => ReactiveWidget(
          stream: rebuildStream,
          builder: (_) => FrostedGlassCropRotateToolbar(
            configs: cropRotateEditor.configs,
            onCancel: cropRotateEditor.close,
            onRotate: cropRotateEditor.rotate,
            onDone: cropRotateEditor.done,
            onReset: cropRotateEditor.reset,
            openAspectRatios: cropRotateEditor.openAspectRatioOptions,
          ),
        ),
      ),
    ),
    filterEditor: FilterEditorConfigs(
      widgets: FilterEditorWidgets(
        appBar: (filterEditor, rebuildStream) => null,
        bodyItems: (filterEditor, rebuildStream) => [
          ReactiveWidget(
            stream: rebuildStream,
            builder: (_) =>
                FrostedGlassFilterAppbar(filterEditor: filterEditor),
          ),
        ],
      ),
    ),
    blurEditor: BlurEditorConfigs(
      widgets: BlurEditorWidgets(
        appBar: (blurEditor, rebuildStream) => null,
        bodyItems: (blurEditor, rebuildStream) => [
          ReactiveWidget(
            stream: rebuildStream,
            builder: (_) => FrostedGlassBlurAppbar(blurEditor: blurEditor),
          ),
        ],
      ),
    ),
    tuneEditor: TuneEditorConfigs(
      widgets: TuneEditorWidgets(
        appBar: (tuneEditor, rebuildStream) => null,
        bottomBar: (tuneEditor, rebuildStream) => null,
        bodyItems: (tuneEditor, rebuildStream) => [
          ReactiveWidget(
            stream: rebuildStream,
            builder: (_) => FrostedGlassTuneAppbar(tuneEditor: tuneEditor),
          ),
          ReactiveWidget(
            stream: rebuildStream,
            builder: (_) => FrostedGlassTuneBottombar(tuneEditor: tuneEditor),
          ),
        ],
      ),
    ),
    dialogConfigs: DialogConfigs(
      widgets: DialogWidgets(
        loadingDialog: (message, configs) => FrostedGlassLoadingDialog(
          message: message,
          configs: configs,
        ),
      ),
    ),
    i18n: const I18n(
      various: I18nVarious(
        loadingDialogMsg: '正在处理...',
        closeEditorWarningTitle: '确认关闭',
        closeEditorWarningMessage: '确定要关闭编辑器吗？未保存的更改将丢失',
        closeEditorWarningConfirmBtn: '确定',
        closeEditorWarningCancelBtn: '取消',
      ),
      paintEditor: I18nPaintEditor(
        bottomNavigationBarText: '画笔',
        freestyle: '自由线',
        arrow: '箭头',
        line: '直线',
        rectangle: '矩形',
        circle: '圆形',
        dashLine: '虚线',
        lineWidth: '线宽',
        toggleFill: '填充',
        undo: '撤销',
        redo: '重做',
        done: '完成',
        back: '返回',
      ),
      textEditor: I18nTextEditor(
        inputHintText: '输入文字',
        bottomNavigationBarText: '文字',
        done: '完成',
        back: '返回',
        textAlign: '对齐',
        backgroundMode: '背景模式',
      ),
      cropRotateEditor: I18nCropRotateEditor(
        bottomNavigationBarText: '裁剪',
        rotate: '旋转',
        ratio: '比例',
        back: '返回',
        done: '完成',
        reset: '重置',
        undo: '撤销',
        redo: '重做',
      ),
      filterEditor: I18nFilterEditor(
        bottomNavigationBarText: '滤镜',
        back: '返回',
        done: '完成',
      ),
      blurEditor: I18nBlurEditor(
        bottomNavigationBarText: '模糊',
        back: '返回',
        done: '完成',
      ),
      tuneEditor: I18nTuneEditor(
        bottomNavigationBarText: '调色',
        back: '返回',
        done: '完成',
        brightness: '亮度',
        contrast: '对比度',
        saturation: '饱和度',
        exposure: '曝光',
        hue: '色调',
        temperature: '色温',
        sharpness: '锐度',
        fade: '褪色',
        luminance: '明度',
      ),
      emojiEditor: I18nEmojiEditor(bottomNavigationBarText: '表情'),
      cancel: '取消',
      undo: '撤销',
      redo: '重做',
      done: '完成',
      remove: '删除',
    ),
  );
}

/// 打开图片涂鸦编辑器并在确认后触发回调与关闭编辑器路由。
Future<void> openDetailImageEditor(
  BuildContext context, {
  required File file,
  required Future<void> Function(Uint8List bytes) onSave,
}) async {
  await Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (editorContext) => ProImageEditor.file(
        file,
        callbacks: ProImageEditorCallbacks(
          onImageEditingComplete: (Uint8List bytes) async {
            await onSave(bytes);
            if (editorContext.mounted) {
              Navigator.pop(editorContext);
            }
          },
        ),
        configs: buildDetailImageEditorConfigs(),
      ),
    ),
  );
}

Future<String?> _editAndSaveNewImage(
  BuildContext context,
  File sourceFile,
  String dataPath,
) async {
  String? resultPath;
  await openDetailImageEditor(
    context,
    file: sourceFile,
    onSave: (bytes) async {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savePath = p.join(dataPath, fileName);
      await File(savePath).writeAsBytes(bytes);
      resultPath = savePath;
    },
  );
  return resultPath;
}

/// 从剪贴板读取图片并经涂鸦编辑器保存为步骤图片文件。
Future<String?> processImageFromClipboard(
  BuildContext context,
  String dataPath,
) async {
  final imageBytes = await Pasteboard.image;
  File? tempFile;
  var createdTempFile = false;

  if (imageBytes != null && imageBytes.isNotEmpty) {
    final tempDir = await getTemporaryDirectory();
    final tempPath = p.join(
      tempDir.path,
      '_clipboard_temp_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    tempFile = File(tempPath);
    await tempFile.writeAsBytes(imageBytes);
    createdTempFile = true;
  } else {
    final files = await Pasteboard.files();
    for (final filePath in files) {
      final ext = p.extension(filePath).toLowerCase();
      if (DataService.trackedImageExtensions.contains(ext) && ext != '.svg') {
        tempFile = File(filePath);
        break;
      }
    }
  }

  if (tempFile == null || !tempFile.existsSync()) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('剪切板中没有找到图片')),
      );
    }
    return null;
  }

  try {
    if (!context.mounted) return null;
    return await _editAndSaveNewImage(context, tempFile, dataPath);
  } finally {
    if (createdTempFile) {
      await DataService.deleteMediaFile(tempFile.path);
    }
  }
}

/// 从剪贴板文件列表中读取视频并复制到数据目录。
Future<String?> processVideoFromClipboard(
  BuildContext context,
  String dataPath,
) async {
  final files = await Pasteboard.files();
  if (files.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('剪切板中没有找到文件')),
      );
    }
    return null;
  }

  String? videoPath;
  for (final filePath in files) {
    final ext = p.extension(filePath).toLowerCase();
    if (DataService.trackedVideoExtensions.contains(ext)) {
      videoPath = filePath;
      break;
    }
  }

  if (videoPath == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('剪切板中没有找到视频文件')),
      );
    }
    return null;
  }

  try {
    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}${p.extension(videoPath)}';
    final savePath = p.join(dataPath, fileName);
    await File(videoPath).copy(savePath);
    return savePath;
  } catch (e) {
    debugPrint('Video copy error: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('复制视频失败: $e')),
      );
    }
    return null;
  }
}

/// 拾取并处理新媒体文件（桌面端支持图库或剪贴板）。
Future<String?> pickAndProcessDetailMedia(
  BuildContext context, {
  required String dataPath,
  required bool isImage,
}) async {
  // 仅桌面端提供来源选择，移动端直接打开系统图库
  final isDesktop = Platform.isWindows || Platform.isLinux;
  if (isDesktop) {
    final source = await showDetailMediaSourcePicker(context, isImage);
    if (source == null || !context.mounted) return null;
    if (source == DetailMediaSource.clipboard) {
      return isImage
          ? processImageFromClipboard(context, dataPath)
          : processVideoFromClipboard(context, dataPath);
    }
  }

  final picker = ImagePicker();
  if (isImage) {
    final xFile = await picker.pickImage(source: ImageSource.gallery);
    if (xFile == null || !context.mounted) return null;
    return _editAndSaveNewImage(context, File(xFile.path), dataPath);
  }

  final xFile = await picker.pickVideo(source: ImageSource.gallery);
  if (xFile == null || !context.mounted) return null;
  try {
    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}${p.extension(xFile.path)}';
    final savePath = p.join(dataPath, fileName);
    await File(xFile.path).copy(savePath);
    return savePath;
  } catch (e) {
    debugPrint('Video copy error: $e');
    return null;
  }
}

/// 重新编辑步骤图片，写库失败时自动回滚并清理临时文件。
Future<bool> editDetailStepImage(
  BuildContext context, {
  required Isar isar,
  required Grenade grenade,
  required StepMedia media,
  required Future<void> Function() onCommitted,
}) async {
  if (media.type != MediaType.image) return false;
  final file = File(media.localPath);
  if (!file.existsSync() || !context.mounted) return false;

  final dataService = DataService(isar);
  final dataPath = isar.directory ?? '';
  var updated = false;

  await openDetailImageEditor(
    context,
    file: file,
    onSave: (bytes) async {
      final previousPath = media.localPath;
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savePath = p.join(dataPath, fileName);
      await File(savePath).writeAsBytes(bytes);

      media.localPath = savePath;
      try {
        await isar.writeTxn(() async {
          await isar.stepMedias.put(media);
          grenade.updatedAt = DateTime.now();
          await isar.grenades.put(grenade);
        });
      } catch (_) {
        media.localPath = previousPath;
        await DataService.deleteMediaFile(savePath);
        rethrow;
      }

      if (previousPath != savePath) {
        await dataService.deleteMediaFileIfUnused(
          previousPath,
          excludingMediaId: media.id,
        );
      }
      await onCommitted();
      updated = true;
    },
  );
  return updated;
}

/// 打开全屏可缩放图片查看页。
void showFullscreenDetailImage(BuildContext context, String imagePath) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (pageContext) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.pop(pageContext),
          ),
        ),
        extendBodyBehindAppBar: true,
        body: Center(
          child: PhotoView(
            imageProvider: FileImage(File(imagePath)),
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 3,
            backgroundDecoration: const BoxDecoration(color: Colors.black),
          ),
        ),
      ),
    ),
  );
}
